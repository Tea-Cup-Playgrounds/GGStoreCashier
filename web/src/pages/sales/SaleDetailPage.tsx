import { useState, type ReactNode } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Link, useParams } from 'react-router';
import { ArrowLeft } from 'lucide-react';
import { api, errorMessage } from '../../api/client';
import type { PaymentMethod, Sale } from '../../api/types';
import { useAuth } from '../../auth/AuthContext';
import { unitLabel } from '../../lib/catalog';
import { formatDate, formatDateTime, formatRp, toNumber } from '../../lib/format';
import { Badge, Button, Card, Checkbox, DataTable, Field, Input, Modal, PageHeader, QueryState, Select, Textarea, useToast } from '../../components/ui';
import { SALE_STATUS } from './SalesPage';

export const usePaymentMethods = (locationId: number | null | undefined) =>
  useQuery({
    queryKey: ['payment-methods', locationId ?? null],
    queryFn: () => api<{ paymentMethods: PaymentMethod[] }>('/sales/payment-methods', { query: { location_id: locationId ?? undefined } }).then((r) => r.paymentMethods),
    staleTime: 60_000,
  });

export function SaleDetailPage() {
  const { id } = useParams();
  const { access } = useAuth();
  const [voiding, setVoiding] = useState(false);
  const [returning, setReturning] = useState(false);
  const sale = useQuery({ queryKey: ['sale', id], queryFn: () => api<{ sale: Sale }>(`/sales/${id}`).then((r) => r.sale) });
  const s = sale.data;
  const canVoid = s && access.can('sales.void', s.location_id);
  const returnable = s?.lines.some((l) => l.qty - l.returned_qty > 0);

  return (
    <QueryState query={sale}>
      {s && (
        <>
          <Link to="/sales" className="mb-3 inline-flex items-center gap-1 text-sm text-stone-500 hover:text-stone-800">
            <ArrowLeft className="size-4" /> Penjualan
          </Link>
          <PageHeader
            title={s.number}
            description={`${s.location_name} · ${formatDateTime(s.occurred_at)} · kasir ${s.cashier_name ?? '—'}`}
            actions={
              <>
                <Badge tone={SALE_STATUS[s.status][1]}>{SALE_STATUS[s.status][0]}</Badge>
                {canVoid && s.status !== 'voided' && returnable && <Button onClick={() => setReturning(true)}>Retur</Button>}
                {canVoid && s.status === 'completed' && <Button variant="danger" onClick={() => setVoiding(true)}>Batalkan</Button>}
              </>
            }
          />
          {s.status === 'voided' && s.void_reason && <p className="mb-4 rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700">Dibatalkan: {s.void_reason}</p>}
          <div className="grid gap-5 lg:grid-cols-[1fr_320px]">
            <Card title="Barang">
              <DataTable
                rows={s.lines}
                rowKey={(l) => l.id}
                columns={[
                  {
                    header: 'Barang',
                    cell: (l) => (
                      <div>
                        <div className="font-medium">{l.description}</div>
                        {(l.imei1 || l.serial_number) && <div className="font-mono text-xs text-stone-500">{unitLabel(l)}</div>}
                        {l.warranty_until && <div className="text-xs text-stone-500">Garansi s/d {formatDate(l.warranty_until)}</div>}
                      </div>
                    ),
                  },
                  { header: 'Qty', align: 'right', cell: (l) => <>{l.qty}{l.returned_qty > 0 && <div className="text-xs text-red-600">retur {l.returned_qty}</div>}</> },
                  { header: 'Harga', align: 'right', cell: (l) => formatRp(l.unit_price) },
                  { header: 'Diskon', align: 'right', cell: (l) => (toNumber(l.discount) ? formatRp(l.discount) : '—') },
                  { header: 'Total', align: 'right', cell: (l) => formatRp(l.line_total) },
                ]}
              />
            </Card>
            <div className="space-y-5">
              <Card title="Ringkasan">
                <dl className="space-y-1.5 text-sm">
                  <Row label="Subtotal" value={formatRp(s.subtotal)} />
                  {toNumber(s.discount_total) > 0 && <Row label={`Diskon${s.voucher_code ? ` (${s.voucher_code})` : ''}`} value={`−${formatRp(s.discount_total)}`} />}
                  <Row label="Total (termasuk PPN)" value={<b>{formatRp(s.grand_total)}</b>} />
                  <Row label="PPN di dalamnya" value={formatRp(s.tax_total)} />
                  <Row label="Dibayar" value={formatRp(s.paid_total)} />
                  {toNumber(s.change_total) > 0 && <Row label="Kembalian" value={formatRp(s.change_total)} />}
                  {toNumber(s.refunded_total) > 0 && <Row label="Dikembalikan" value={<span className="text-red-600">{formatRp(s.refunded_total)}</span>} />}
                </dl>
              </Card>
              <Card title="Pembayaran">
                <dl className="space-y-1.5 text-sm">
                  {s.payments.map((p) => <Row key={p.id} label={`${p.method_name}${p.reference ? ` · ${p.reference}` : ''}`} value={formatRp(p.amount)} />)}
                </dl>
              </Card>
              <Card title="Pelanggan">
                <p className="text-sm">{s.customer_name ? <>{s.customer_name}<br /><span className="text-stone-500">{s.customer_phone}</span></> : <span className="text-stone-500">Umum</span>}</p>
              </Card>
            </div>
          </div>
          {s.returns.length > 0 && (
            <Card title="Retur" className="mt-5">
              <DataTable
                rows={s.returns}
                rowKey={(r) => r.id}
                columns={[
                  { header: 'Nomor', cell: (r) => <span className="font-mono text-xs">{r.number}</span> },
                  { header: 'Waktu', cell: (r) => formatDateTime(r.created_at) },
                  { header: 'Alasan', cell: (r) => r.reason },
                  { header: 'Dikembalikan via', cell: (r) => r.refund_method },
                  { header: 'Oleh', cell: (r) => r.created_by_name ?? '—' },
                  { header: 'Jumlah', align: 'right', cell: (r) => formatRp(r.refund_total) },
                ]}
              />
            </Card>
          )}
          {voiding && <VoidDialog sale={s} onClose={() => setVoiding(false)} />}
          {returning && <ReturnDialog sale={s} onClose={() => setReturning(false)} />}
        </>
      )}
    </QueryState>
  );
}

