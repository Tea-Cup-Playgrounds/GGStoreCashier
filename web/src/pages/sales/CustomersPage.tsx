import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Link } from 'react-router';
import { Plus } from 'lucide-react';
import { api, errorMessage } from '../../api/client';
import type { Customer, SaleStatus, UnitStatus } from '../../api/types';
import { useAuth } from '../../auth/AuthContext';
import { unitLabel, unitStatusBadge } from '../../lib/catalog';
import { formatDate, formatDateTime, formatRp } from '../../lib/format';
import { Badge, Button, Card, DataTable, Field, Input, Modal, PageHeader, QueryState, Spinner, Textarea, Toolbar, useToast } from '../../components/ui';
import { SALE_STATUS } from './SalesPage';

interface CustomerDetail {
  customer: Customer;
  sales: Array<{ id: string; number: string; occurred_at: string; grand_total: string; refunded_total: string; status: SaleStatus; location_code: string }>;
  units: Array<{ unit_id: string; imei1: string | null; imei2: string | null; serial_number: string | null; status: UnitStatus; description: string; warranty_until: string | null; sale_number: string; occurred_at: string }>;
}

export function CustomersPage() {
  const { access } = useAuth();
  const qc = useQueryClient();
  const [search, setSearch] = useState('');
  const [selected, setSelected] = useState<string | null>(null);
  const [editing, setEditing] = useState<Customer | 'new' | null>(null);
  const customers = useQuery({
    queryKey: ['customers', search],
    queryFn: () => api<{ customers: Customer[] }>('/customers', { query: { search } }).then((r) => r.customers),
  });

  return (
    <>
      <PageHeader
        title="Pelanggan"
        description="Dicari lewat nama, kode, atau nomor HP (08… atau +62…). Menampilkan 50 terbaru."
        actions={<Button variant="primary" icon={<Plus className="size-4" />} onClick={() => setEditing('new')}>Pelanggan baru</Button>}
      />
      <Toolbar>
        <Field label="Cari" className="w-72"><Input placeholder="Nama, kode, atau nomor HP" value={search} onChange={(e) => setSearch(e.target.value)} /></Field>
      </Toolbar>
      <QueryState query={customers}>
        <DataTable
          rows={customers.data ?? []}
          rowKey={(c) => c.id}
          onRowClick={(c) => setSelected(c.id)}
          empty="Tidak ada pelanggan"
          columns={[
            { header: 'Nama', cell: (c) => <span className="font-medium">{c.name}</span> },
            { header: 'HP', cell: (c) => c.phone ?? '—' },
            { header: 'Email', cell: (c) => c.email ?? '—' },
            { header: 'Kode', cell: (c) => c.code ?? '—' },
            { header: 'Terdaftar', cell: (c) => formatDate(c.created_at) },
          ]}
        />
      </QueryState>
      {selected && (
        <CustomerDetailDialog
          id={selected}
          canEdit={access.can('customers.manage')}
          onEdit={(c) => { setSelected(null); setEditing(c); }}
          onClose={() => setSelected(null)}
        />
      )}
      {editing && <CustomerDialog customer={editing === 'new' ? null : editing} onClose={() => setEditing(null)} onSaved={() => qc.invalidateQueries({ queryKey: ['customers'] })} />}
    </>
  );
}

