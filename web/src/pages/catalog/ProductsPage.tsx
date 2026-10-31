import { useState } from 'react';
import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useNavigate } from 'react-router';
import { Plus, Trash2 } from 'lucide-react';
import { api, errorMessage } from '../../api/client';
import type { Pagination as Page, Product, ProductKind, SerialType } from '../../api/types';
import { useAuth } from '../../auth/AuthContext';
import { KIND_LABELS, useBrands, useCategories, useTaxRates } from '../../lib/catalog';
import { formatRp, toNumber } from '../../lib/format';
import { Badge, Button, Checkbox, DataTable, Field, Input, Modal, PageHeader, Pagination, QueryState, Select, Textarea, Toolbar, useToast } from '../../components/ui';

export function ProductsPage() {
  const { access } = useAuth();
  const navigate = useNavigate();
  const [search, setSearch] = useState('');
  const [categoryId, setCategoryId] = useState('');
  const [kind, setKind] = useState('');
  const [inactive, setInactive] = useState(false);
  const [page, setPage] = useState(1);
  const [creating, setCreating] = useState(false);
  const categories = useCategories();

  const products = useQuery({
    queryKey: ['products', { search, categoryId, kind, inactive, page }],
    queryFn: () =>
      api<{ products: Product[]; pagination: Page }>('/catalog/products', {
        query: { search, category_id: categoryId, kind, include_inactive: inactive || undefined, page, limit: 30 },
      }),
    placeholderData: keepPreviousData,
  });

  const priceRange = (p: Product) => {
    const prices = p.variants.map((v) => toNumber(v.base_price));
    if (prices.length === 0) return '—';
    const min = Math.min(...prices);
    const max = Math.max(...prices);
    return min === max ? formatRp(min) : `${formatRp(min)} – ${formatRp(max)}`;
  };

  return (
    <>
      <PageHeader
        title="Produk"
        description="Katalog bersama untuk semua lokasi. Harga di sini adalah harga dasar; harga per lokasi diatur di halaman Stok."
        actions={
          access.can('catalog.manage') && (
            <Button variant="primary" icon={<Plus className="size-4" />} onClick={() => setCreating(true)}>
              Produk baru
            </Button>
          )
        }
      />
      <Toolbar>
        <Field label="Cari" className="w-64">
          <Input placeholder="Nama, SKU, barcode" value={search} onChange={(e) => { setSearch(e.target.value); setPage(1); }} />
        </Field>
        <Field label="Kategori" className="w-48">
          <Select value={categoryId} onChange={(e) => { setCategoryId(e.target.value); setPage(1); }}>
            <option value="">Semua</option>
            {categories.data?.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
          </Select>
        </Field>
        <Field label="Jenis" className="w-40">
          <Select value={kind} onChange={(e) => { setKind(e.target.value); setPage(1); }}>
            <option value="">Semua</option>
            {Object.entries(KIND_LABELS).map(([k, label]) => <option key={k} value={k}>{label}</option>)}
          </Select>
        </Field>
        <div className="pb-2.5">
          <Checkbox label="Tampilkan nonaktif" checked={inactive} onChange={(e) => { setInactive(e.target.checked); setPage(1); }} />
        </div>
      </Toolbar>
      <QueryState query={products}>
        <DataTable
          rows={products.data?.products ?? []}
          rowKey={(p) => p.id}
          onRowClick={(p) => navigate(`/catalog/${p.id}`)}
          columns={[
            {
              header: 'Produk',
              cell: (p) => (
                <div>
                  <div className="font-medium">{p.name}</div>
                  <div className="text-xs text-stone-500">{[p.brand_name, p.category_name].filter(Boolean).join(' · ') || '—'}</div>
                </div>
              ),
            },
            {
              header: 'Jenis',
              cell: (p) => (
                <div className="flex flex-wrap gap-1">
                  <Badge>{KIND_LABELS[p.kind]}</Badge>
                  {p.is_serialized && <Badge tone="blue">{p.serial_type === 'serial' ? 'Serial' : 'IMEI'}</Badge>}
                  {!p.is_active && <Badge tone="red">Nonaktif</Badge>}
                </div>
              ),
            },
            { header: 'Varian', align: 'right', cell: (p) => p.variants.length },
            { header: 'Harga dasar', align: 'right', cell: priceRange },
          ]}
        />
        <Pagination page={page} totalPages={products.data?.pagination.totalPages ?? 1} onChange={setPage} />
      </QueryState>
      {creating && <CreateProductDialog onClose={() => setCreating(false)} onCreated={(id) => navigate(`/catalog/${id}`)} />}
    </>
  );
}

interface VariantRow {
  name: string;
  sku: string;
  barcode: string;
  base_price: string;
}

export function CreateProductDialog({ onClose, onCreated }: { onClose: () => void; onCreated: (id: number) => void }) {
  const qc = useQueryClient();
  const toast = useToast();
  const categories = useCategories();
  const brands = useBrands();
  const taxRates = useTaxRates();
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [categoryId, setCategoryId] = useState('');
  const [brandId, setBrandId] = useState('');
  const [kind, setKind] = useState<ProductKind>('goods');
  const [serialType, setSerialType] = useState<SerialType | ''>('');
  const [warranty, setWarranty] = useState('0');
  const [taxRateId, setTaxRateId] = useState('');
  const [variants, setVariants] = useState<VariantRow[]>([{ name: '', sku: '', barcode: '', base_price: '' }]);

  const create = useMutation({
    mutationFn: () =>
      api<{ product: Product }>('/catalog/products', {
        method: 'POST',
        body: {
          name: name.trim(),
          description: description.trim() || null,
          category_id: categoryId || null,
          brand_id: brandId || null,
          kind,
          is_serialized: kind === 'goods' && serialType !== '',
          serial_type: serialType || undefined,
          warranty_months: Number(warranty) || 0,
          tax_rate_id: taxRateId || null,
          variants: variants.map((v) => ({
            name: v.name.trim() || null,
            sku: v.sku.trim() || undefined,
            barcode: v.barcode.trim() || null,
            base_price: Number(v.base_price),
          })),
        },
      }),
    onSuccess: (res) => {
      toast.success('Produk dibuat');
      qc.invalidateQueries({ queryKey: ['products'] });
      onClose();
      onCreated(res.product.id);
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  const setVariant = (i: number, patch: Partial<VariantRow>) => setVariants((vs) => vs.map((v, j) => (j === i ? { ...v, ...patch } : v)));
  const valid = name.trim() && variants.length > 0 && variants.every((v) => v.base_price !== '' && Number(v.base_price) >= 0);

  return (
    <Modal
      open
      wide
      onClose={onClose}
      title="Produk baru"
      footer={
        <>
          <Button onClick={onClose}>Batal</Button>
          <Button variant="primary" loading={create.isPending} disabled={!valid} onClick={() => create.mutate()}>
            Simpan
          </Button>
        </>
      }
    >
      <div className="grid gap-4 sm:grid-cols-3">
        <Field label="Nama produk" className="sm:col-span-2">
          <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="mis. Samsung Galaxy A55 5G" />
        </Field>
        <Field label="Jenis">
          <Select value={kind} onChange={(e) => { setKind(e.target.value as ProductKind); setSerialType(''); }}>
            {Object.entries(KIND_LABELS).map(([k, label]) => <option key={k} value={k}>{label}</option>)}
          </Select>
        </Field>
        <Field label="Kategori">
          <Select value={categoryId} onChange={(e) => setCategoryId(e.target.value)}>
            <option value="">—</option>
            {categories.data?.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
          </Select>
        </Field>
        <Field label="Merek">
          <Select value={brandId} onChange={(e) => setBrandId(e.target.value)}>
            <option value="">—</option>
            {brands.data?.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
          </Select>
        </Field>
        <Field label="Pajak">
          <Select value={taxRateId} onChange={(e) => setTaxRateId(e.target.value)}>
            <option value="">Default</option>
            {taxRates.data?.filter((t) => t.is_active).map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}
          </Select>
        </Field>
        {kind === 'goods' && (
          <Field label="Lacak per unit" hint="Untuk HP/elektronik: setiap unit dicatat dengan IMEI atau nomor seri">
            <Select value={serialType} onChange={(e) => setSerialType(e.target.value as SerialType | '')}>
              <option value="">Tidak (jumlah saja)</option>
              <option value="imei">IMEI</option>
              <option value="imei_dual">IMEI ganda (dual SIM)</option>
              <option value="serial">Nomor seri</option>
            </Select>
          </Field>
        )}
        <Field label="Garansi (bulan)">
          <Input type="number" min={0} max={120} value={warranty} onChange={(e) => setWarranty(e.target.value)} />
        </Field>
        <Field label="Deskripsi" className="sm:col-span-3">
          <Textarea rows={2} value={description} onChange={(e) => setDescription(e.target.value)} />
        </Field>
      </div>

      <div className="mt-5 mb-2 text-sm font-medium text-stone-700">Varian</div>
      <div className="space-y-2">
        {variants.map((v, i) => (
          <div key={i} className="grid grid-cols-[1fr_1fr_1fr_1fr_auto] gap-2">
            <Input placeholder="Nama varian (mis. 8/256 Navy)" value={v.name} onChange={(e) => setVariant(i, { name: e.target.value })} />
            <Input placeholder="SKU (otomatis)" value={v.sku} onChange={(e) => setVariant(i, { sku: e.target.value })} />
            <Input placeholder="Barcode" value={v.barcode} onChange={(e) => setVariant(i, { barcode: e.target.value })} />
            <Input type="number" min={0} placeholder="Harga jual" value={v.base_price} onChange={(e) => setVariant(i, { base_price: e.target.value })} />
            <Button variant="ghost" aria-label="Hapus varian" disabled={variants.length === 1} onClick={() => setVariants((vs) => vs.filter((_, j) => j !== i))}>
              <Trash2 className="size-4" />
            </Button>
          </div>
        ))}
        <Button size="sm" variant="ghost" icon={<Plus className="size-4" />} onClick={() => setVariants((vs) => [...vs, { name: '', sku: '', barcode: '', base_price: '' }])}>
          Tambah varian
        </Button>
      </div>
      <p className="mt-3 text-xs text-stone-500">Harga jual termasuk PPN. Stok awal diisi lewat halaman Stok atau Penerimaan Barang.</p>
    </Modal>
  );
}
