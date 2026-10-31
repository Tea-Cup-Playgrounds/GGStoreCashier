import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Download, Plus, Trash2 } from 'lucide-react';
import { api, errorMessage } from '../../api/client';
import type { Account, Journal, JournalSummary } from '../../api/types';
import { useAuth } from '../../auth/AuthContext';
import { LocationSelect, useLocationChoice, useLocations } from '../../lib/locations';
import { downloadCsv } from '../../lib/csv';
import { firstOfMonth, formatDate, formatRp, toNumber, today } from '../../lib/format';
import { Badge, Button, ConfirmButton, DataTable, Field, Input, Modal, PageHeader, QueryState, Select, Spinner, Toolbar, useToast } from '../../components/ui';

export const SOURCE_TYPES: Record<string, string> = {
  sale: 'Penjualan',
  sale_void: 'Pembatalan penjualan',
  sale_return: 'Retur penjualan',
  goods_receipt: 'Penerimaan barang',
  supplier_payment: 'Pembayaran supplier',
  stock_adjustment: 'Penyesuaian stok',
  opname: 'Stok opname',
  transfer: 'Transfer',
  cash_session: 'Shift kasir',
  expense: 'Biaya',
  manual: 'Jurnal manual',
};

export const useAccounts = () =>
  useQuery({ queryKey: ['accounts'], queryFn: () => api<{ accounts: Account[] }>('/accounting/accounts').then((r) => r.accounts), staleTime: 60_000 });

export function JournalsPage() {
  const { access } = useAuth();
  const choice = useLocationChoice('accounting.view', { allowAll: true });
  const accounts = useAccounts();
  const [from, setFrom] = useState(firstOfMonth());
  const [to, setTo] = useState(today());
  const [sourceType, setSourceType] = useState('');
  const [accountId, setAccountId] = useState('');
  const [selected, setSelected] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);

  const journals = useQuery({
    queryKey: ['journals', choice.locationId, from, to, sourceType, accountId],
    queryFn: () =>
      api<{ journals: JournalSummary[] }>('/accounting/journals', { query: { location_id: choice.locationId, from, to, source_type: sourceType, account_id: accountId } }).then((r) => r.journals),
  });

  const exportCsv = () =>
    downloadCsv(`jurnal-${from}-${to}`, ['Nomor', 'Tanggal', 'Lokasi', 'Sumber', 'Keterangan', 'Status', 'Jumlah'], (journals.data ?? []).map((j) => [j.number, j.entry_date, j.location_code ?? 'Pusat', SOURCE_TYPES[j.source_type] ?? j.source_type, j.memo, j.status, j.amount]));

  return (
    <>
      <PageHeader
        title="Jurnal"
        description="Jurnal tidak pernah diubah; kesalahan dikoreksi dengan jurnal pembalik."
        actions={
          <>
            <Button icon={<Download className="size-4" />} disabled={!journals.data?.length} onClick={exportCsv}>CSV</Button>
            {access.can('accounting.post_manual') && <Button variant="primary" icon={<Plus className="size-4" />} onClick={() => setCreating(true)}>Jurnal manual</Button>}
          </>
        }
      />
      <Toolbar>
        <LocationSelect choice={choice} />
        <Field label="Dari" className="w-40"><Input type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></Field>
        <Field label="Sampai" className="w-40"><Input type="date" value={to} onChange={(e) => setTo(e.target.value)} /></Field>
        <Field label="Sumber" className="w-48">
          <Select value={sourceType} onChange={(e) => setSourceType(e.target.value)}>
            <option value="">Semua</option>
            {Object.entries(SOURCE_TYPES).map(([k, label]) => <option key={k} value={k}>{label}</option>)}
          </Select>
        </Field>
        <Field label="Akun" className="w-56">
          <Select value={accountId} onChange={(e) => setAccountId(e.target.value)}>
            <option value="">Semua</option>
            {accounts.data?.filter((a) => a.is_postable).map((a) => <option key={a.id} value={a.id}>{a.code} {a.name}</option>)}
          </Select>
        </Field>
      </Toolbar>
      <QueryState query={journals}>
        <DataTable
          rows={journals.data ?? []}
          rowKey={(j) => j.id}
          onRowClick={(j) => setSelected(j.id)}
          empty="Tidak ada jurnal"
          columns={[
            { header: 'Nomor', cell: (j) => <span className="font-mono text-xs">{j.number}</span> },
            { header: 'Tanggal', cell: (j) => formatDate(j.entry_date) },
            { header: 'Lokasi', cell: (j) => j.location_code ?? 'Pusat' },
            { header: 'Sumber', cell: (j) => SOURCE_TYPES[j.source_type] ?? j.source_type },
            { header: 'Keterangan', cell: (j) => <span className="text-stone-600">{j.memo}</span> },
            { header: 'Jumlah', align: 'right', cell: (j) => formatRp(j.amount) },
            { header: '', cell: (j) => (j.status === 'void' ? <Badge tone="red">Dibatalkan</Badge> : j.reverses_entry_id ? <Badge tone="amber">Pembalik</Badge> : null) },
          ]}
        />
      </QueryState>
      {selected && <JournalDialog id={selected} onClose={() => setSelected(null)} />}
      {creating && <ManualJournalDialog onClose={() => setCreating(false)} />}
    </>
  );
}

