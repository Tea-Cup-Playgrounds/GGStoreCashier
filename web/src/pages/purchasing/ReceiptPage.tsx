import { useEffect, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Link, useNavigate, useParams } from 'react-router';
import { ArrowLeft, Plus, Trash2 } from 'lucide-react';
import { api, errorMessage } from '../../api/client';
import type { Grade, Receipt } from '../../api/types';
import { LocationSelect, useLocationChoice } from '../../lib/locations';
import { GRADES, unitLabel, VariantPicker } from '../../lib/catalog';
import { formatDate, formatRp, toNumber, today } from '../../lib/format';
import { Badge, Button, Card, ConfirmButton, DataTable, Field, Input, Modal, PageHeader, QueryState, Select, Textarea, useToast } from '../../components/ui';
import { useSuppliers } from './SuppliersPage';
import { PAYMENT_STATUS } from './ReceiptsPage';

interface ItemRow {
  key: number;
  variantId: number;
  name: string;
  sku: string;
  isSerialized: boolean;
  qty: string;
  unitCost: string;
  taxRate: string;
  identifiers: string; // serialized items: one unit per line, "IMEI1" or "IMEI1, IMEI2" or a serial number
  grade: Grade;
}

let nextKey = 1;

/** "356938035643809, 356938035643817" → IMEIs; anything that isn't 15 digits is a serial number. */
const parseUnits = (text: string, grade: Grade) =>
  text
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      const parts = line.split(/[,;\s]+/).filter(Boolean);
      const isImei = parts.every((p) => /^\d{15}$/.test(p));
      return isImei
        ? { imei1: parts[0], imei2: parts[1] ?? null, serial_number: null, condition_grade: grade }
        : { imei1: null, imei2: null, serial_number: line, condition_grade: grade };
    });

const toRows = (receipt: Receipt): ItemRow[] =>
  receipt.items.map((i) => ({
    key: nextKey++,
    variantId: i.variant_id,
    name: i.name,
    sku: i.sku,
    isSerialized: i.is_serialized,
    qty: String(i.qty),
    unitCost: String(toNumber(i.unit_cost)),
    taxRate: String(toNumber(i.tax_rate)),
    identifiers: i.units
      .filter((u) => u.imei1 || u.serial_number)
      .map((u) => (u.imei1 ? [u.imei1, u.imei2].filter(Boolean).join(', ') : u.serial_number))
      .join('\n'),
    grade: i.units[0]?.condition_grade ?? 'new',
  }));

export function ReceiptPage() {
  const { id } = useParams();
  const isNew = id === undefined || id === 'new';
  const receipt = useQuery({
    queryKey: ['receipt', id],
    queryFn: () => api<{ receipt: Receipt }>(`/purchasing/receipts/${id}`).then((r) => r.receipt),
    enabled: !isNew,
  });

  if (isNew) return <ReceiptEditor receipt={null} />;
  return <QueryState query={receipt}>{receipt.data && (receipt.data.status === 'draft' ? <ReceiptEditor receipt={receipt.data} /> : <PostedReceipt receipt={receipt.data} />)}</QueryState>;
}

