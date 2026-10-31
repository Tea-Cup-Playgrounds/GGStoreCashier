import { useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { Plus } from 'lucide-react';
import { api, errorMessage } from '../../api/client';
import { useAuth } from '../../auth/AuthContext';
import { useLocations, type Location } from '../../lib/locations';
import { Badge, Button, Checkbox, DataTable, Field, Input, Modal, PageHeader, QueryState, Select, useToast } from '../../components/ui';

export function LocationsPage() {
  const { access } = useAuth();
  const qc = useQueryClient();
  const [inactive, setInactive] = useState(false);
  const locations = useLocations(inactive);
  const [editing, setEditing] = useState<Location | 'new' | null>(null);
  // locations.manage at every location (owners) is needed to add locations or change codes/status.
  const managesAll = access.locationsFor('locations.manage') === null;

  return (
    <>
      <PageHeader
        title="Lokasi"
        description="Cabang dan gudang. Lokasi tidak pernah dihapus, hanya dinonaktifkan, agar riwayat tetap utuh."
        actions={
          managesAll && (
            <Button variant="primary" icon={<Plus className="size-4" />} onClick={() => setEditing('new')}>
              Lokasi baru
            </Button>
          )
        }
      />
      <div className="mb-4">
        <Checkbox label="Tampilkan nonaktif" checked={inactive} onChange={(e) => setInactive(e.target.checked)} />
      </div>
      <QueryState query={locations}>
        <DataTable
          rows={locations.data ?? []}
          rowKey={(l) => l.id}
          onRowClick={(l) => (access.can('locations.manage', l.id) ? setEditing(l) : undefined)}
          columns={[
            { header: 'Kode', cell: (l) => <span className="font-mono">{l.code}</span> },
            { header: 'Nama', cell: (l) => <span className="font-medium">{l.name}</span> },
            { header: 'Tipe', cell: (l) => (l.type === 'warehouse' ? <Badge tone="blue">Gudang</Badge> : <Badge>Cabang</Badge>) },
            { header: 'Alamat', cell: (l) => l.address ?? '—' },
            { header: 'Telepon', cell: (l) => l.phone ?? '—' },
            { header: 'Status', cell: (l) => (l.is_active ? <Badge tone="green">Aktif</Badge> : <Badge tone="red">Nonaktif</Badge>) },
          ]}
        />
      </QueryState>
      {editing && (
        <LocationDialog
          location={editing === 'new' ? null : editing}
          managesAll={managesAll}
          onClose={() => setEditing(null)}
          onSaved={() => qc.invalidateQueries({ queryKey: ['locations'] })}
        />
      )}
    </>
  );
}

function LocationDialog({ location, managesAll, onClose, onSaved }: { location: Location | null; managesAll: boolean; onClose: () => void; onSaved: () => void }) {
  const toast = useToast();
  const [code, setCode] = useState(location?.code ?? '');
  const [name, setName] = useState(location?.name ?? '');
  const [type, setType] = useState<Location['type']>(location?.type ?? 'branch');
  const [address, setAddress] = useState(location?.address ?? '');
  const [phone, setPhone] = useState(location?.phone ?? '');
  const [active, setActive] = useState(location?.is_active ?? true);

  const save = useMutation({
    mutationFn: () => {
      const body: Record<string, unknown> = {
        name: name.trim(),
        address: address.trim() || null,
        phone: phone.trim() || null,
      };
      if (!location) return api('/locations', { method: 'POST', body: { ...body, code: code.trim(), type } });
      if (managesAll) {
        if (code.trim().toUpperCase() !== location.code) body.code = code.trim();
        if (active !== location.is_active) body.is_active = active;
      }
      return api(`/locations/${location.id}`, { method: 'PUT', body });
    },
    onSuccess: () => {
      toast.success(location ? 'Lokasi diperbarui' : 'Lokasi dibuat');
      onSaved();
      onClose();
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  return (
    <Modal
      open
      onClose={onClose}
      title={location ? `Lokasi ${location.code}` : 'Lokasi baru'}
      footer={
        <>
          <Button onClick={onClose}>Batal</Button>
          <Button variant="primary" loading={save.isPending} disabled={!name.trim() || !code.trim()} onClick={() => save.mutate()}>
            Simpan
          </Button>
        </>
      }
    >
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="Kode" hint="2–10 karakter A–Z, 0–9, -; dipakai di nomor dokumen">
          <Input value={code} onChange={(e) => setCode(e.target.value.toUpperCase())} disabled={!managesAll} />
        </Field>
        <Field label="Tipe">
          <Select value={type} onChange={(e) => setType(e.target.value as Location['type'])} disabled={!!location}>
            <option value="branch">Cabang</option>
            <option value="warehouse">Gudang</option>
          </Select>
        </Field>
        <Field label="Nama" className="sm:col-span-2">
          <Input value={name} onChange={(e) => setName(e.target.value)} />
        </Field>
        <Field label="Alamat" className="sm:col-span-2">
          <Input value={address} onChange={(e) => setAddress(e.target.value)} />
        </Field>
        <Field label="Telepon">
          <Input value={phone} onChange={(e) => setPhone(e.target.value)} />
        </Field>
      </div>
      {location && managesAll && (
        <div className="mt-4">
          <Checkbox label="Aktif" checked={active} onChange={(e) => setActive(e.target.checked)} />
        </div>
      )}
    </Modal>
  );
}
