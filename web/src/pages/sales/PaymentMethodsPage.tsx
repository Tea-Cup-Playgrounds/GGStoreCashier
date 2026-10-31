import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Plus } from 'lucide-react';
import { api, errorMessage } from '../../api/client';
import type { PaymentMethod } from '../../api/types';
import { useLocations } from '../../lib/locations';
import { Badge, Button, Checkbox, DataTable, Field, Input, Modal, PageHeader, QueryState, Select, useToast } from '../../components/ui';

const TYPES: Record<PaymentMethod['type'], string> = { cash: 'Tunai', qris: 'QRIS', ewallet: 'E-Wallet', card: 'Kartu (EDC)', transfer: 'Transfer bank' };

export function PaymentMethodsPage() {
  const qc = useQueryClient();
  const locations = useLocations();
  const methods = useQuery({
    queryKey: ['payment-methods', 'all'],
    queryFn: () => api<{ paymentMethods: PaymentMethod[] }>('/sales/payment-methods', { query: { all: true } }).then((r) => r.paymentMethods),
  });
  const [editing, setEditing] = useState<PaymentMethod | 'new' | null>(null);

  return (
    <>
      <PageHeader
        title="Metode Pembayaran"
        description="Setiap metode dijurnal ke akun aset tertentu (mis. Kas, Bank, Piutang QRIS)."
        actions={<Button variant="primary" icon={<Plus className="size-4" />} onClick={() => setEditing('new')}>Metode baru</Button>}
      />
      <QueryState query={methods}>
        <DataTable
          rows={methods.data ?? []}
          rowKey={(m) => m.id}
          onRowClick={(m) => setEditing(m)}
          columns={[
            { header: 'Nama', cell: (m) => <span className="font-medium">{m.name}</span> },
            { header: 'Tipe', cell: (m) => TYPES[m.type] },
            { header: 'Akun', cell: (m) => <span className="font-mono text-xs">{m.account_code}</span> },
            { header: 'Lokasi', cell: (m) => (m.location_id ? locations.data?.find((l) => l.id === m.location_id)?.name ?? m.location_id : 'Semua') },
            { header: 'Referensi', cell: (m) => (m.requires_reference ? <Badge tone="blue">Wajib</Badge> : '—') },
            { header: 'Urutan', align: 'right', cell: (m) => m.sort_order },
            { header: '', cell: (m) => !m.is_active && <Badge tone="red">Nonaktif</Badge> },
          ]}
        />
      </QueryState>
      {editing && <MethodDialog method={editing === 'new' ? null : editing} onClose={() => setEditing(null)} onSaved={() => qc.invalidateQueries({ queryKey: ['payment-methods'] })} />}
    </>
  );
}

function MethodDialog({ method, onClose, onSaved }: { method: PaymentMethod | null; onClose: () => void; onSaved: () => void }) {
  const toast = useToast();
  const locations = useLocations();
  const [name, setName] = useState(method?.name ?? '');
  const [type, setType] = useState<PaymentMethod['type']>(method?.type ?? 'qris');
  const [accountCode, setAccountCode] = useState(method?.account_code ?? '');
  const [requiresReference, setRequiresReference] = useState(method?.requires_reference ?? false);
  const [locationId, setLocationId] = useState(String(method?.location_id ?? ''));
  const [sortOrder, setSortOrder] = useState(String(method?.sort_order ?? 0));
  const [active, setActive] = useState(method?.is_active ?? true);

  const save = useMutation({
    mutationFn: () => {
      const body = { name: name.trim(), type, account_code: accountCode.trim(), requires_reference: requiresReference, location_id: locationId ? Number(locationId) : null, sort_order: Number(sortOrder) || 0, is_active: active };
      return method ? api(`/sales/payment-methods/${method.id}`, { method: 'PUT', body }) : api('/sales/payment-methods', { method: 'POST', body });
    },
    onSuccess: () => {
      toast.success('Metode pembayaran disimpan');
      onSaved();
      onClose();
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  return (
    <Modal
      open
      onClose={onClose}
      title={method ? `Metode ${method.name}` : 'Metode pembayaran baru'}
      footer={
        <>
          <Button onClick={onClose}>Batal</Button>
          <Button variant="primary" loading={save.isPending} disabled={!name.trim() || !accountCode.trim()} onClick={() => save.mutate()}>Simpan</Button>
        </>
      }
    >
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="Nama"><Input value={name} onChange={(e) => setName(e.target.value)} placeholder="mis. QRIS BCA" /></Field>
        <Field label="Tipe">
          <Select value={type} onChange={(e) => setType(e.target.value as PaymentMethod['type'])}>
            {Object.entries(TYPES).map(([k, label]) => <option key={k} value={k}>{label}</option>)}
          </Select>
        </Field>
        <Field label="Kode akun" hint="Akun aset, mis. 1-1100 Kas, 1-1200 Bank, 1-1300 Piutang QRIS"><Input value={accountCode} onChange={(e) => setAccountCode(e.target.value)} className="font-mono" /></Field>
        <Field label="Hanya di lokasi">
          <Select value={locationId} onChange={(e) => setLocationId(e.target.value)}>
            <option value="">Semua lokasi</option>
            {locations.data?.map((l) => <option key={l.id} value={l.id}>{l.name}</option>)}
          </Select>
        </Field>
        <Field label="Urutan tampil"><Input type="number" value={sortOrder} onChange={(e) => setSortOrder(e.target.value)} /></Field>
        <div className="space-y-2 pt-6">
          <Checkbox label="Wajib isi nomor referensi" checked={requiresReference} onChange={(e) => setRequiresReference(e.target.checked)} />
          <Checkbox label="Aktif" checked={active} onChange={(e) => setActive(e.target.checked)} />
        </div>
      </div>
    </Modal>
  );
}
