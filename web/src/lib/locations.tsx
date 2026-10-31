import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { api } from '../api/client';
import { useAuth } from '../auth/AuthContext';
import { Field, Select } from '../components/ui';

export interface Location {
  id: number;
  code: string;
  name: string;
  type: 'branch' | 'warehouse';
  address: string | null;
  phone: string | null;
  is_active: boolean;
  settings: Record<string, unknown> | null;
}

/** Locations the user is assigned to (every location for owners). */
export function useLocations(includeInactive = false) {
  return useQuery({
    queryKey: ['locations', { includeInactive }],
    queryFn: () => api<{ locations: Location[] }>('/locations', { query: { include_inactive: includeInactive || undefined } }).then((r) => r.locations),
    staleTime: 60_000,
  });
}

/** Every active location (short form), for picking transfer destinations. */
export function useDestinations() {
  return useQuery({
    queryKey: ['locations', 'destinations'],
    queryFn: () => api<{ locations: Location[] }>('/locations', { query: { scope: 'destinations' } }).then((r) => r.locations),
    staleTime: 60_000,
  });
}

const STORAGE_KEY = 'gg.location';
const readStored = (): number | null => {
  try {
    return Number(localStorage.getItem(STORAGE_KEY)) || null;
  } catch {
    return null;
  }
};

export interface LocationChoice {
  locationId: number | null;
  setLocationId: (id: number | null) => void;
  options: Location[];
  allowAll: boolean;
  isPending: boolean;
}

/**
 * The location a page works on: one of the locations where the user holds `permission`, remembered
 * across pages. With `allowAll`, null means "every location in scope".
 */
export function useLocationChoice(permission: string, { allowAll = false } = {}): LocationChoice {
  const { access } = useAuth();
  const locations = useLocations();
  const scope = access.locationsFor(permission);
  const options = (locations.data ?? []).filter((l) => scope === null || scope.includes(l.id));
  const [stored, setStored] = useState<number | null>(readStored);
  const match = options.find((l) => l.id === stored);
  const locationId = match ? match.id : allowAll ? null : (options.find((l) => l.type === 'branch') ?? options[0])?.id ?? null;

  const setLocationId = (id: number | null) => {
    setStored(id);
    try {
      if (id === null) localStorage.removeItem(STORAGE_KEY);
      else localStorage.setItem(STORAGE_KEY, String(id));
    } catch {
      // Storage unavailable (private mode): the choice just isn't remembered.
    }
  };
  return { locationId, setLocationId, options, allowAll, isPending: locations.isPending };
}

export function LocationSelect({ choice, label = 'Lokasi' }: { choice: LocationChoice; label?: string }) {
  return (
    <Field label={label} className="w-56">
      <Select
        value={choice.locationId ?? ''}
        onChange={(e) => choice.setLocationId(e.target.value ? Number(e.target.value) : null)}
        disabled={choice.isPending}
      >
        {choice.allowAll && <option value="">Semua lokasi</option>}
        {choice.options.map((l) => (
          <option key={l.id} value={l.id}>
            {l.name} ({l.code})
          </option>
        ))}
      </Select>
    </Field>
  );
}

export const locationName = (locations: Location[] | undefined, id: number | null | undefined): string =>
  id == null ? 'Semua lokasi' : locations?.find((l) => l.id === id)?.name ?? `#${id}`;
