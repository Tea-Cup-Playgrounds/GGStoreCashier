import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Link, useNavigate, useParams } from 'react-router';
import { ArrowLeft, Plus, Trash2 } from 'lucide-react';
import { api, errorMessage } from '../../api/client';
import type { Transfer, Unit } from '../../api/types';
import { useAuth } from '../../auth/AuthContext';
import { LocationSelect, useDestinations, useLocationChoice } from '../../lib/locations';
import { unitLabel, unitStatusBadge, VariantPicker } from '../../lib/catalog';
import { formatDateTime } from '../../lib/format';
import { Badge, Button, Card, Checkbox, ConfirmButton, DataTable, Field, Input, Modal, PageHeader, QueryState, Select, Spinner, Textarea, useToast } from '../../components/ui';
import { TRANSFER_STATUS } from './TransfersPage';

interface ItemRow {
  variantId: number;
  name: string;
  sku: string;
  isSerialized: boolean;
  qty: string;
  unitIds: string[];
}

export function TransferPage() {
  const { id } = useParams();
  const isNew = id === undefined || id === 'new';
  const transfer = useQuery({
    queryKey: ['transfer', id],
    queryFn: () => api<{ transfer: Transfer }>(`/transfers/${id}`).then((r) => r.transfer),
    enabled: !isNew,
  });
  if (isNew) return <TransferEditor transfer={null} />;
  return <QueryState query={transfer}>{transfer.data && (transfer.data.status === 'draft' ? <TransferEditor transfer={transfer.data} /> : <TransferView transfer={transfer.data} />)}</QueryState>;
}