function ReceiptEditor({ receipt }: { receipt: Receipt | null }) {
  const navigate = useNavigate();
  const qc = useQueryClient();
  const toast = useToast();
  const choice = useLocationChoice('purchases.manage');
  const suppliers = useSuppliers();
  const [supplierId, setSupplierId] = useState(String(receipt?.supplier_id ?? ''));
  const [invoiceNo, setInvoiceNo] = useState(receipt?.invoice_no ?? '');
  const [invoiceDate, setInvoiceDate] = useState(receipt?.invoice_date ?? today());
  const [dueDate, setDueDate] = useState(receipt?.due_date ?? '');
  const [note, setNote] = useState(receipt?.note ?? '');
  const [items, setItems] = useState<ItemRow[]>(() => (receipt ? toRows(receipt) : []));
  const [picking, setPicking] = useState(false);
  const locationId = receipt?.location_id ?? choice.locationId;

  useEffect(() => {
    if (receipt) setItems(toRows(receipt));
  }, [receipt]);

  const body = () => ({
    location_id: locationId,
    supplier_id: Number(supplierId),
    invoice_no: invoiceNo.trim() || null,
    invoice_date: invoiceDate || null,
    due_date: dueDate || null,
    note: note.trim() || null,
    items: items.map((i) => {
      const units = i.isSerialized ? parseUnits(i.identifiers, i.grade) : [];
      return {
        variant_id: i.variantId,
        qty: units.length > 0 ? units.length : Number(i.qty),
        unit_cost: Number(i.unitCost),
        tax_rate: Number(i.taxRate) || 0,
        ...(units.length > 0 ? { units } : {}),
      };
    }),
  });

  const save = useMutation({
    mutationFn: () =>
      receipt
        ? api<{ receipt: Receipt }>(`/purchasing/receipts/${receipt.id}`, { method: 'PUT', body: body() })
        : api<{ receipt: Receipt }>('/purchasing/receipts', { method: 'POST', body: body() }),
    onSuccess: (res) => {
      toast.success('Draf disimpan');
      qc.invalidateQueries({ queryKey: ['receipts'] });
      qc.setQueryData(['receipt', res.receipt.id], res.receipt);
      if (!receipt) navigate(`/receipts/${res.receipt.id}`, { replace: true });
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  const set = (key: number, patch: Partial<ItemRow>) => setItems((rows) => rows.map((r) => (r.key === key ? { ...r, ...patch } : r)));
  const lineTotal = (i: ItemRow) => {
    const qty = i.isSerialized && i.identifiers.trim() ? parseUnits(i.identifiers, i.grade).length : Number(i.qty) || 0;
    const sub = qty * (Number(i.unitCost) || 0);
    return sub + (sub * (Number(i.taxRate) || 0)) / 100;
  };
  const total = items.reduce((s, i) => s + lineTotal(i), 0);
  const valid = locationId !== null && supplierId && items.length > 0 && items.every((i) => i.unitCost !== '' && (i.isSerialized ? i.identifiers.trim() || Number(i.qty) > 0 : Number(i.qty) > 0));

  return (
    <>
      <Link to="/receipts" className="mb-3 inline-flex items-center gap-1 text-sm text-stone-500 hover:text-stone-800">
        <ArrowLeft className="size-4" /> Penerimaan barang
      </Link>
      <PageHeader
        title={receipt ? `Draf ${receipt.number}` : 'Penerimaan barang baru'}
        description="Simpan sebagai draf, periksa, lalu posting untuk menambah stok. Posting tidak bisa dibatalkan."
        actions={
          <>
            {receipt && (
              <ConfirmButton
                label="Hapus draf"
                title="Hapus draf?"
                message="Draf ini akan dihapus."
                onConfirm={async () => {
                  await api(`/purchasing/receipts/${receipt.id}`, { method: 'DELETE' });
                  qc.invalidateQueries({ queryKey: ['receipts'] });
                  toast.success('Draf dihapus');
                  navigate('/receipts');
                }}
              />
            )}
            <Button loading={save.isPending} disabled={!valid} onClick={() => save.mutate()}>Simpan draf</Button>
            {receipt && (
              <ConfirmButton
                label="Posting"
                variant="primary"
                confirmVariant="primary"
                title="Posting penerimaan barang?"
                message="Stok bertambah, unit IMEI didaftarkan, dan jurnal persediaan/hutang dibuat. Simpan perubahan draf terlebih dahulu. Tindakan ini final."
                confirmLabel="Posting"
                onConfirm={async () => {
                  await api(`/purchasing/receipts/${receipt.id}/post`, { method: 'POST' });
                  toast.success('Penerimaan diposting, stok bertambah');
                  qc.invalidateQueries({ queryKey: ['receipts'] });
                  qc.invalidateQueries({ queryKey: ['receipt', receipt.id] });
                  qc.invalidateQueries({ queryKey: ['stock'] });
                }}
              />
            )}
          </>
        }
      />

      <Card>
        <div className="grid gap-4 sm:grid-cols-3">
          {receipt ? (
            <Field label="Lokasi"><Input value={`${receipt.location_name} (${receipt.location_code})`} disabled /></Field>
          ) : (
            <LocationSelect choice={choice} label="Lokasi penerimaan" />
          )}
          <Field label="Supplier">
            <Select value={supplierId} onChange={(e) => setSupplierId(e.target.value)}>
              <option value="">Pilih supplier…</option>
              {suppliers.data?.filter((s) => s.is_active).map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
            </Select>
          </Field>
          <Field label="No. faktur"><Input value={invoiceNo} onChange={(e) => setInvoiceNo(e.target.value)} /></Field>
          <Field label="Tanggal faktur"><Input type="date" value={invoiceDate} onChange={(e) => setInvoiceDate(e.target.value)} /></Field>
          <Field label="Jatuh tempo"><Input type="date" value={dueDate} onChange={(e) => setDueDate(e.target.value)} /></Field>
          <Field label="Catatan"><Input value={note} onChange={(e) => setNote(e.target.value)} /></Field>
        </div>
      </Card>

      <Card title="Barang" className="mt-5" actions={<Button size="sm" icon={<Plus className="size-4" />} onClick={() => setPicking(true)}>Tambah barang</Button>}>
        {items.length === 0 ? (
          <p className="py-6 text-center text-sm text-stone-500">Belum ada barang.</p>
        ) : (
          <div className="space-y-3">
            {items.map((i) => (
              <div key={i.key} className="rounded-lg border border-stone-200 p-3">
                <div className="mb-2 flex items-start justify-between gap-2">
                  <div>
                    <div className="font-medium">{i.name} {i.isSerialized && <Badge tone="blue">IMEI</Badge>}</div>
                    <div className="font-mono text-xs text-stone-500">{i.sku}</div>
                  </div>
                  <Button size="sm" variant="ghost" aria-label="Hapus barang" onClick={() => setItems((rows) => rows.filter((r) => r.key !== i.key))}>
                    <Trash2 className="size-4" />
                  </Button>
                </div>
                <div className="grid gap-3 sm:grid-cols-4">
                  <Field label={i.isSerialized ? 'Jumlah (jika IMEI belum ada)' : 'Jumlah'}>
                    <Input type="number" min={1} value={i.qty} onChange={(e) => set(i.key, { qty: e.target.value })} disabled={i.isSerialized && !!i.identifiers.trim()} />
                  </Field>
                  <Field label="Harga beli / unit (sebelum pajak)"><Input type="number" min={0} value={i.unitCost} onChange={(e) => set(i.key, { unitCost: e.target.value })} /></Field>
                  <Field label="PPN masukan (%)"><Input type="number" min={0} max={100} value={i.taxRate} onChange={(e) => set(i.key, { taxRate: e.target.value })} /></Field>
                  <Field label="Subtotal"><Input value={formatRp(lineTotal(i))} disabled /></Field>
                  {i.isSerialized && (
                    <>
                      <Field label="IMEI / nomor seri (satu unit per baris)" hint="Dua IMEI dalam satu baris dipisah koma. Di gudang boleh kosong dan diisi nanti." className="sm:col-span-3">
                        <Textarea rows={3} className="font-mono" value={i.identifiers} onChange={(e) => set(i.key, { identifiers: e.target.value })} />
                      </Field>
                      <Field label="Kondisi">
                        <Select value={i.grade} onChange={(e) => set(i.key, { grade: e.target.value as Grade })}>
                          {GRADES.map(([g, label]) => <option key={g} value={g}>{label}</option>)}
                        </Select>
                      </Field>
                    </>
                  )}
                </div>
              </div>
            ))}
            <div className="text-right text-sm">Total termasuk PPN: <b className="num">{formatRp(total)}</b></div>
          </div>
        )}
      </Card>

      {picking && (
        <Modal open onClose={() => setPicking(false)} title="Tambah barang">
          <VariantPicker
            locationId={locationId}
            exclude={items.map((i) => i.variantId)}
            onPick={(v) => {
              setItems((rows) => [...rows, { key: nextKey++, variantId: v.variantId, name: v.name, sku: v.sku, isSerialized: v.isSerialized, qty: v.isSerialized ? '' : '1', unitCost: '', taxRate: '11', identifiers: '', grade: 'new' }]);
              setPicking(false);
            }}
          />
        </Modal>
      )}
    </>
  );
}

function PostedReceipt({ receipt }: { receipt: Receipt }) {
  const [paying, setPaying] = useState(false);
  const outstanding = toNumber(receipt.grand_total) - toNumber(receipt.paid_total);
  const [label, tone] = PAYMENT_STATUS[receipt.payment_status];
  return (
    <>
      <Link to="/receipts" className="mb-3 inline-flex items-center gap-1 text-sm text-stone-500 hover:text-stone-800">
        <ArrowLeft className="size-4" /> Penerimaan barang
      </Link>
      <PageHeader
        title={receipt.number}
        description={`${receipt.supplier_name} → ${receipt.location_name} · diposting ${formatDate(receipt.posted_at)} oleh ${receipt.posted_by_name ?? '—'}`}
        actions={outstanding > 0.004 && <Button variant="primary" onClick={() => setPaying(true)}>Catat pembayaran</Button>}
      />
      <div className="mb-5 grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Card><div className="text-xs text-stone-500">Total</div><div className="num text-lg font-semibold">{formatRp(receipt.grand_total)}</div><div className="text-xs text-stone-500">PPN {formatRp(receipt.tax_total)}</div></Card>
        <Card><div className="text-xs text-stone-500">Dibayar</div><div className="num text-lg font-semibold">{formatRp(receipt.paid_total)}</div></Card>
        <Card><div className="text-xs text-stone-500">Sisa hutang</div><div className="num text-lg font-semibold">{formatRp(outstanding)}</div></Card>
        <Card><div className="text-xs text-stone-500">Status</div><div className="mt-1"><Badge tone={tone}>{label}</Badge></div><div className="mt-1 text-xs text-stone-500">Jatuh tempo {formatDate(receipt.due_date)}</div></Card>
      </div>
      <Card title="Barang">
        <DataTable
          rows={receipt.items}
          rowKey={(i) => i.id}
          columns={[
            { header: 'Barang', cell: (i) => <div><div className="font-medium">{i.name}</div>{i.units.length > 0 && <div className="mt-1 space-y-0.5 font-mono text-xs text-stone-500">{i.units.map((u) => <div key={u.id}>{unitLabel(u)}</div>)}</div>}</div> },
            { header: 'Qty', align: 'right', cell: (i) => i.qty },
            { header: 'Harga beli', align: 'right', cell: (i) => formatRp(i.unit_cost) },
            { header: 'PPN', align: 'right', cell: (i) => `${toNumber(i.tax_rate)}% · ${formatRp(i.tax_amount)}` },
            { header: 'Total', align: 'right', cell: (i) => formatRp(i.line_total) },
          ]}
        />
      </Card>
      <Card title="Pembayaran" className="mt-5">
        <DataTable
          rows={receipt.payments}
          rowKey={(p) => p.id}
          empty="Belum ada pembayaran"
          columns={[
            { header: 'Tanggal', cell: (p) => formatDate(p.paid_at) },
            { header: 'Metode', cell: (p) => ({ cash: 'Tunai', transfer: 'Transfer', giro: 'Giro', other: 'Lainnya' })[p.method] },
            { header: 'Referensi', cell: (p) => p.reference ?? '—' },
            { header: 'Oleh', cell: (p) => p.created_by_name ?? '—' },
            { header: 'Jumlah', align: 'right', cell: (p) => formatRp(p.amount) },
          ]}
        />
      </Card>
      {paying && <PaymentDialog receipt={receipt} outstanding={outstanding} onClose={() => setPaying(false)} />}
    </>
  );
}

function PaymentDialog({ receipt, outstanding, onClose }: { receipt: Receipt; outstanding: number; onClose: () => void }) {
  const qc = useQueryClient();
  const toast = useToast();
  const [amount, setAmount] = useState(String(Math.round(outstanding * 100) / 100));
  const [method, setMethod] = useState('transfer');
  const [reference, setReference] = useState('');
  const [paidAt, setPaidAt] = useState(today());
  const [note, setNote] = useState('');
  const pay = useMutation({
    mutationFn: () => api('/purchasing/payments', { method: 'POST', body: { receipt_id: receipt.id, amount: Number(amount), method, reference: reference.trim() || null, paid_at: paidAt, note: note.trim() || null } }),
    onSuccess: () => {
      toast.success('Pembayaran dicatat');
      qc.invalidateQueries({ queryKey: ['receipt', receipt.id] });
      qc.invalidateQueries({ queryKey: ['receipts'] });
      qc.invalidateQueries({ queryKey: ['suppliers'] });
      onClose();
    },
    onError: (error) => toast.error(errorMessage(error)),
  });
  return (
    <Modal
      open
      onClose={onClose}
      title={`Bayar ${receipt.number}`}
      footer={
        <>
          <Button onClick={onClose}>Batal</Button>
          <Button variant="primary" loading={pay.isPending} disabled={!(Number(amount) > 0)} onClick={() => pay.mutate()}>Simpan</Button>
        </>
      }
    >
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="Jumlah" hint={`Sisa hutang ${formatRp(outstanding)}`}><Input type="number" min={0} value={amount} onChange={(e) => setAmount(e.target.value)} /></Field>
        <Field label="Metode">
          <Select value={method} onChange={(e) => setMethod(e.target.value)}>
            <option value="transfer">Transfer</option>
            <option value="cash">Tunai</option>
            <option value="giro">Giro</option>
            <option value="other">Lainnya</option>
          </Select>
        </Field>
        <Field label="Tanggal bayar"><Input type="date" value={paidAt} onChange={(e) => setPaidAt(e.target.value)} /></Field>
        <Field label="Referensi"><Input value={reference} onChange={(e) => setReference(e.target.value)} placeholder="No. transfer / giro" /></Field>
        <Field label="Catatan" className="sm:col-span-2"><Input value={note} onChange={(e) => setNote(e.target.value)} /></Field>
      </div>
    </Modal>
  );
}
