import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Download } from 'lucide-react';
import { api } from '../../api/client';
import type { AccountType, Balance } from '../../api/types';
import { LocationSelect, useLocationChoice } from '../../lib/locations';
import { downloadCsv } from '../../lib/csv';
import { firstOfMonth, formatRp, today } from '../../lib/format';
import { Button, Card, DataTable, Field, Input, PageHeader, QueryState, Toolbar } from '../../components/ui';

export const TYPE_LABELS: Record<AccountType, string> = { asset: 'Aset', liability: 'Kewajiban', equity: 'Ekuitas', income: 'Pendapatan', expense: 'Beban' };

export function TrialBalancePage() {
  const choice = useLocationChoice('accounting.view', { allowAll: true });
  const [from, setFrom] = useState('');
  const [to, setTo] = useState(today());
  const report = useQuery({
    queryKey: ['trial-balance', choice.locationId, from, to],
    queryFn: () => api<{ accounts: Balance[]; totals: { debit: number; credit: number } }>('/accounting/trial-balance', { query: { location_id: choice.locationId, from, to } }),
  });
  const rows = report.data?.accounts ?? [];
  const totals = report.data?.totals;
  const balanced = totals && Math.abs(totals.debit - totals.credit) < 0.005;

  return (
    <>
      <PageHeader
        title="Neraca Saldo"
        description="Total debit dan kredit per akun. Saldo dihitung sesuai sisi normal akun."
        actions={
          <Button
            icon={<Download className="size-4" />}
            disabled={rows.length === 0}
            onClick={() => downloadCsv(`neraca-saldo-${to}`, ['Kode', 'Akun', 'Tipe', 'Debit', 'Kredit', 'Saldo'], rows.map((r) => [r.code, r.name, TYPE_LABELS[r.type], r.debit, r.credit, r.balance]))}
          >
            CSV
          </Button>
        }
      />
      <Toolbar>
        <LocationSelect choice={choice} />
        <Field label="Dari (opsional)" className="w-40"><Input type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></Field>
        <Field label="Sampai" className="w-40"><Input type="date" value={to} onChange={(e) => setTo(e.target.value)} /></Field>
      </Toolbar>
      <QueryState query={report}>
        <DataTable
          rows={rows}
          rowKey={(r) => r.id}
          empty="Belum ada jurnal pada periode ini"
          columns={[
            { header: 'Kode', cell: (r) => <span className="font-mono text-xs">{r.code}</span> },
            { header: 'Akun', cell: (r) => r.name },
            { header: 'Tipe', cell: (r) => TYPE_LABELS[r.type] },
            { header: 'Debit', align: 'right', cell: (r) => formatRp(r.debit) },
            { header: 'Kredit', align: 'right', cell: (r) => formatRp(r.credit) },
            { header: 'Saldo', align: 'right', cell: (r) => <span className={r.balance < 0 ? 'text-red-600' : ''}>{formatRp(r.balance)}</span> },
          ]}
          footer={
            totals && (
              <tr>
                <td className="px-3 py-2" colSpan={3}>Total {balanced ? '(seimbang)' : '(TIDAK SEIMBANG)'}</td>
                <td className="num px-3 py-2 text-right">{formatRp(totals.debit)}</td>
                <td className="num px-3 py-2 text-right">{formatRp(totals.credit)}</td>
                <td />
              </tr>
            )
          }
        />
      </QueryState>
    </>
  );
}

interface ProfitLoss {
  income: Balance[];
  expense: Balance[];
  totals: { income: number; cost_of_goods: number; gross_profit: number; expense: number; net_profit: number };
}

export function ProfitLossPage() {
  const choice = useLocationChoice('accounting.view', { allowAll: true });
  const [from, setFrom] = useState(firstOfMonth());
  const [to, setTo] = useState(today());
  const report = useQuery({
    queryKey: ['profit-loss', choice.locationId, from, to],
    queryFn: () => api<ProfitLoss>('/accounting/profit-loss', { query: { location_id: choice.locationId, from, to } }),
  });
  const r = report.data;
  const exportCsv = () => {
    if (!r) return;
    downloadCsv(`laba-rugi-${from}-${to}`, ['Bagian', 'Kode', 'Akun', 'Jumlah'], [
      ...r.income.map((a) => ['Pendapatan', a.code, a.name, a.balance]),
      ['', '', 'Total pendapatan', r.totals.income],
      ...r.expense.map((a) => ['Beban', a.code, a.name, a.balance]),
      ['', '', 'Harga pokok penjualan', r.totals.cost_of_goods],
      ['', '', 'Laba kotor', r.totals.gross_profit],
      ['', '', 'Total beban (termasuk HPP)', r.totals.expense],
      ['', '', 'Laba bersih', r.totals.net_profit],
    ]);
  };

  const section = (title: string, rows: Balance[], total: number) => (
    <Card title={title}>
      <table className="w-full text-sm">
        <tbody className="divide-y divide-stone-100">
          {rows.map((a) => (
            <tr key={a.id}>
              <td className="py-1.5 pr-3 font-mono text-xs text-stone-500">{a.code}</td>
              <td className="py-1.5">{a.name}</td>
              <td className="num py-1.5 text-right">{formatRp(a.balance)}</td>
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
      <PageHeader title="Laba Rugi" actions={<Button icon={<Download className="size-4" />} disabled={!r} onClick={exportCsv}>CSV</Button>} />
      <Toolbar>
        <LocationSelect choice={choice} />
        <Field label="Dari" className="w-40"><Input type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></Field>
        <Field label="Sampai" className="w-40"><Input type="date" value={to} onChange={(e) => setTo(e.target.value)} /></Field>
      </Toolbar>
      <QueryState query={report}>
        {r && (
          <div className="space-y-5">
            {section('Pendapatan', r.income, r.totals.income)}
            {section('Beban', r.expense, r.totals.expense)}
            <Card>
              <dl className="grid max-w-md grid-cols-2 gap-y-1.5 text-sm">
                <dt className="text-stone-500">Pendapatan</dt><dd className="num text-right">{formatRp(r.totals.income)}</dd>
                <dt className="text-stone-500">Harga pokok penjualan</dt><dd className="num text-right">{formatRp(r.totals.cost_of_goods)}</dd>
                <dt className="font-medium">Laba kotor</dt><dd className="num text-right font-medium">{formatRp(r.totals.gross_profit)}</dd>
                <dt className="text-stone-500">Beban operasional</dt><dd className="num text-right">{formatRp(r.totals.expense - r.totals.cost_of_goods)}</dd>
                <dt className="text-base font-semibold">Laba bersih</dt>
                <dd className={`num text-right text-base font-semibold ${r.totals.net_profit < 0 ? 'text-red-600' : 'text-green-700'}`}>{formatRp(r.totals.net_profit)}</dd>
              </dl>
            </Card>
          </div>
        )}
      </QueryState>
    </>
  );
}
