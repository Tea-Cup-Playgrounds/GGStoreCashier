import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Link } from 'react-router';
import { api, errorMessage } from '../../api/client';
import type { JournalSummary } from '../../api/types';
import { useAuth } from '../../auth/AuthContext';
import { useLocations } from '../../lib/locations';
import { formatDate, formatRp, today } from '../../lib/format';
import { Badge, Button, Card, DataTable, Field, Input, PageHeader, QueryState, Select, useToast } from '../../components/ui';
import { JournalDialog, useAccounts } from './JournalsPage';
import { TYPE_LABELS } from './ReportsPages';

interface Mapping {
  key: string;
  location_id: number | null;
  account_code: string;
}

const SIDE_HINT: Record<string, string> = {
  asset: 'Aset: isi di Debit',
  liability: 'Kewajiban: isi di Kredit',
  equity: 'Ekuitas: isi di Kredit',
};

/**
 * Saldo Awal: what the business had when it started using the system (cash, bank, receivables,
 * supplier debt, loans, capital). The difference goes to Ekuitas Saldo Awal. Stock comes in as
 * opening stock (Stok → Sesuaikan → "Stok awal") so quantities and value stay together.
 */
export function OpeningBalancesPage() {
  const { access } = useAuth();
  const qc = useQueryClient();
  const toast = useToast();
  const accounts = useAccounts();
  const locations = useLocations();
  const mappings = useQuery({
    queryKey: ['mappings'],
    queryFn: () => api<{ mappings: Mapping[] }>('/accounting/mappings').then((r) => r.mappings),
    staleTime: 60_000,
  });
  const entries = useQuery({
    queryKey: ['journals', 'opening_balance'],
    queryFn: () => api<{ journals: JournalSummary[] }>('/accounting/journals', { query: { source_type: 'opening_balance' } }).then((r) => r.journals),
  });
  const canPost = access.can('accounting.post_manual');
  const companyWide = access.locationsFor('accounting.post_manual') === null;
  const [date, setDate] = useState(today());
  const [locationId, setLocationId] = useState('');
  const [memo, setMemo] = useState('Saldo awal');
  const [amounts, setAmounts] = useState<Record<string, { debit: string; credit: string }>>({});
  const [selected, setSelected] = useState<string | null>(null);

  const mapped = (key: string) => mappings.data?.find((m) => m.key === key && m.location_id === null)?.account_code;
  const inventoryCode = mapped('inventory');
  const openingCode = mapped('opening_balance');
  // Stock comes in as opening stock; the inter-location account only through transfers.
  const excluded = new Set([inventoryCode, openingCode, mapped('inter_location')]);
  const balanceAccounts = (accounts.data ?? []).filter(
    (a) => a.is_postable && a.is_active && ['asset', 'liability', 'equity'].includes(a.type) && !excluded.has(a.code),
  );
  const debit = Object.values(amounts).reduce((s, v) => s + (Number(v.debit) || 0), 0);
  const credit = Object.values(amounts).reduce((s, v) => s + (Number(v.credit) || 0), 0);
  const toOpening = debit - credit; // > 0: credited to Ekuitas Saldo Awal
  const set = (code: string, side: 'debit' | 'credit', value: string) =>
    setAmounts((a) => ({ ...a, [code]: { debit: side === 'debit' ? value : '', credit: side === 'credit' ? value : '' } }));

  const post = useMutation({
    mutationFn: () =>
      api<{ message: string }>('/accounting/opening-balances', {
        method: 'POST',
        body: {
          date,
          location_id: locationId ? Number(locationId) : null,
          memo: memo.trim(),
          lines: Object.entries(amounts)
            .filter(([, v]) => Number(v.debit) > 0 || Number(v.credit) > 0)
            .map(([code, v]) => ({ account_code: code, debit: Number(v.debit) || 0, credit: Number(v.credit) || 0 })),
        },
      }),
    onSuccess: (res) => {
      toast.success(res.message);
      setAmounts({});
      qc.invalidateQueries({ queryKey: ['journals'] });
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  return (
    <>
      <PageHeader
        title="Saldo Awal"
        description="Saldo akun saat mulai memakai sistem. Selisihnya otomatis masuk ke Ekuitas Saldo Awal."
      />
      <Card className="mb-5">
        <p className="text-sm text-stone-600">
          Isi saldo kas, bank, piutang, hutang, pinjaman, dan modal per tanggal mulai. <b>Persediaan tidak diisi di sini</b>: masukkan sebagai
          stok awal di <Link className="underline" to="/stock">Stok</Link> (Sesuaikan → centang "Stok awal") atau daftarkan unit IMEI dengan
          "Stok awal", supaya jumlah barang dan nilainya selalu sama.
        </p>
      </Card>

      {canPost && (
        <Card title="Catat saldo awal" className="mb-5">
          <div className="mb-4 grid gap-4 sm:grid-cols-3">
            <Field label="Tanggal"><Input type="date" value={date} max={today()} onChange={(e) => setDate(e.target.value)} /></Field>
            <Field label="Lokasi" hint={companyWide ? 'Kosongkan untuk saldo kantor pusat' : undefined}>
              <Select value={locationId} onChange={(e) => setLocationId(e.target.value)}>
                {companyWide ? <option value="">Pusat (tanpa lokasi)</option> : <option value="">Pilih lokasi…</option>}
                {locations.data?.filter((l) => access.can('accounting.post_manual', l.id)).map((l) => <option key={l.id} value={l.id}>{l.name}</option>)}
              </Select>
            </Field>
            <Field label="Keterangan"><Input value={memo} onChange={(e) => setMemo(e.target.value)} /></Field>
          </div>
          <table className="w-full text-sm">
            <thead className="text-left text-xs uppercase text-stone-500">
              <tr>
                <th className="py-1.5">Akun</th>
                <th className="py-1.5">Tipe</th>
                <th className="w-40 py-1.5 text-right">Debit</th>
                <th className="w-40 py-1.5 text-right">Kredit</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-stone-100">
              {balanceAccounts.map((a) => (
                <tr key={a.id}>
                  <td className="py-1.5"><span className="font-mono text-xs text-stone-500">{a.code}</span> {a.name}</td>
                  <td className="py-1.5 text-stone-500" title={SIDE_HINT[a.type]}>{TYPE_LABELS[a.type]}</td>
                  <td className="py-1"><Input type="number" min={0} className="text-right" value={amounts[a.code]?.debit ?? ''} onChange={(e) => set(a.code, 'debit', e.target.value)} /></td>
                  <td className="py-1"><Input type="number" min={0} className="text-right" value={amounts[a.code]?.credit ?? ''} onChange={(e) => set(a.code, 'credit', e.target.value)} /></td>
                </tr>
              ))}
              <tr className="text-stone-600">
                <td className="py-2" colSpan={2}><span className="font-mono text-xs">{openingCode}</span> Ekuitas Saldo Awal (otomatis)</td>
                <td className="num py-2 text-right">{toOpening < 0 ? formatRp(-toOpening) : ''}</td>
                <td className="num py-2 text-right">{toOpening > 0 ? formatRp(toOpening) : ''}</td>
              </tr>
            </tbody>
          </table>
          <div className="mt-4 flex items-center justify-end gap-3">
            <span className="text-sm text-stone-500">Debit {formatRp(Math.max(debit, credit))} · Kredit {formatRp(Math.max(debit, credit))}</span>
            <Button
              variant="primary"
              loading={post.isPending}
              disabled={(debit === 0 && credit === 0) || !memo.trim() || (!locationId && !companyWide)}
              onClick={() => post.mutate()}
            >
              Posting saldo awal
            </Button>
          </div>
        </Card>
      )}

      <Card title="Saldo awal yang sudah dicatat">
        <QueryState query={entries}>
          <DataTable
            rows={entries.data ?? []}
            rowKey={(j) => j.id}
            onRowClick={(j) => setSelected(j.id)}
            empty="Belum ada saldo awal"
            columns={[
              { header: 'Nomor', cell: (j) => <span className="font-mono text-xs">{j.number}</span> },
              { header: 'Tanggal', cell: (j) => formatDate(j.entry_date) },
              { header: 'Lokasi', cell: (j) => j.location_code ?? 'Pusat' },
              { header: 'Keterangan', wrap: true, cell: (j) => j.memo },
              { header: 'Jumlah', align: 'right', cell: (j) => formatRp(j.amount) },
              { header: '', cell: (j) => (j.status === 'void' ? <Badge tone="red">Dibatalkan</Badge> : j.reverses_entry_id ? <Badge tone="amber">Pembalik</Badge> : null) },
            ]}
          />
        </QueryState>
      </Card>
      {selected && <JournalDialog id={selected} onClose={() => setSelected(null)} />}
    </>
  );
}