function JournalDialog({ id, onClose }: { id: string; onClose: () => void }) {
  const { access } = useAuth();
  const qc = useQueryClient();
  const toast = useToast();
  const [reason, setReason] = useState('');
  const journal = useQuery({ queryKey: ['journal', id], queryFn: () => api<{ journal: Journal }>(`/accounting/journals/${id}`).then((r) => r.journal) });
  const j = journal.data;
  const canVoid = j && j.source_type === 'manual' && j.status === 'posted' && !j.reverses_entry_id && access.can('accounting.post_manual', j.location_id);
  const total = (key: 'debit' | 'credit') => j?.lines.reduce((s, l) => s + toNumber(l[key]), 0) ?? 0;

  return (
    <Modal
      open
      wide
      onClose={onClose}
      title={j ? `${j.number} · ${formatDate(j.entry_date)}` : 'Jurnal'}
      footer={
        <>
          {canVoid && (
            <>
              <Input className="w-64" placeholder="Alasan pembatalan" value={reason} onChange={(e) => setReason(e.target.value)} />
              <ConfirmButton
                label="Batalkan jurnal"
                title="Batalkan jurnal?"
                message="Jurnal pembalik akan dibuat dengan tanggal hari ini."
                disabled={!reason.trim()}
                onConfirm={async () => {
                  await api(`/accounting/journals/${id}/void`, { method: 'POST', body: { reason: reason.trim() } });
                  toast.success('Jurnal dibatalkan');
                  qc.invalidateQueries({ queryKey: ['journals'] });
                  qc.invalidateQueries({ queryKey: ['journal', id] });
                }}
              />
            </>
          )}
          <div className="flex-1" />
          <Button onClick={onClose}>Tutup</Button>
        </>
      }
    >
      {!j ? (
        <div className="flex justify-center py-6"><Spinner /></div>
      ) : (
        <>
          <p className="mb-3 text-sm text-stone-600">
            {SOURCE_TYPES[j.source_type] ?? j.source_type} · {j.location_code ?? 'Pusat'} · {j.memo} · dibuat oleh {j.created_by_name ?? 'sistem'}
          </p>
          <DataTable
            rows={j.lines}
            rowKey={(l) => l.id}
            columns={[
              { header: 'Akun', cell: (l) => <span><span className="font-mono text-xs">{l.account_code}</span> {l.account_name}</span> },
              { header: 'Keterangan', cell: (l) => l.memo ?? '' },
              { header: 'Debit', align: 'right', cell: (l) => (toNumber(l.debit) ? formatRp(l.debit) : '') },
              { header: 'Kredit', align: 'right', cell: (l) => (toNumber(l.credit) ? formatRp(l.credit) : '') },
            ]}
            footer={
              <tr>
                <td className="px-3 py-2" colSpan={2}>Total</td>
                <td className="num px-3 py-2 text-right">{formatRp(total('debit'))}</td>
                <td className="num px-3 py-2 text-right">{formatRp(total('credit'))}</td>
              </tr>
            }
          />
        </>
      )}
    </Modal>
  );
}

interface LineRow {
  accountCode: string;
  debit: string;
  credit: string;
  memo: string;
}

