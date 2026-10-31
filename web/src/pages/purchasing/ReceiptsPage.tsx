import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useNavigate } from 'react-router';
import { Plus } from 'lucide-react';
import { api } from '../../api/client';
import type { PaymentStatus, ReceiptSummary } from '../../api/types';
import { LocationSelect, useLocationChoice } from '../../lib/locations';
import { formatDate, formatRp } from '../../lib/format';
import { Badge, Button, DataTable, Field, PageHeader, QueryState, Select, Toolbar, type Tone } from '../../components/ui';
import { useSuppliers } from './SuppliersPage';

export const PAYMENT_STATUS: Record<PaymentStatus, [string, Tone]> = {
  unpaid: ['Belum dibayar', 'red'],
  partial: ['Dibayar sebagian', 'amber'],
  paid: ['Lunas', 'green'],
};

export function ReceiptsPage() {
  const navigate = useNavigate();
  const choice = useLocationChoice('purchases.manage', { allowAll: true });
  const suppliers = useSuppliers();
  const [supplierId, setSupplierId] = useState('');
  const [status, setStatus] = useState('');
  const [payment, setPayment] = useState('');

  const receipts = useQuery({
    queryKey: ['receipts', choice.locationId, supplierId, status, payment],
    queryFn: () =>
      api<{ receipts: ReceiptSummary[] }>('/purchasing/receipts', {
        query: { location_id: choice.locationId, supplier_id: supplierId, status, payment_status: payment },
      }).then((r) => r.receipts),
  });

  return (
    <>
      <PageHeader
        title="Penerimaan Barang"
        description="Draf bisa diubah; setelah diposting stok bertambah, HPP rata-rata diperbarui dan jurnal hutang dibuat."
        actions={<Button variant="primary" icon={<Plus className="size-4" />} onClick={() => navigate('/receipts/new')}>Penerimaan baru</Button>}
      />
      <Toolbar>
        <LocationSelect choice={choice} />
        <Field label="Supplier" className="w-48">
          <Select value={supplierId} onChange={(e) => setSupplierId(e.target.value)}>
            <option value="">Semua</option>
            {suppliers.data?.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
          </Select>
        </Field>
        <Field label="Status" className="w-36">
          <Select value={status} onChange={(e) => setStatus(e.target.value)}>
            <option value="">Semua</option>
            <option value="draft">Draf</option>
            <option value="posted">Diposting</option>
          </Select>
        </Field>
        <Field label="Pembayaran" className="w-44">
          <Select value={payment} onChange={(e) => setPayment(e.target.value)}>
            <option value="">Semua</option>
            {Object.entries(PAYMENT_STATUS).map(([k, [label]]) => <option key={k} value={k}>{label}</option>)}
          </Select>
        </Field>
      </Toolbar>
      <QueryState query={receipts}>
        <DataTable
          rows={receipts.data ?? []}
          rowKey={(r) => r.id}
          onRowClick={(r) => navigate(`/receipts/${r.id}`)}
          empty="Belum ada penerimaan barang"
          columns={[
            { header: 'Nomor', cell: (r) => <span className="font-mono text-xs">{r.number}</span> },
            { header: 'Supplier', cell: (r) => r.supplier_name },
            { header: 'Lokasi', cell: (r) => r.location_code },
            { header: 'Faktur', cell: (r) => <div>{r.invoice_no ?? '—'}<div className="text-xs text-stone-500">{formatDate(r.invoice_date)}</div></div> },
            { header: 'Qty', align: 'right', cell: (r) => r.item_qty },
            { header: 'Total', align: 'right', cell: (r) => formatRp(r.grand_total) },
            { header: 'Status', cell: (r) => (r.status === 'draft' ? <Badge>Draf</Badge> : <Badge tone={PAYMENT_STATUS[r.payment_status][1]}>{PAYMENT_STATUS[r.payment_status][0]}</Badge>) },
            { header: 'Jatuh tempo', cell: (r) => formatDate(r.due_date) },
          ]}
        />
      </QueryState>
    </>
  );
}
