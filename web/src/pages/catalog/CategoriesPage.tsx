import { useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { Plus } from 'lucide-react';
import { api, errorMessage } from '../../api/client';
import type { Brand, Category, TaxRate } from '../../api/types';
import { useAuth } from '../../auth/AuthContext';
import { useBrands, useCategories, useTaxRates } from '../../lib/catalog';
import { Badge, Button, Card, Checkbox, ConfirmButton, DataTable, Field, Input, Modal, PageHeader, QueryState, Textarea, useToast } from '../../components/ui';

export function CategoriesPage() {
  const { access } = useAuth();
  const qc = useQueryClient();
  const categories = useCategories();
  const brands = useBrands();
  const [category, setCategory] = useState<Category | 'new' | null>(null);
  const [brand, setBrand] = useState<Brand | 'new' | null>(null);
  const canManage = access.can('catalog.manage');

  return (
    <>
      <PageHeader title="Kategori & Merek" description="Pengelompokan produk di katalog." />
      <div className="grid gap-5 lg:grid-cols-2">
        <Card title="Kategori" actions={canManage && <Button size="sm" icon={<Plus className="size-4" />} onClick={() => setCategory('new')}>Kategori</Button>}>
          <QueryState query={categories}>
            <DataTable
              rows={categories.data ?? []}
              rowKey={(c) => c.id}
              onRowClick={canManage ? (c) => setCategory(c) : undefined}
              columns={[
                { header: 'Nama', cell: (c) => <span className="font-medium">{c.name}</span> },
                { header: 'Deskripsi', cell: (c) => c.description ?? '—' },
              ]}
            />
          </QueryState>
        </Card>
        <Card title="Merek" actions={canManage && <Button size="sm" icon={<Plus className="size-4" />} onClick={() => setBrand('new')}>Merek</Button>}>
          <QueryState query={brands}>
            <DataTable
              rows={brands.data ?? []}
              rowKey={(b) => b.id}
              onRowClick={canManage ? (b) => setBrand(b) : undefined}
              columns={[{ header: 'Nama', cell: (b) => <span className="font-medium">{b.name}</span> }]}
            />
          </QueryState>
        </Card>
      </div>
      {category && <CategoryDialog category={category === 'new' ? null : category} onClose={() => setCategory(null)} onSaved={() => qc.invalidateQueries({ queryKey: ['categories'] })} />}
      {brand && <BrandDialog brand={brand === 'new' ? null : brand} onClose={() => setBrand(null)} onSaved={() => qc.invalidateQueries({ queryKey: ['brands'] })} />}
    </>
  );
}

function CategoryDialog({ category, onClose, onSaved }: { category: Category | null; onClose: () => void; onSaved: () => void }) {
  const toast = useToast();
  const [name, setName] = useState(category?.name ?? '');
  const [description, setDescription] = useState(category?.description ?? '');
  const save = useMutation({
    mutationFn: () => {
      const body = { name: name.trim(), description: description.trim() };
      return category ? api(`/categories/${category.id}`, { method: 'PUT', body }) : api('/categories', { method: 'POST', body });
    },
    onSuccess: () => {
      toast.success('Kategori disimpan');
      onSaved();
      onClose();
    },
    onError: (error) => toast.error(errorMessage(error)),
  });
  return (
    <Modal
      open
      onClose={onClose}
      title={category ? 'Ubah kategori' : 'Kategori baru'}
      footer={
        <>
          {category && (
            <ConfirmButton
              label="Hapus"
              title="Hapus kategori?"
              message="Kategori yang masih dipakai produk tidak bisa dihapus."
              onConfirm={async () => {
                await api(`/categories/${category.id}`, { method: 'DELETE' });
                toast.success('Kategori dihapus');
                onSaved();
                onClose();
              }}
            />
          )}
          <div className="flex-1" />
          <Button onClick={onClose}>Batal</Button>
          <Button variant="primary" loading={save.isPending} disabled={!name.trim()} onClick={() => save.mutate()}>
            Simpan
          </Button>
        </>
      }
    >
      <div className="space-y-4">
        <Field label="Nama">
          <Input value={name} onChange={(e) => setName(e.target.value)} />
        </Field>
        <Field label="Deskripsi">
          <Textarea rows={2} value={description} onChange={(e) => setDescription(e.target.value)} />
        </Field>
      </div>
    </Modal>
  );
}

function BrandDialog({ brand, onClose, onSaved }: { brand: Brand | null; onClose: () => void; onSaved: () => void }) {
  const toast = useToast();
  const [name, setName] = useState(brand?.name ?? '');
  const save = useMutation({
    mutationFn: () => (brand ? api(`/catalog/brands/${brand.id}`, { method: 'PUT', body: { name: name.trim() } }) : api('/catalog/brands', { method: 'POST', body: { name: name.trim() } })),
    onSuccess: () => {
      toast.success('Merek disimpan');
      onSaved();
      onClose();
    },
    onError: (error) => toast.error(errorMessage(error)),
  });
  return (
    <Modal
      open
      onClose={onClose}
      title={brand ? 'Ubah merek' : 'Merek baru'}
      footer={
        <>
          <Button onClick={onClose}>Batal</Button>
          <Button variant="primary" loading={save.isPending} disabled={!name.trim()} onClick={() => save.mutate()}>
            Simpan
          </Button>
        </>
      }
    >
      <Field label="Nama merek">
        <Input value={name} onChange={(e) => setName(e.target.value)} />
      </Field>
    </Modal>
  );
}

export function TaxRatesPage() {
  const qc = useQueryClient();
  const taxRates = useTaxRates();
  const [editing, setEditing] = useState<TaxRate | 'new' | null>(null);
  return (
    <>
      <PageHeader
        title="Tarif Pajak"
        description="Harga jual sudah termasuk PPN; tarif ini dipakai untuk memisahkan pajak dari harga."
        actions={<Button variant="primary" icon={<Plus className="size-4" />} onClick={() => setEditing('new')}>Tarif baru</Button>}
      />
      <QueryState query={taxRates}>
        <DataTable
          rows={taxRates.data ?? []}
          rowKey={(t) => t.id}
          onRowClick={(t) => setEditing(t)}
          columns={[
            { header: 'Nama', cell: (t) => <span className="font-medium">{t.name}</span> },
            { header: 'Tarif', align: 'right', cell: (t) => `${Number(t.rate)}%` },
            { header: 'Status', cell: (t) => (t.is_active ? <Badge tone="green">Aktif</Badge> : <Badge tone="red">Nonaktif</Badge>) },
          ]}
        />
      </QueryState>
      {editing && <TaxRateDialog rate={editing === 'new' ? null : editing} onClose={() => setEditing(null)} onSaved={() => qc.invalidateQueries({ queryKey: ['tax-rates'] })} />}
    </>
  );
}

function TaxRateDialog({ rate, onClose, onSaved }: { rate: TaxRate | null; onClose: () => void; onSaved: () => void }) {
  const toast = useToast();
  const [name, setName] = useState(rate?.name ?? '');
  const [value, setValue] = useState(rate ? String(Number(rate.rate)) : '');
  const [active, setActive] = useState(rate?.is_active ?? true);
  const save = useMutation({
    mutationFn: () => {
      const body = { name: name.trim(), rate: Number(value), is_active: active };
      return rate ? api(`/catalog/tax-rates/${rate.id}`, { method: 'PUT', body }) : api('/catalog/tax-rates', { method: 'POST', body });
    },
    onSuccess: () => {
      toast.success('Tarif pajak disimpan');
      onSaved();
      onClose();
    },
    onError: (error) => toast.error(errorMessage(error)),
  });
  return (
    <Modal
      open
      onClose={onClose}
      title={rate ? 'Ubah tarif pajak' : 'Tarif pajak baru'}
      footer={
        <>
          <Button onClick={onClose}>Batal</Button>
          <Button variant="primary" loading={save.isPending} disabled={!name.trim() || value === ''} onClick={() => save.mutate()}>
            Simpan
          </Button>
        </>
      }
    >
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="Nama">
          <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="mis. PPN 11%" />
        </Field>
        <Field label="Tarif (%)">
          <Input type="number" min={0} max={100} step="0.01" value={value} onChange={(e) => setValue(e.target.value)} />
        </Field>
        {rate && <Checkbox label="Aktif" checked={active} onChange={(e) => setActive(e.target.checked)} />}
      </div>
    </Modal>
  );
}