function ManualJournalDialog({ onClose }: { onClose: () => void }) {
  const { access } = useAuth();
  const qc = useQueryClient();
  const toast = useToast();
  const accounts = useAccounts();
  const locations = useLocations();
  const [date, setDate] = useState(today());
  const [locationId, setLocationId] = useState('');
  const [memo, setMemo] = useState('');
  const [lines, setLines] = useState<LineRow[]>([
    { accountCode: '', debit: '', credit: '', memo: '' },
    { accountCode: '', debit: '', credit: '', memo: '' },
  ]);
  const postable = accounts.data?.filter((a) => a.is_postable && a.is_active) ?? [];
  const debit = lines.reduce((s, l) => s + (Number(l.debit) || 0), 0);
  const credit = lines.reduce((s, l) => s + (Number(l.credit) || 0), 0);
  const balanced = Math.abs(debit - credit) < 0.005 && debit > 0;
  // A company-wide entry (no location) needs the permission at every location.
  const companyWide = access.locationsFor('accounting.post_manual') === null;
  const set = (i: number, patch: Partial<LineRow>) => setLines((ls) => ls.map((l, j) => (j === i ? { ...l, ...patch } : l)));

  const post = useMutation({
    mutationFn: () =>
      api('/accounting/journals', {
        method: 'POST',
        body: {
          date,
          location_id: locationId ? Number(locationId) : null,
          memo: memo.trim(),
          lines: lines.filter((l) => l.accountCode).map((l) => ({ account_code: l.accountCode, debit: Number(l.debit) || 0, credit: Number(l.credit) || 0, memo: l.memo.trim() || null })),
        },
      }),
    onSuccess: () => {
      toast.success('Jurnal diposting');
      qc.invalidateQueries({ queryKey: ['journals'] });
      onClose();
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  return (
    <Modal
      open
      wide
      onClose={onClose}
      title="Jurnal manual"
      footer={
        <>
          <span className={`text-sm ${balanced ? 'text-green-700' : 'text-red-600'}`}>
            Debit {formatRp(debit)} · Kredit {formatRp(credit)} {balanced ? '· seimbang' : '· belum seimbang'}
          </span>
          <div className="flex-1" />
          <Button onClick={onClose}>Batal</Button>
          <Button variant="primary" loading={post.isPending} disabled={!balanced || !memo.trim() || (!locationId && !companyWide)} onClick={() => post.mutate()}>Posting</Button>
        </>
      }
    >
      <div className="mb-4 grid gap-4 sm:grid-cols-3">
        <Field label="Tanggal"><Input type="date" value={date} onChange={(e) => setDate(e.target.value)} /></Field>
        <Field label="Lokasi" hint={companyWide ? 'Kosongkan untuk jurnal kantor pusat' : undefined}>
          <Select value={locationId} onChange={(e) => setLocationId(e.target.value)}>
            {companyWide ? <option value="">Pusat (tanpa lokasi)</option> : <option value="">Pilih lokasi…</option>}
            {locations.data?.filter((l) => access.can('accounting.post_manual', l.id)).map((l) => <option key={l.id} value={l.id}>{l.name}</option>)}
          </Select>
        </Field>
        <Field label="Keterangan"><Input value={memo} onChange={(e) => setMemo(e.target.value)} placeholder="mis. Sewa toko Oktober" /></Field>
      </div>
      <div className="space-y-2">
        {lines.map((l, i) => (
          <div key={i} className="grid grid-cols-[2fr_1fr_1fr_1.5fr_auto] gap-2">
            <Select value={l.accountCode} onChange={(e) => set(i, { accountCode: e.target.value })}>
              <option value="">Pilih akun…</option>
              {postable.map((a) => <option key={a.id} value={a.code}>{a.code} {a.name}</option>)}
            </Select>
            <Input type="number" min={0} placeholder="Debit" value={l.debit} onChange={(e) => set(i, { debit: e.target.value, credit: e.target.value ? '' : l.credit })} />
            <Input type="number" min={0} placeholder="Kredit" value={l.credit} onChange={(e) => set(i, { credit: e.target.value, debit: e.target.value ? '' : l.debit })} />
            <Input placeholder="Keterangan baris" value={l.memo} onChange={(e) => set(i, { memo: e.target.value })} />
            <Button variant="ghost" aria-label="Hapus baris" disabled={lines.length <= 2} onClick={() => setLines((ls) => ls.filter((_, j) => j !== i))}>
              <Trash2 className="size-4" />
            </Button>
          </div>
        ))}
        <Button size="sm" variant="ghost" icon={<Plus className="size-4" />} onClick={() => setLines((ls) => [...ls, { accountCode: '', debit: '', credit: '', memo: '' }])}>
          Tambah baris
        </Button>
      </div>
    </Modal>
  );
}