function Row({ label, value }: { label: string; value: ReactNode }) {
  return (
    <div className="flex justify-between gap-3">
      <dt className="text-stone-500">{label}</dt>
      <dd className="num text-right">{value}</dd>
    </div>
  );
}

function VoidDialog({ sale, onClose }: { sale: Sale; onClose: () => void }) {
  const qc = useQueryClient();
  const toast = useToast();
  const [reason, setReason] = useState('');
  const voidSale = useMutation({
    mutationFn: () => api(`/sales/${sale.id}/void`, { method: 'POST', body: { reason: reason.trim() } }),
    onSuccess: () => {
      toast.success('Penjualan dibatalkan');
      qc.invalidateQueries({ queryKey: ['sale', sale.id] });
      qc.invalidateQueries({ queryKey: ['sales'] });
      onClose();
    },
    onError: (error) => toast.error(errorMessage(error)),
  });
  return (
    <Modal
      open
      onClose={onClose}
      title={`Batalkan ${sale.number}?`}
      footer={
        <>
          <Button onClick={onClose}>Kembali</Button>
          <Button variant="danger" loading={voidSale.isPending} disabled={!reason.trim()} onClick={() => voidSale.mutate()}>Batalkan penjualan</Button>
        </>
      }
    >
      <p className="mb-3 text-sm text-stone-600">Stok dan unit IMEI kembali ke lokasi, dan jurnalnya dibalik. Uang dikembalikan di luar sistem.</p>
      <Field label="Alasan"><Textarea rows={2} value={reason} onChange={(e) => setReason(e.target.value)} autoFocus /></Field>
    </Modal>
  );
}

function ReturnDialog({ sale, onClose }: { sale: Sale; onClose: () => void }) {
  const qc = useQueryClient();
  const toast = useToast();
  const methods = usePaymentMethods(sale.location_id);
  const open = sale.lines.filter((l) => l.qty - l.returned_qty > 0);
  const [qty, setQty] = useState<Record<string, string>>({});
  const [defective, setDefective] = useState<Record<string, boolean>>({});
  const [methodId, setMethodId] = useState('');
  const [reason, setReason] = useState('');

  const chosen = open.filter((l) => Number(qty[l.id]) > 0);
  const refund = chosen.reduce((s, l) => s + (toNumber(l.line_total) * Number(qty[l.id])) / l.qty, 0);
  const submit = useMutation({
    mutationFn: () =>
      api(`/sales/${sale.id}/returns`, {
        method: 'POST',
        body: {
          lines: chosen.map((l) => ({ sale_line_id: l.id, qty: Number(qty[l.id]), restock: !defective[l.id] })),
          refund_method_id: Number(methodId),
          reason: reason.trim(),
        },
      }),
    onSuccess: () => {
      toast.success('Retur dicatat');
      qc.invalidateQueries({ queryKey: ['sale', sale.id] });
      qc.invalidateQueries({ queryKey: ['sales'] });
      onClose();
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  return (
    <Modal
      open
      wide
      onClose={onClose}
      title={`Retur ${sale.number}`}
      footer={
        <>
          <Button onClick={onClose}>Batal</Button>
          <Button variant="primary" loading={submit.isPending} disabled={chosen.length === 0 || !methodId || !reason.trim()} onClick={() => submit.mutate()}>
            Retur · kembalikan {formatRp(refund)}
          </Button>
        </>
      }
    >
      <div className="space-y-2">
        {open.map((l) => {
          const max = l.qty - l.returned_qty;
          return (
            <div key={l.id} className="flex flex-wrap items-center gap-3 rounded-lg border border-stone-200 p-2">
              <div className="min-w-48 flex-1">
                <div className="text-sm font-medium">{l.description}</div>
                {(l.imei1 || l.serial_number) && <div className="font-mono text-xs text-stone-500">{unitLabel(l)}</div>}
              </div>
              <Input type="number" min={0} max={max} className="w-20" placeholder="0" value={qty[l.id] ?? ''} onChange={(e) => setQty((q) => ({ ...q, [l.id]: e.target.value }))} />
              <span className="text-xs text-stone-500">maks {max}</span>
              {l.line_type === 'goods' && <Checkbox label="Rusak (tidak kembali ke stok)" checked={!!defective[l.id]} onChange={(e) => setDefective((d) => ({ ...d, [l.id]: e.target.checked }))} />}
            </div>
          );
        })}
      </div>
      <div className="mt-4 grid gap-4 sm:grid-cols-2">
        <Field label="Dikembalikan via">
          <Select value={methodId} onChange={(e) => setMethodId(e.target.value)}>
            <option value="">Pilih metode…</option>
            {methods.data?.map((m) => <option key={m.id} value={m.id}>{m.name}</option>)}
          </Select>
        </Field>
        <Field label="Alasan"><Input value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
      </div>
    </Modal>
  );
}
