import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Search } from 'lucide-react';
import { api } from '../api/client';
import type { Brand, Category, Grade, Product, ProductKind, TaxRate, UnitStatus, Variant } from '../api/types';
import { Badge, Input, Spinner, type Tone } from '../components/ui';
import { formatRp } from './format';

export const useCategories = () =>
  useQuery({ queryKey: ['categories'], queryFn: () => api<{ categories: Category[] }>('/categories').then((r) => r.categories), staleTime: 60_000 });

export const useBrands = () =>
  useQuery({ queryKey: ['brands'], queryFn: () => api<{ brands: Brand[] }>('/catalog/brands').then((r) => r.brands), staleTime: 60_000 });

export const useTaxRates = () =>
  useQuery({ queryKey: ['tax-rates'], queryFn: () => api<{ taxRates: TaxRate[] }>('/catalog/tax-rates').then((r) => r.taxRates), staleTime: 60_000 });

export const KIND_LABELS: Record<ProductKind, string> = { goods: 'Barang', service: 'Jasa', digital: 'Digital / pulsa' };

export const UNIT_STATUS: Record<UnitStatus, [string, Tone]> = {
  in_stock: ['Tersedia', 'green'],
  in_transit: ['Dalam pengiriman', 'blue'],
  reserved: ['Dipesan', 'amber'],
  sold: ['Terjual', 'gray'],
  returned: ['Diretur', 'amber'],
  in_service: ['Servis', 'amber'],
  defective: ['Rusak', 'red'],
  written_off: ['Dihapus', 'red'],
};

export const GRADES: Array<[Grade, string]> = [
  ['new', 'Baru'],
  ['A', 'Bekas A'],
  ['B', 'Bekas B'],
  ['C', 'Bekas C'],
];

export const unitStatusBadge = (status: UnitStatus) => {
  const [label, tone] = UNIT_STATUS[status] ?? [status, 'gray'];
  return <Badge tone={tone}>{label}</Badge>;
};

/** The identifier to show for a unit: IMEI 1 (+ IMEI 2) or serial number. */
export const unitLabel = (u: { imei1: string | null; imei2?: string | null; serial_number: string | null }) =>
  [u.imei1, u.imei2].filter(Boolean).join(' / ') || u.serial_number || 'Tanpa IMEI/serial';

export const variantName = (product: Pick<Product, 'name'>, variant: Pick<Variant, 'name'>) =>
  variant.name ? `${product.name} ${variant.name}` : product.name;

export interface PickedVariant {
  variantId: number;
  name: string;
  sku: string;
  isSerialized: boolean;
  kind: ProductKind;
  basePrice: number;
  onHand?: number;
}

/**
 * Search the catalog and pick a variant. With `locationId`, shows stock there. `goodsOnly` hides
 * services and digital products (they have no stock).
 */
export function VariantPicker({
  locationId,
  goodsOnly = true,
  onPick,
  exclude = [],
}: {
  locationId?: number | null;
  goodsOnly?: boolean;
  onPick: (variant: PickedVariant) => void;
  exclude?: number[];
}) {
  const [search, setSearch] = useState('');
  const term = search.trim();
  const results = useQuery({
    queryKey: ['variant-picker', term, locationId, goodsOnly],
    queryFn: () =>
      api<{ products: Product[] }>('/catalog/products', {
        query: { search: term, location_id: locationId ?? undefined, kind: goodsOnly ? 'goods' : undefined, limit: 20 },
      }).then((r) => r.products),
    enabled: term.length >= 2,
  });

  const rows = (results.data ?? []).flatMap((p) =>
    p.variants
      .filter((v) => !exclude.includes(v.id))
      .map((v) => ({ product: p, variant: v })),
  );

  return (
    <div>
      <div className="relative">
        <Search className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-stone-400" />
        <Input className="pl-9" placeholder="Cari produk, SKU, atau barcode (min. 2 huruf)…" value={search} onChange={(e) => setSearch(e.target.value)} autoFocus />
      </div>
      {term.length >= 2 && (
        <div className="mt-2 max-h-72 overflow-y-auto rounded-lg border border-stone-200">
          {results.isFetching && rows.length === 0 ? (
            <div className="flex justify-center p-4">
              <Spinner className="size-5" />
            </div>
          ) : rows.length === 0 ? (
            <div className="p-4 text-center text-sm text-stone-500">Tidak ditemukan</div>
          ) : (
            rows.map(({ product, variant }) => (
              <button
                key={variant.id}
                type="button"
                onClick={() => {
                  onPick({
                    variantId: variant.id,
                    name: variantName(product, variant),
                    sku: variant.sku,
                    isSerialized: product.is_serialized,
                    kind: product.kind,
                    basePrice: Number(variant.sell_price ?? variant.base_price),
                    onHand: variant.on_hand,
                  });
                  setSearch('');
                }}
                className="flex w-full items-center justify-between gap-3 border-b border-stone-100 px-3 py-2 text-left text-sm last:border-0 hover:bg-brand-50"
              >
                <span>
                  <span className="font-medium">{variantName(product, variant)}</span>
                  <span className="ml-2 font-mono text-xs text-stone-500">{variant.sku}</span>
                  {product.is_serialized && <span className="ml-2"><Badge tone="blue">IMEI</Badge></span>}
                </span>
                <span className="text-right text-xs whitespace-nowrap text-stone-500">
                  {variant.on_hand !== undefined && <span className="mr-3">Stok {variant.on_hand}</span>}
                  {formatRp(variant.sell_price ?? variant.base_price)}
                </span>
              </button>
            ))
          )}
        </div>
      )}
    </div>
  );
}