function CustomerDetailDialog({ id, canEdit, onEdit, onClose }: { id: string; canEdit: boolean; onEdit: (c: Customer) => void; onClose: () => void }) {
  const detail = useQuery({ queryKey: ['customer', id], queryFn: () => api<CustomerDetail>(`/customers/${id}`) });
  const d = detail.data;
  return (
    <Modal
      open
      wide
      onClose={onClose}
      title={d?.customer.name ?? 'Pelanggan'}
      footer={<>{canEdit && d && <Button onClick={() => onEdit(d.customer)}>Ubah</Button>}<Button onClick={onClose}>Tutup</Button></>}
    >
      {!d ? (
        <div className="flex justify-center py-6"><Spinner /></div>
      ) : (
        <div className="space-y-5">
          <dl className="grid gap-2 text-sm sm:grid-cols-3">
            <div><dt className="text-stone-500">HP</dt><dd>{d.customer.phone ?? '—'}</dd></div>
            <div><dt className="text-stone-500">Email</dt><dd>{d.customer.email ?? '—'}</dd></div>
            <div><dt className="text-stone-500">No. identitas</dt><dd>{d.customer.id_number ?? '—'}</dd></div>
            <div className="sm:col-span-3"><dt className="text-stone-500">Alamat</dt><dd>{d.customer.address ?? '—'}</dd></div>
          </dl>
          <Card title="Unit IMEI yang dibeli (garansi)">
            <DataTable
              rows={d.units}
              rowKey={(u) => u.unit_id}
              empty="Belum ada"
              columns={[
                { header: 'Barang', cell: (u) => <div>{u.description}<div className="font-mono text-xs text-stone-500">{unitLabel(u)}</div></div> },
                { header: 'Nota', cell: (u) => <span className="font-mono text-xs">{u.sale_number}</span> },
                { header: 'Garansi s/d', cell: (u) => formatDate(u.warranty_until) },
                { header: 'Status', cell: (u) => unitStatusBadge(u.status) },
              ]}
            />
          </Card>
          <Card title="Riwayat belanja">
            <DataTable
              rows={d.sales}
              rowKey={(s) => s.id}
              empty="Belum ada"
              columns={[
                { header: 'Nomor', cell: (s) => <Link to={`/sales/${s.id}`} className="font-mono text-xs text-brand-700 underline">{s.number}</Link> },
                { header: 'Waktu', cell: (s) => formatDateTime(s.occurred_at) },
                { header: 'Lokasi', cell: (s) => s.location_code },
                { header: 'Total', align: 'right', cell: (s) => formatRp(s.grand_total) },
                { header: '', cell: (s) => <Badge tone={SALE_STATUS[s.status][1]}>{SALE_STATUS[s.status][0]}</Badge> },
              ]}
            />
          </Card>
        </div>
      )}
    </Modal>
  );
}

function CustomerDialog({ customer, onClose, onSaved }: { customer: Customer | null; onClose: () => void; onSaved: () => void }) {
  const toast = useToast();
  const [form, setForm] = useState({
    name: customer?.name ?? '',
    phone: customer?.phone ?? '',
    email: customer?.email ?? '',
    address: customer?.address ?? '',
    id_number: customer?.id_number ?? '',
    notes: customer?.notes ?? '',
  });
  const set = (patch: Partial<typeof form>) => setForm((f) => ({ ...f, ...patch }));
  const save = useMutation({
    mutationFn: () => {
      const body = Object.fromEntries(Object.entries(form).map(([k, v]) => [k, v.trim() || null]));
      return customer ? api(`/customers/${customer.id}`, { method: 'PUT', body }) : api('/customers', { method: 'POST', body });
    },
    onSuccess: () => {
      toast.success('Pelanggan disimpan');
      onSaved();
      onClose();
    },
    onError: (error) => toast.error(errorMessage(error)),
  });
  return (
    <Modal
      open
      onClose={onClose}
      title={customer ? 'Ubah pelanggan' : 'Pelanggan baru'}
      footer={
        <>
          <Button onClick={onClose}>Batal</Button>
          <Button variant="primary" loading={save.isPending} disabled={!form.name.trim()} onClick={() => save.mutate()}>Simpan</Button>
        </>
      }
    >
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="Nama"><Input value={form.name} onChange={(e) => set({ name: e.target.value })} /></Field>
        <Field label="Nomor HP" hint="Satu nomor hanya untuk satu pelanggan"><Input value={form.phone} onChange={(e) => set({ phone: e.target.value })} /></Field>
        <Field label="Email"><Input type="email" value={form.email} onChange={(e) => set({ email: e.target.value })} /></Field>
        <Field label="No. identitas (KTP)"><Input value={form.id_number} onChange={(e) => set({ id_number: e.target.value })} /></Field>
        <Field label="Alamat" className="sm:col-span-2"><Textarea rows={2} value={form.address} onChange={(e) => set({ address: e.target.value })} /></Field>
        <Field label="Catatan" className="sm:col-span-2"><Textarea rows={2} value={form.notes} onChange={(e) => set({ notes: e.target.value })} /></Field>
      </div>
    </Modal>
  );
}