function TransferEditor({ transfer }: { transfer: Transfer | null }) {
  const navigate = useNavigate();
  const qc = useQueryClient();
  const toast = useToast();
  const { access } = useAuth();
  const choice = useLocationChoice('transfers.create');
  const destinations = useDestinations();
  const fromId = transfer?.from_location_id ?? choice.locationId;
  const [toId, setToId] = useState(String(transfer?.to_location_id ?? ''));
  const [note, setNote] = useState(transfer?.note ?? '');
  const [items, setItems] = useState<ItemRow[]>(
    () =>
      transfer?.items.map((i) => ({ variantId: i.variant_id, name: i.name, sku: i.sku, isSerialized: i.is_serialized, qty: String(i.qty_sent), unitIds: i.units.map((u) => u.unit_id) })) ?? [],
  );
  const [picking, setPicking] = useState(false);

  const body = () => ({
    from_location_id: fromId,
    to_location_id: Number(toId),
    note: note.trim() || null,
    items: items.map((i) => (i.isSerialized ? { variant_id: i.variantId, unit_ids: i.unitIds } : { variant_id: i.variantId, qty: Number(i.qty) })),
  });
  const save = useMutation({
    mutationFn: () =>
      transfer
        ? api<{ transfer: Transfer }>(`/transfers/${transfer.id}`, { method: 'PUT', body: body() })
        : api<{ transfer: Transfer }>('/transfers', { method: 'POST', body: body() }),
    onSuccess: (res) => {
      toast.success('Draf transfer disimpan');
      qc.invalidateQueries({ queryKey: ['transfers'] });
      qc.setQueryData(['transfer', res.transfer.id], res.transfer);
      if (!transfer) navigate(`/transfers/${res.transfer.id}`, { replace: true });
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  const set = (variantId: number, patch: Partial<ItemRow>) => setItems((rows) => rows.map((r) => (r.variantId === variantId ? { ...r, ...patch } : r)));
  const valid = fromId !== null && toId && Number(toId) !== fromId && items.length > 0 && items.every((i) => (i.isSerialized ? i.unitIds.length > 0 : Number(i.qty) > 0));

  return (
    <>
      <Link to="/transfers" className="mb-3 inline-flex items-center gap-1 text-sm text-stone-500 hover:text-stone-800">
        <ArrowLeft className="size-4" /> Transfer stok
      </Link>
      <PageHeader
        title={transfer ? `Draf ${transfer.number}` : 'Transfer baru'}
        actions={
          <>
            {transfer && (
              <ConfirmButton
                label="Batalkan"
                title="Batalkan transfer?"
                message="Draf ini dibatalkan; stok tidak berubah."
                onConfirm={async () => {
                  await api(`/transfers/${transfer.id}/cancel`, { method: 'POST' });
                  qc.invalidateQueries({ queryKey: ['transfers'] });
                  qc.invalidateQueries({ queryKey: ['transfer', transfer.id] });
                  toast.success('Transfer dibatalkan');
                }}
              />
            )}
            <Button loading={save.isPending} disabled={!valid} onClick={() => save.mutate()}>Simpan draf</Button>
            {transfer && access.can('transfers.send', transfer.from_location_id) && (
              <ConfirmButton
                label="Kirim"
                variant="primary"
                confirmVariant="primary"
                title="Kirim transfer?"
                message="Stok keluar dari lokasi asal dan berstatus dalam pengiriman sampai diterima. Simpan perubahan draf terlebih dahulu."
                confirmLabel="Kirim"
                onConfirm={async () => {
                  await api(`/transfers/${transfer.id}/send`, { method: 'POST' });
                  qc.invalidateQueries({ queryKey: ['transfers'] });
                  qc.invalidateQueries({ queryKey: ['transfer', transfer.id] });
                  toast.success('Transfer dikirim');
                }}
              />
            )}
          </>
        }
      />
      <Card>
        <div className="grid gap-4 sm:grid-cols-3">
          {transfer ? <Field label="Dari"><Input value={`${transfer.from_name} (${transfer.from_code})`} disabled /></Field> : <LocationSelect choice={choice} label="Dari" />}
          <Field label="Ke">
            <Select value={toId} onChange={(e) => setToId(e.target.value)}>
              <option value="">Pilih tujuan…</option>
              {destinations.data?.filter((l) => l.id !== fromId).map((l) => <option key={l.id} value={l.id}>{l.name} ({l.code})</option>)}
            </Select>
          </Field>
          <Field label="Catatan"><Input value={note} onChange={(e) => setNote(e.target.value)} /></Field>
        </div>
      </Card>
      <Card title="Barang" className="mt-5" actions={<Button size="sm" icon={<Plus className="size-4" />} disabled={fromId === null} onClick={() => setPicking(true)}>Tambah barang</Button>}>
        {items.length === 0 ? (
          <p className="py-6 text-center text-sm text-stone-500">Belum ada barang.</p>
        ) : (
          <div className="space-y-3">
            {items.map((i) => (
              <div key={i.variantId} className="rounded-lg border border-stone-200 p-3">
                <div className="flex items-start justify-between gap-2">
                  <div>
                    <div className="font-medium">{i.name} {i.isSerialized && <Badge tone="blue">IMEI</Badge>}</div>
                    <div className="font-mono text-xs text-stone-500">{i.sku}</div>
                  </div>
                  <div className="flex items-center gap-2">
                    {!i.isSerialized && <Input type="number" min={1} className="w-24" value={i.qty} onChange={(e) => set(i.variantId, { qty: e.target.value })} />}
                    <Button size="sm" variant="ghost" aria-label="Hapus barang" onClick={() => setItems((rows) => rows.filter((r) => r.variantId !== i.variantId))}>
                      <Trash2 className="size-4" />
                    </Button>
                  </div>
                </div>
                {i.isSerialized && fromId !== null && (
                  <UnitChooser locationId={fromId} variantId={i.variantId} selected={i.unitIds} onChange={(unitIds) => set(i.variantId, { unitIds })} />
                )}
              </div>
            ))}
          </div>
        )}
      </Card>
      {picking && fromId !== null && (
        <Modal open onClose={() => setPicking(false)} title="Tambah barang">
          <VariantPicker
            locationId={fromId}
            exclude={items.map((i) => i.variantId)}
            onPick={(v) => {
              setItems((rows) => [...rows, { variantId: v.variantId, name: v.name, sku: v.sku, isSerialized: v.isSerialized, qty: '1', unitIds: [] }]);
              setPicking(false);
            }}
          />
        </Modal>
      )}
    </>
  );
}

/** In-stock units of a variant at the source, as checkboxes (plus units already on the draft). */
function UnitChooser({ locationId, variantId, selected, onChange }: { locationId: number; variantId: number; selected: string[]; onChange: (ids: string[]) => void }) {
  const units = useQuery({
    queryKey: ['units', locationId, 'transfer', variantId],
    queryFn: () => api<{ units: Unit[] }>('/stock/units', { query: { location_id: locationId, variant_id: variantId, status: 'in_stock' } }).then((r) => r.units),
  });
  if (units.isPending) return <Spinner className="mt-2 size-4" />;
  const list = units.data ?? [];
  return (
    <div className="mt-2 grid gap-1 sm:grid-cols-2">
      {list.length === 0 && selected.length === 0 && <p className="text-sm text-stone-500">Tidak ada unit tersedia di lokasi asal.</p>}
      {list.map((u) => (
        <Checkbox
          key={u.id}
          checked={selected.includes(u.id)}
          onChange={(e) => onChange(e.target.checked ? [...selected, u.id] : selected.filter((id) => id !== u.id))}
          label={<span className="font-mono text-xs">{unitLabel(u)}</span>}
        />
      ))}
    </div>
  );
}

function TransferView({ transfer }: { transfer: Transfer }) {
  const { access } = useAuth();
  const [receiving, setReceiving] = useState(false);
  const [resolving, setResolving] = useState(false);
  const [label, tone] = TRANSFER_STATUS[transfer.status];
  const outstanding = transfer.items.reduce((s, i) => s + i.outstanding, 0);
  const canReceive = transfer.status === 'sent' && access.can('transfers.receive', transfer.to_location_id);
  const canResolve = outstanding > 0 && transfer.status === 'partially_received' && access.can('stock.adjust', transfer.from_location_id);

  return (
    <>
      <Link to="/transfers" className="mb-3 inline-flex items-center gap-1 text-sm text-stone-500 hover:text-stone-800">
        <ArrowLeft className="size-4" /> Transfer stok
      </Link>
      <PageHeader
        title={transfer.number}
        description={`${transfer.from_name} → ${transfer.to_name}`}
        actions={
          <>
            <Badge tone={tone}>{label}</Badge>
            {canResolve && <Button onClick={() => setResolving(true)}>Selesaikan sisa</Button>}
            {canReceive && <Button variant="primary" onClick={() => setReceiving(true)}>Terima</Button>}
          </>
        }
      />
      <Card className="mb-5">
        <dl className="grid gap-3 text-sm sm:grid-cols-3">
          <div><dt className="text-stone-500">Dibuat</dt><dd>{formatDateTime(transfer.created_at)} · {transfer.created_by_name ?? '—'}</dd></div>
          <div><dt className="text-stone-500">Dikirim</dt><dd>{formatDateTime(transfer.sent_at)} · {transfer.sent_by_name ?? '—'}</dd></div>
          <div><dt className="text-stone-500">Diterima</dt><dd>{formatDateTime(transfer.received_at)} · {transfer.received_by_name ?? '—'}</dd></div>
          {transfer.note && <div className="sm:col-span-3"><dt className="text-stone-500">Catatan</dt><dd>{transfer.note}</dd></div>}
        </dl>
      </Card>
      <DataTable
        rows={transfer.items}
        rowKey={(i) => i.id}
        columns={[
          {
            header: 'Barang',
            cell: (i) => (
              <div>
                <div className="font-medium">{i.name}</div>
                {i.units.length > 0 && (
                  <div className="mt-1 space-y-0.5">
                    {i.units.map((u) => (
                      <div key={u.unit_id} className="flex items-center gap-2 font-mono text-xs text-stone-600">
                        {unitLabel(u)}
                        {u.outcome === 'received' ? <Badge tone="green">Diterima</Badge> : u.outcome === 'returned' ? <Badge tone="amber">Dikembalikan</Badge> : u.outcome === 'written_off' ? <Badge tone="red">Hilang</Badge> : unitStatusBadge(u.status)}
                      </div>
                    ))}
                  </div>
                )}
              </div>
            ),
          },
          { header: 'Dikirim', align: 'right', cell: (i) => i.qty_sent },
          { header: 'Diterima', align: 'right', cell: (i) => i.qty_received ?? '—' },
          { header: 'Diselesaikan', align: 'right', cell: (i) => i.qty_resolved || '—' },
          { header: 'Belum jelas', align: 'right', cell: (i) => (i.outstanding ? <span className="font-medium text-red-600">{i.outstanding}</span> : '—') },
        ]}
      />
      {receiving && <ReceiveDialog transfer={transfer} onClose={() => setReceiving(false)} />}
      {resolving && <ResolveDialog transfer={transfer} onClose={() => setResolving(false)} />}
    </>
  );
}

function ReceiveDialog({ transfer, onClose }: { transfer: Transfer; onClose: () => void }) {
  const qc = useQueryClient();
  const toast = useToast();
  const [qty, setQty] = useState<Record<string, string>>(() => Object.fromEntries(transfer.items.filter((i) => !i.is_serialized).map((i) => [i.id, String(i.qty_sent)])));
  const [missing, setMissing] = useState<string[]>([]);
  const [note, setNote] = useState('');
  const receive = useMutation({
    mutationFn: () =>
      api<{ message: string }>(`/transfers/${transfer.id}/receive`, {
        method: 'POST',
        body: { items: Object.entries(qty).map(([item_id, q]) => ({ item_id, qty_received: Number(q) })), missing_unit_ids: missing, note: note.trim() || undefined },
      }),
    onSuccess: (res) => {
      toast.success(res.message);
      qc.invalidateQueries({ queryKey: ['transfer', transfer.id] });
      qc.invalidateQueries({ queryKey: ['transfers'] });
      qc.invalidateQueries({ queryKey: ['stock'] });
      onClose();
    },
    onError: (error) => toast.error(errorMessage(error)),
  });
  return (
    <Modal
      open
      wide
      onClose={onClose}
      title={`Terima ${transfer.number}`}
      footer={
        <>
          <Button onClick={onClose}>Batal</Button>
          <Button variant="primary" loading={receive.isPending} onClick={() => receive.mutate()}>Konfirmasi penerimaan</Button>
        </>
      }
    >
      <p className="mb-4 text-sm text-stone-600">Isi jumlah yang benar-benar sampai. Untuk unit IMEI, centang yang <b>tidak</b> sampai.</p>
      <div className="space-y-3">
        {transfer.items.map((i) => (
          <div key={i.id} className="rounded-lg border border-stone-200 p-3">
            <div className="flex items-center justify-between gap-2">
              <div className="font-medium">{i.name}</div>
              {!i.is_serialized && (
                <div className="flex items-center gap-2 text-sm">
                  <Input type="number" min={0} max={i.qty_sent} className="w-24" value={qty[i.id]} onChange={(e) => setQty((q) => ({ ...q, [i.id]: e.target.value }))} />
                  <span className="text-stone-500">dari {i.qty_sent}</span>
                </div>
              )}
            </div>
            {i.is_serialized && (
              <div className="mt-2 grid gap-1 sm:grid-cols-2">
                {i.units.map((u) => (
                  <Checkbox
                    key={u.unit_id}
                    checked={missing.includes(u.unit_id)}
                    onChange={(e) => setMissing((m) => (e.target.checked ? [...m, u.unit_id] : m.filter((x) => x !== u.unit_id)))}
                    label={<span className="font-mono text-xs">Tidak sampai: {unitLabel(u)}</span>}
                  />
                ))}
              </div>
            )}
          </div>
        ))}
        <Field label="Catatan"><Input value={note} onChange={(e) => setNote(e.target.value)} /></Field>
      </div>
    </Modal>
  );
}

function ResolveDialog({ transfer, onClose }: { transfer: Transfer; onClose: () => void }) {
  const qc = useQueryClient();
  const toast = useToast();
  const [action, setAction] = useState<'return' | 'write_off'>('return');
  const [note, setNote] = useState('');
  const resolve = useMutation({
    mutationFn: () => api<{ message: string }>(`/transfers/${transfer.id}/resolve`, { method: 'POST', body: { action, note: note.trim() } }),
    onSuccess: (res) => {
      toast.success(res.message);
      qc.invalidateQueries({ queryKey: ['transfer', transfer.id] });
      qc.invalidateQueries({ queryKey: ['transfers'] });
      qc.invalidateQueries({ queryKey: ['stock'] });
      onClose();
    },
    onError: (error) => toast.error(errorMessage(error)),
  });
  return (
    <Modal
      open
      onClose={onClose}
      title="Selesaikan barang yang belum sampai"
      footer={
        <>
          <Button onClick={onClose}>Batal</Button>
          <Button variant={action === 'write_off' ? 'danger' : 'primary'} loading={resolve.isPending} disabled={!note.trim()} onClick={() => resolve.mutate()}>Simpan</Button>
        </>
      }
    >
      <div className="space-y-4">
        <Field label="Tindakan">
          <Select value={action} onChange={(e) => setAction(e.target.value as 'return' | 'write_off')}>
            <option value="return">Kembalikan ke stok lokasi asal</option>
            <option value="write_off">Catat sebagai hilang (kerugian persediaan)</option>
          </Select>
        </Field>
        <Field label="Alasan"><Textarea rows={2} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
      </div>
    </Modal>
  );
}
