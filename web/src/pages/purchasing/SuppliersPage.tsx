import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Plus } from 'lucide-react';
import { api, errorMessage } from '../../api/client';
import type { Supplier } from '../../api/types';
import { useAuth } from '../../auth/AuthContext';
import { formatRp, toNumber } from '../../lib/format';
import { Badge, Button, Checkbox, DataTable, Field, Input, Modal, PageHeader, QueryState, Textarea, Toolbar, useToast } from '../../components/ui';

export const useSuppliers = (search = '', includeInactive = false) =>
  useQuery({
    queryKey: ['suppliers', search, includeInactive],
    queryFn: () => api<{ suppliers: Supplier[] }>('/purchasing/suppliers', { query: { search, include_inactive: includeInactive || undefined } }).then((r) => r.suppliers),
  });

export function SuppliersPage() {
  const { access } = useAuth();
  const qc = useQueryClient();
  const [search, setSearch] = useState('');
  const [inactive, setInactive] = useState(false);
  const [editing, setEditing] = useState<Supplier | 'new' | null>(null);
  const suppliers = useSuppliers(search, inactive);
  const canManage = access.can('suppliers.manage');

  return (
    <>
      <PageHeader
        title="Supplier"
        description="Hutang = total penerimaan barang yang sudah diposting dikurangi pembayaran."
        actions={canManage && <Button variant="primary" icon={<Plus className="size-4" />} onClick={() => setEditing('new')}>Supplier baru</Button>}
      />
      <Toolbar>
        <Field label="Cari" className="w-64">
          <Input placeholder="Nama, kode, telepon" value={search} onChange={(e) => setSearch(e.target.value)} />
        </Field>
        <div className="pb-2.5">
          <Checkbox label="Tampilkan nonaktif" checked={inactive} onChange={(e) => setInactive(e.target.checked)} />
        </div>
      </Toolbar>
      <QueryState query={suppliers}>
        <DataTable
          rows={suppliers.data ?? []}
          rowKey={(s) => s.id}
          onRowClick={canManage ? (s) => setEditing(s) : undefined}
          columns={[
            { header: 'Kode', cell: (s) => <span className="font-mono text-xs">{s.code ?? '—'}</span> },
            { header: 'Nama', cell: (s) => <span className="font-medium">{s.name}</span> },
            { header: 'Telepon', cell: (s) => s.phone ?? '—' },
            { header: 'Email', cell: (s) => s.email ?? '—' },
            { header: 'Hutang', align: 'right', cell: (s) => <span className={toNumber(s.outstanding) > 0 ? 'font-medium text-red-600' : ''}>{formatRp(s.outstanding)}</span> },
            { header: '', cell: (s) => !s.is_active && <Badge tone="red">Nonaktif</Badge> },
          ]}
        />
      </QueryState>
      {editing && <SupplierDialog supplier={editing === 'new' ? null : editing} onClose={() => setEditing(null)} onSaved={() => qc.invalidateQueries({ queryKey: ['suppliers'] })} />}
    </>
  );
}

function SupplierDialog({ supplier, onClose, onSaved }: { supplier: Supplier | null; onClose: () => void; onSaved: () => void }) {
  const toast = useToast();
  const [form, setForm] = useState({
    code: supplier?.code ?? '',
    name: supplier?.name ?? '',
    phone: supplier?.phone ?? '',
    email: supplier?.email ?? '',
    address: supplier?.address ?? '',
    notes: supplier?.notes ?? '',
    is_active: supplier?.is_active ?? true,
  });
  const set = (patch: Partial<typeof form>) => setForm((f) => ({ ...f, ...patch }));
  const save = useMutation({
    mutationFn: () => {
      const body = { ...form, code: form.code.trim() || undefined, name: form.name.trim() };
      return supplier ? api(`/purchasing/suppliers/${supplier.id}`, { method: 'PUT', body }) : api('/purchasing/suppliers', { method: 'POST', body });
    },
    onSuccess: () => {
      toast.success('Supplier disimpan');
      onSaved();
      onClose();
    },
    onError: (error) => toast.error(errorMessage(error)),
  });
  return (
    <Modal
      open
      onClose={onClose}
      title={supplier ? `Supplier ${supplier.name}` : 'Supplier baru'}
      footer={
        <>
          <Button onClick={onClose}>Batal</Button>
          <Button variant="primary" loading={save.isPending} disabled={!form.name.trim()} onClick={() => save.mutate()}>Simpan</Button>
        </>
      }
    >
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="Kode" hint="Kosongkan untuk dibuat otomatis"><Input value={form.code} onChange={(e) => set({ code: e.target.value.toUpperCase() })} /></Field>
        <Field label="Nama"><Input value={form.name} onChange={(e) => set({ name: e.target.value })} /></Field>
        <Field label="Telepon"><Input value={form.phone} onChange={(e) => set({ phone: e.target.value })} /></Field>
        <Field label="Email"><Input type="email" value={form.email} onChange={(e) => set({ email: e.target.value })} /></Field>
        <Field label="Alamat" className="sm:col-span-2"><Textarea rows={2} value={form.address} onChange={(e) => set({ address: e.target.value })} /></Field>
        <Field label="Catatan" className="sm:col-span-2"><Textarea rows={2} value={form.notes} onChange={(e) => set({ notes: e.target.value })} /></Field>
        {supplier && <Checkbox label="Aktif" checked={form.is_active} onChange={(e) => set({ is_active: e.target.checked })} />}
      </div>
    </Modal>
  );
}
