import { useRef, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Link, useNavigate, useParams } from 'react-router';
import { ArrowLeft, ImageUp, Pencil, Plus } from 'lucide-react';
import { api, errorMessage, uploadUrl } from '../../api/client';
import type { Product, ProductKind, SerialType, Variant } from '../../api/types';
import { useAuth } from '../../auth/AuthContext';
import { KIND_LABELS, useBrands, useCategories, useTaxRates } from '../../lib/catalog';
import { formatRp } from '../../lib/format';
import { Badge, Button, Card, Checkbox, ConfirmButton, DataTable, Field, Input, Modal, PageHeader, QueryState, Select, Textarea, useToast } from '../../components/ui';

export function ProductDetailPage() {
  const { id } = useParams();
  const { access } = useAuth();
  const navigate = useNavigate();
  const qc = useQueryClient();
  const toast = useToast();
  const fileRef = useRef<HTMLInputElement>(null);
  const [editing, setEditing] = useState(false);
  const [variant, setVariant] = useState<Variant | 'new' | null>(null);
  const canManage = access.can('catalog.manage');

  const product = useQuery({
    queryKey: ['product', id],
    queryFn: () => api<{ product: Product }>(`/catalog/products/${id}`).then((r) => r.product),
  });
  const p = product.data;
  const refresh = () => {
    qc.invalidateQueries({ queryKey: ['product', id] });
    qc.invalidateQueries({ queryKey: ['products'] });
  };

  const upload = useMutation({
    mutationFn: (file: File) => {
      const form = new FormData();
      form.append('image', file);
      return api(`/catalog/products/${id}/image`, { method: 'POST', body: form });
    },
    onSuccess: () => {
      toast.success('Gambar diperbarui');
      refresh();
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  return (
    <QueryState query={product}>
      {p && (
        <>
          <Link to="/catalog" className="mb-3 inline-flex items-center gap-1 text-sm text-stone-500 hover:text-stone-800">
            <ArrowLeft className="size-4" /> Produk
          </Link>
          <PageHeader
            title={p.name}
            description={[p.brand_name, p.category_name, KIND_LABELS[p.kind]].filter(Boolean).join(' · ')}
            actions={
              canManage && (
                <>
                  <Button icon={<Pencil className="size-4" />} onClick={() => setEditing(true)}>
                    Ubah
                  </Button>
                  <ConfirmButton
                    label="Hapus"
                    title="Hapus produk?"
                    message="Produk hilang dari katalog dan kasir, tetapi riwayat penjualan dan stok tetap tersimpan."
                    onConfirm={async () => {
                      await api(`/catalog/products/${p.id}`, { method: 'DELETE' });
                      toast.success('Produk dihapus');
                      qc.invalidateQueries({ queryKey: ['products'] });
                      navigate('/catalog');
                    }}
                  />
                </>
              )
            }
          />

          <div className="grid gap-5 lg:grid-cols-[220px_1fr]">
            <Card>
              <div className="flex aspect-square items-center justify-center overflow-hidden rounded-lg bg-stone-100">
                {p.image ? <img src={uploadUrl('products', p.image)!} alt={p.name} className="h-full w-full object-cover" /> : <span className="text-sm text-stone-400">Tanpa gambar</span>}
              </div>
              {canManage && (
                <>
                  <input
                    ref={fileRef}
                    type="file"
                    accept="image/jpeg,image/png,image/webp"
                    className="hidden"
                    onChange={(e) => {
                      const file = e.target.files?.[0];
                      if (file) upload.mutate(file);
                      e.target.value = '';
                    }}
                  />
                  <Button size="sm" className="mt-3 w-full" icon={<ImageUp className="size-4" />} loading={upload.isPending} onClick={() => fileRef.current?.click()}>
                    Ganti gambar
                  </Button>
                </>
              )}
              <dl className="mt-4 space-y-1.5 text-sm">
                <div className="flex justify-between"><dt className="text-stone-500">Status</dt><dd>{p.is_active ? <Badge tone="green">Aktif</Badge> : <Badge tone="red">Nonaktif</Badge>}</dd></div>
                <div className="flex justify-between"><dt className="text-stone-500">Per unit</dt><dd>{p.is_serialized ? (p.serial_type === 'serial' ? 'Nomor seri' : p.serial_type === 'imei_dual' ? 'IMEI ganda' : 'IMEI') : 'Tidak'}</dd></div>
                <div className="flex justify-between"><dt className="text-stone-500">Garansi</dt><dd>{p.warranty_months ? `${p.warranty_months} bulan` : '—'}</dd></div>
              </dl>
              {p.description && <p className="mt-3 text-sm text-stone-600">{p.description}</p>}
            </Card>

            <div className="space-y-5">
              <Card
                title="Varian"
                actions={canManage && <Button size="sm" icon={<Plus className="size-4" />} onClick={() => setVariant('new')}>Varian</Button>}
              >
                <DataTable
                  rows={p.variants}
                  rowKey={(v) => v.id}
                  onRowClick={canManage ? (v) => setVariant(v) : undefined}
                  columns={[
                    { header: 'Varian', cell: (v) => <span className="font-medium">{v.name || '(utama)'}</span> },
                    { header: 'SKU', cell: (v) => <span className="font-mono text-xs">{v.sku}</span> },
                    { header: 'Barcode', cell: (v) => v.barcode ?? '—' },
                    { header: 'Harga dasar', align: 'right', cell: (v) => formatRp(v.base_price) },
                    { header: 'Harga min.', align: 'right', cell: (v) => (v.min_price == null ? '—' : formatRp(v.min_price)) },
                    { header: '', cell: (v) => !v.is_active && <Badge tone="red">Nonaktif</Badge> },
                  ]}
                />
              </Card>

              <Card title="Stok per lokasi">
                <DataTable
                  rows={p.stock ?? []}
                  rowKey={(s) => `${s.location_id}-${s.variant_id}`}
                  empty="Belum ada stok di lokasi yang bisa Anda lihat"
                  columns={[
                    { header: 'Lokasi', cell: (s) => `${s.location_name} (${s.location_code})` },
                    { header: 'Varian', cell: (s) => p.variants.find((v) => v.id === s.variant_id)?.name || '(utama)' },
                    { header: 'Stok', align: 'right', cell: (s) => s.on_hand },
                    { header: 'Harga jual', align: 'right', cell: (s) => <>{formatRp(s.sell_price)}{s.location_price != null && <span className="ml-1 text-xs text-brand-700">lokasi</span>}</> },
                    { header: 'HPP rata-rata', align: 'right', cell: (s) => (s.avg_cost === undefined ? '—' : formatRp(s.avg_cost)) },
                  ]}
                />
              </Card>
            </div>
          </div>

          {editing && <EditProductDialog product={p} onClose={() => setEditing(false)} onSaved={refresh} />}
          {variant && <VariantDialog productId={p.id} variant={variant === 'new' ? null : variant} onClose={() => setVariant(null)} onSaved={refresh} />}
        </>
      )}
    </QueryState>
  );
}

function EditProductDialog({ product, onClose, onSaved }: { product: Product; onClose: () => void; onSaved: () => void }) {
  const toast = useToast();
  const categories = useCategories();
  const brands = useBrands();
  const taxRates = useTaxRates();
  const [name, setName] = useState(product.name);
  const [description, setDescription] = useState(product.description ?? '');
  const [categoryId, setCategoryId] = useState(String(product.category_id ?? ''));
  const [brandId, setBrandId] = useState(String(product.brand_id ?? ''));
  const [kind, setKind] = useState<ProductKind>(product.kind);
  const [serialType, setSerialType] = useState<SerialType | ''>(product.is_serialized ? (product.serial_type ?? 'imei') : '');
  const [warranty, setWarranty] = useState(String(product.warranty_months ?? 0));
  const [taxRateId, setTaxRateId] = useState(String(product.tax_rate_id ?? ''));
  const [active, setActive] = useState(product.is_active);

  const save = useMutation({
    mutationFn: () =>
      api(`/catalog/products/${product.id}`, {
        method: 'PUT',
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
          is_active: active,
        },
      }),
    onSuccess: () => {
      toast.success('Produk diperbarui');
      onSaved();
      onClose();
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  return (
    <Modal
      open
      onClose={onClose}
      title="Ubah produk"
      footer={
        <>
          <Button onClick={onClose}>Batal</Button>
          <Button variant="primary" loading={save.isPending} disabled={!name.trim()} onClick={() => save.mutate()}>
            Simpan
          </Button>
        </>
      }
    >
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="Nama" className="sm:col-span-2">
          <Input value={name} onChange={(e) => setName(e.target.value)} />
        </Field>
        <Field label="Jenis">
          <Select value={kind} onChange={(e) => { setKind(e.target.value as ProductKind); if (e.target.value !== 'goods') setSerialType(''); }}>
            {Object.entries(KIND_LABELS).map(([k, label]) => <option key={k} value={k}>{label}</option>)}
          </Select>
        </Field>
        <Field label="Lacak per unit" hint="Tidak bisa diubah setelah ada stok">
          <Select value={serialType} onChange={(e) => setSerialType(e.target.value as SerialType | '')} disabled={kind !== 'goods'}>
            <option value="">Tidak</option>
            <option value="imei">IMEI</option>
            <option value="imei_dual">IMEI ganda</option>
            <option value="serial">Nomor seri</option>
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
            {taxRates.data?.map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}
          </Select>
        </Field>
        <Field label="Garansi (bulan)">
          <Input type="number" min={0} max={120} value={warranty} onChange={(e) => setWarranty(e.target.value)} />
        </Field>
        <Field label="Deskripsi" className="sm:col-span-2">
          <Textarea rows={3} value={description} onChange={(e) => setDescription(e.target.value)} />
        </Field>
        <Checkbox label="Aktif (tampil di kasir)" checked={active} onChange={(e) => setActive(e.target.checked)} />
      </div>
    </Modal>
  );
}

function VariantDialog({ productId, variant, onClose, onSaved }: { productId: number; variant: Variant | null; onClose: () => void; onSaved: () => void }) {
  const toast = useToast();
  const [name, setName] = useState(variant?.name ?? '');
  const [sku, setSku] = useState(variant?.sku ?? '');
  const [barcode, setBarcode] = useState(variant?.barcode ?? '');
  const [basePrice, setBasePrice] = useState(variant ? String(Number(variant.base_price)) : '');
  const [minPrice, setMinPrice] = useState(variant?.min_price != null ? String(Number(variant.min_price)) : '');
  const [active, setActive] = useState(variant?.is_active ?? true);

  const save = useMutation({
    mutationFn: () => {
      const body = {
        name: name.trim() || null,
        sku: sku.trim() || undefined,
        barcode: barcode.trim() || null,
        base_price: Number(basePrice),
        min_price: minPrice === '' ? null : Number(minPrice),
        is_active: active,
      };
      return variant
        ? api(`/catalog/variants/${variant.id}`, { method: 'PUT', body })
        : api(`/catalog/products/${productId}/variants`, { method: 'POST', body });
    },
    onSuccess: () => {
      toast.success(variant ? 'Varian diperbarui' : 'Varian ditambahkan');
      onSaved();
      onClose();
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  return (
    <Modal
      open
      onClose={onClose}
      title={variant ? 'Ubah varian' : 'Varian baru'}
      footer={
        <>
          {variant && (
            <ConfirmButton
              label="Hapus"
              title="Hapus varian?"
              message="Varian hilang dari katalog; riwayat penjualan dan stok tetap tersimpan."
              onConfirm={async () => {
                await api(`/catalog/variants/${variant.id}`, { method: 'DELETE' });
                toast.success('Varian dihapus');
                onSaved();
                onClose();
              }}
            />
          )}
          <div className="flex-1" />
          <Button onClick={onClose}>Batal</Button>
          <Button variant="primary" loading={save.isPending} disabled={basePrice === ''} onClick={() => save.mutate()}>
            Simpan
          </Button>
        </>
      }
    >
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="Nama varian" hint="Kosongkan untuk varian utama">
          <Input value={name} onChange={(e) => setName(e.target.value)} />
        </Field>
        <Field label="SKU" hint="Kosongkan untuk dibuat otomatis">
          <Input value={sku} onChange={(e) => setSku(e.target.value)} />
        </Field>
        <Field label="Barcode">
          <Input value={barcode} onChange={(e) => setBarcode(e.target.value)} />
        </Field>
        <div />
        <Field label="Harga jual dasar (termasuk PPN)">
          <Input type="number" min={0} value={basePrice} onChange={(e) => setBasePrice(e.target.value)} />
        </Field>
        <Field label="Harga minimum" hint="Kasir tidak bisa menjual di bawah ini tanpa izin">
          <Input type="number" min={0} value={minPrice} onChange={(e) => setMinPrice(e.target.value)} />
        </Field>
        <Checkbox label="Aktif" checked={active} onChange={(e) => setActive(e.target.checked)} />
      </div>
    </Modal>
  );
}
