import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Download } from 'lucide-react';
import { api } from '../../api/client';
import type { BalanceSheet, BalanceSheetRow, Ledger } from '../../api/types';
import { LocationSelect, useLocationChoice } from '../../lib/locations';
import { downloadCsv } from '../../lib/csv';
import { firstOfMonth, formatDate, formatRp, today } from '../../lib/format';
import { Badge, Button, Card, DataTable, Field, Input, PageHeader, QueryState, Select, Toolbar } from '../../components/ui';
import { JournalDialog, SOURCE_TYPES, useAccounts } from './JournalsPage';
import { STATEMENT_PERMISSIONS } from './ReportsPages';

/** Neraca: assets = liabilities + equity at a date. This year's and earlier years' profit come from the income and expense accounts. */
export function BalanceSheetPage() {
  const choice = useLocationChoice(STATEMENT_PERMISSIONS, { allowAll: true });
  const [to, setTo] = useState(today());
  const report = useQuery({
    queryKey: ['balance-sheet', choice.locationId, to],
    queryFn: () => api<BalanceSheet>('/accounting/balance-sheet', { query: { location_id: choice.locationId, to } }),
  });
  const r = report.data;

  const exportCsv = () => {
    if (!r) return;
    const rows = (part: string, list: BalanceSheetRow[]) => list.map((a) => [part, a.code ?? '', a.name, a.balance]);
    downloadCsv(`neraca-${to}`, ['Bagian', 'Kode', 'Akun', 'Saldo'], [
      ...rows('Aset', r.assets),
      ['', '', 'Total aset', r.totals.assets],
      ...rows('Kewajiban', r.liabilities),
      ['', '', 'Total kewajiban', r.totals.liabilities],
      ...rows('Ekuitas', r.equity),
      ['', '', 'Total ekuitas', r.totals.equity],
      ['', '', 'Total kewajiban dan ekuitas', r.totals.liabilities_and_equity],
    ]);
  };

  const section = (title: string, rows: BalanceSheetRow[], total: number) => (
    <Card title={title}>
      <table className="w-full text-sm">
        <tbody className="divide-y divide-stone-100">
          {rows.length === 0 && (
            <tr>
              <td className="py-2 text-stone-500" colSpan={3}>Belum ada saldo</td>
            </tr>
          )}
          {rows.map((a) => (
            <tr key={a.code ?? a.name}>
              <td className="w-20 py-1.5 pr-3 font-mono text-xs text-stone-500">{a.code}</td>
              <td className="py-1.5">
                {a.name}
                {a.computed && <span className="ml-2 text-xs text-stone-400">dihitung</span>}
              </td>
              <td className={`num py-1.5 text-right ${a.balance < 0 ? 'text-red-600' : ''}`}>{formatRp(a.balance)}</td>
            </tr>
          ))}
          <tr className="font-semibold">
            <td />
            <td className="py-2">Total {title.toLowerCase()}</td>
            <td className="num py-2 text-right">{formatRp(total)}</td>
          </tr>
        </tbody>
      </table>
    </Card>
  );

  return (
    <>
      <PageHeader
        title="Neraca"
        description="Posisi aset, kewajiban, dan ekuitas pada tanggal tertentu. Laba dihitung dari akun pendapatan dan beban (tanpa jurnal penutup)."
        actions={<Button icon={<Download className="size-4" />} disabled={!r} onClick={exportCsv}>CSV</Button>}
      />
      <Toolbar>
        <LocationSelect choice={choice} />
        <Field label="Per tanggal" className="w-40"><Input type="date" value={to} onChange={(e) => setTo(e.target.value)} /></Field>
      </Toolbar>
      <QueryState query={report}>
        {r && (
          <>
            <div className="mb-4 flex flex-wrap items-center gap-3">
              {Math.abs(r.totals.difference) < 0.005 ? (
                <Badge tone="green">Seimbang: aset = kewajiban + ekuitas</Badge>
              ) : (
                <Badge tone="red">Tidak seimbang, selisih {formatRp(r.totals.difference)}</Badge>
              )}
              {choice.locationId === null && <span className="text-xs text-stone-500">Semua lokasi, termasuk jurnal kantor pusat.</span>}
            </div>
            <div className="grid gap-5 lg:grid-cols-2">
              {section('Aset', r.assets, r.totals.assets)}
              <div className="space-y-5">
                {section('Kewajiban', r.liabilities, r.totals.liabilities)}
                {section('Ekuitas', r.equity, r.totals.equity)}
                <Card>
                  <div className="flex justify-between text-sm font-semibold">
                    <span>Total kewajiban dan ekuitas</span>
                    <span className="num">{formatRp(r.totals.liabilities_and_equity)}</span>
                  </div>
                </Card>
              </div>
            </div>
          </>
        )}
      </QueryState>
    </>
  );
}

/** Buku Besar: one account's entries with the running balance. */
export function LedgerPage() {
  const choice = useLocationChoice('accounting.view', { allowAll: true });
  const accounts = useAccounts();
  const [accountId, setAccountId] = useState('');
  const [from, setFrom] = useState(firstOfMonth());
  const [to, setTo] = useState(today());
  const [selected, setSelected] = useState<string | null>(null);
  const ledger = useQuery({
    queryKey: ['ledger', accountId, choice.locationId, from, to],
    queryFn: () => api<Ledger>('/accounting/ledger', { query: { account_id: accountId, location_id: choice.locationId, from, to } }),
    enabled: accountId !== '',
  });
  const l = ledger.data;

  const exportCsv = () => {
    if (!l) return;
    downloadCsv(`buku-besar-${l.account.code}-${from}-${to}`, ['Tanggal', 'Nomor', 'Lokasi', 'Sumber', 'Keterangan', 'Debit', 'Kredit', 'Saldo'], [
      [from, '', '', '', 'Saldo awal', '', '', l.opening],
      ...l.entries.map((e) => [e.date, e.number, e.location_code ?? 'Pusat', SOURCE_TYPES[e.source_type] ?? e.source_type, e.line_memo || e.memo || '', e.debit, e.credit, e.balance]),
      [to, '', '', '', 'Saldo akhir', '', '', l.closing],
    ]);
  };

  return (
    <>
      <PageHeader
        title="Buku Besar"
        description="Semua transaksi satu akun dengan saldo berjalan. Klik baris untuk melihat jurnalnya."
        actions={<Button icon={<Download className="size-4" />} disabled={!l} onClick={exportCsv}>CSV</Button>}
      />
      <Toolbar>
        <Field label="Akun" className="w-72">
          <Select value={accountId} onChange={(e) => setAccountId(e.target.value)}>
            <option value="">Pilih akun…</option>
            {accounts.data?.filter((a) => a.is_postable).map((a) => <option key={a.id} value={a.id}>{a.code} {a.name}</option>)}
          </Select>
        </Field>
        <LocationSelect choice={choice} />
        <Field label="Dari" className="w-40"><Input type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></Field>
        <Field label="Sampai" className="w-40"><Input type="date" value={to} onChange={(e) => setTo(e.target.value)} /></Field>
      </Toolbar>
      {accountId === '' ? (
        <p className="text-sm text-stone-500">Pilih akun untuk melihat buku besarnya.</p>
      ) : (
        <QueryState query={ledger}>
          {l && (
            <>
              {l.truncated && (
                <p className="mb-3 rounded-lg bg-amber-50 px-3 py-2 text-sm text-amber-800">
                  Lebih dari 5.000 baris: hanya 5.000 pertama yang ditampilkan. Persempit rentang tanggal; saldo akhir tetap benar.
                </p>
              )}
              <DataTable
                rows={l.entries}
                rowKey={(e) => `${e.entry_id}-${e.debit}-${e.credit}-${e.balance}`}
                onRowClick={(e) => setSelected(e.entry_id)}
                empty="Tidak ada transaksi pada rentang ini"
                columns={[
                  { header: 'Tanggal', cell: (e) => formatDate(e.date) },
                  { header: 'Nomor', cell: (e) => <span className="font-mono text-xs">{e.number}</span> },
                  { header: 'Lokasi', cell: (e) => e.location_code ?? 'Pusat' },
                  { header: 'Keterangan', wrap: true, cell: (e) => <span className="text-stone-600">{e.line_memo || e.memo}</span> },
                  { header: 'Debit', align: 'right', cell: (e) => (e.debit ? formatRp(e.debit) : '') },
                  { header: 'Kredit', align: 'right', cell: (e) => (e.credit ? formatRp(e.credit) : '') },
                  { header: 'Saldo', align: 'right', cell: (e) => <span className={e.balance < 0 ? 'text-red-600' : ''}>{formatRp(e.balance)}</span> },
                ]}
              />
              <dl className="mt-4 grid max-w-sm grid-cols-2 gap-y-1 text-sm">
                <dt className="text-stone-500">Saldo awal ({formatDate(l.from)})</dt>
                <dd className="num text-right">{formatRp(l.opening)}</dd>
                <dt className="font-semibold">Saldo akhir ({formatDate(l.to)})</dt>
                <dd className="num text-right font-semibold">{formatRp(l.closing)}</dd>
              </dl>
            </>
          )}
        </QueryState>
      )}
      {selected && <JournalDialog id={selected} onClose={() => setSelected(null)} />}
    </>
  );
}
