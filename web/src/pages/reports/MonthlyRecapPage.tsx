import { useState, type ReactNode } from 'react';
import { useQuery } from '@tanstack/react-query';
import { ChevronLeft, ChevronRight, Download } from 'lucide-react';
import { api } from '../../api/client';
import type { MonthlyRecap, RecapLine } from '../../api/types';
import { useAuth } from '../../auth/AuthContext';
import { LocationSelect, locationName, useLocationChoice } from '../../lib/locations';
import { downloadCsv } from '../../lib/csv';
import { formatNumber, formatRp, today } from '../../lib/format';
import { Button, Card, DataTable, Field, Input, PageHeader, QueryState, Toolbar, cx } from '../../components/ui';

/** Who may open the recap: branch managers (own branch), owner and accountant. */
export const RECAP_PERMISSIONS = ['reports.view_location', 'reports.view_all', 'accounting.view'];

const MONTHS = ['Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];
const monthLabel = (ym: string) => {
  const [y, m] = ym.split('-').map(Number);
  return `${MONTHS[m - 1]} ${y}`;
};
const shiftMonth = (ym: string, by: number) => {
  const [y, m] = ym.split('-').map(Number);
  const d = new Date(y, m - 1 + by, 1);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
};

type RowKind = 'plain' | 'minus' | 'sub' | 'result' | 'note';
interface Row {
  label: ReactNode;
  value: number | null;
  kind?: RowKind;
  color?: string;
  hint?: string;
}

/**
 * The spreadsheet look: month header, black "Keterangan | Angka" bar, one figure per row.
 * Deductions carry a minus sign, sub-rows are indented, results are highlighted.
 */
function SheetTable({ month, rows, caption }: { month: string; rows: Row[]; caption: string }) {
  return (
    // flex-1: side by side, both frames fill their section so the two tables end at the same line.
    <div className="flex flex-1 flex-col overflow-hidden rounded-lg border-2 border-ink-900 bg-white">
      {/* flex-1 on the table too: the shorter table spreads the extra height over its rows instead of leaving a gap. */}
      <table className="w-full flex-1 text-sm">
        <caption className="sr-only">{caption}</caption>
        <thead>
          <tr className="border-b-2 border-ink-900">
            <th scope="col" className="px-3 py-2 text-left font-extrabold">Bulan</th>
            <th scope="col" className="px-3 py-2 text-right font-extrabold">{monthLabel(month)}</th>
          </tr>
          <tr className="bg-ink-900 text-xs tracking-wide text-white uppercase">
            <th scope="col" className="px-3 py-2.5 text-left font-bold">Keterangan</th>
            <th scope="col" className="px-3 py-2.5 text-right font-bold">Angka</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-stone-200">
          {rows.map((r, i) => {
            const kind = r.kind ?? 'plain';
            const negative = r.value != null && r.value < 0;
            return (
              <tr key={i} className={cx(kind === 'result' && 'bg-brand-500', kind === 'sub' && 'bg-stone-50')}>
                <th scope="row" className={cx('px-3 py-2 text-left align-top', kind === 'sub' ? 'pl-9 font-medium text-stone-600' : 'font-bold', kind === 'note' && 'font-medium text-stone-600 italic')}>
                  <span className="flex items-center gap-2">
                    {r.color && <span aria-hidden className="size-3 shrink-0 rounded-sm border border-ink-900/30" style={{ background: r.color }} />}
                    {kind === 'minus' && <span aria-hidden className="w-3 shrink-0 text-center font-extrabold">−</span>}
                    <span>{r.label}</span>
                  </span>
                  {r.hint && <span className="mt-0.5 block text-xs font-medium text-stone-500">{r.hint}</span>}
                </th>
                <td
                  className={cx(
                    'num px-3 py-2 text-right align-top whitespace-nowrap',
                    kind === 'result' ? 'text-base font-extrabold' : kind === 'sub' ? 'font-medium text-stone-600' : 'font-bold',
                    negative && kind !== 'result' && 'text-red-700',
                  )}
                >
                  {r.value == null ? '—' : formatRp(r.value)}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

/**
 * How the three totals on this page relate, so they do not look contradictory:
 * omset sistem → (− komplimen − refund) → total per kategori → (− pengeluaran) → omset bersih.
 * Discounts and refunds belong to items, so the category figures already exclude them; store
 * spending belongs to no category, so only omset bersih takes it off.
 */
function OmsetSteps({ omset, categoryTotal }: { omset: MonthlyRecap['omset']; categoryTotal: number }) {
  const step = (label: string, value: number, strong = false) => (
    <div className={cx('min-w-0 flex-1 rounded-md border-2 px-3 py-2', strong ? 'border-ink-900 bg-brand-500' : 'border-stone-300 bg-white')}>
      <div className="text-xs font-bold text-ink-900">{label}</div>
      <div className="num text-sm font-extrabold whitespace-nowrap">{formatRp(value)}</div>
    </div>
  );
  const arrow = (text: string) => (
    <div className="flex shrink-0 flex-col items-center justify-center px-1 text-center text-xs font-bold text-stone-600">
      <ChevronRight aria-hidden className="size-4 max-md:rotate-90" />
      <span className="whitespace-nowrap">{text}</span>
    </div>
  );
  return (
    <div className="mt-4">
      <h3 className="mb-2 text-sm font-extrabold">Kenapa angkanya berbeda?</h3>
      <div className="flex flex-col gap-2 md:flex-row md:items-stretch">
        {step('Total omset sistem', omset.gross)}
        {arrow(`− komplimen ${formatRp(omset.discounts)} − refund ${formatRp(omset.refund)}`)}
        {step('Total per kategori', categoryTotal)}
        {arrow(`− pengeluaran ${formatRp(omset.expenses)}`)}
        {step('Omset bersih', omset.net, true)}
      </div>
    </div>
  );
}

const lineRows = (lines: RecapLine[]): Row[] =>
  lines.map((l) => ({ label: `${l.name} (${l.count}×)`, value: l.amount, kind: 'sub' as const }));

/** Rekap Bulanan: the monthly recap the shop kept in a spreadsheet, built from the system's records. */
export function MonthlyRecapPage() {
  const { access } = useAuth();
  const choice = useLocationChoice(RECAP_PERMISSIONS, { allowAll: true });
  const [month, setMonth] = useState(today().slice(0, 7));
  const thisMonth = today().slice(0, 7);
  const report = useQuery({
    queryKey: ['monthly-recap', choice.locationId, month],
    queryFn: () => api<MonthlyRecap>('/reports/monthly-recap', { query: { month, location_id: choice.locationId } }),
    enabled: !choice.isPending,
  });
  const r = report.data;
  const where = locationName(choice.options, choice.locationId);

  const omsetRows: Row[] = r
    ? [
        { label: 'Total omset sistem', value: r.omset.gross, hint: `${formatNumber(r.omset.transactions)} transaksi, sebelum diskon` },
        { label: 'Total cash', value: r.omset.cash, kind: 'sub', hint: 'Tunai diterima, dikurangi kembalian' },
        { label: 'Total QRIS + debit', value: r.omset.qris_debit, kind: 'sub' },
        { label: 'Total transfer', value: r.omset.transfer, kind: 'sub' },
        { label: 'E-wallet / online', value: r.omset.ewallet, kind: 'sub' },
        { label: 'Pengeluaran', value: r.omset.expenses, kind: 'minus', hint: 'Biaya yang dibayar dari kas toko' },
        ...lineRows(r.omset.expense_lines),
        { label: 'Refund', value: r.omset.refund, kind: 'minus', hint: 'Uang dikembalikan ke pelanggan (retur)' },
        { label: 'Komplimen', value: r.omset.discounts, kind: 'minus', hint: 'Diskon dan voucher' },
        { label: 'Omset bersih', value: r.omset.net, kind: 'result', hint: 'Omset sistem − pengeluaran − refund − komplimen' },
      ]
    : [];

  const a = r?.allocation;
  const allocationRows: Row[] = a
    ? [
        { label: 'Omset bersih', value: a.net_revenue },
        { label: 'Operasional', value: a.operational, hint: 'Biaya yang dibayar dari bank, per kategori' },
        ...lineRows(a.operational_lines),
        { label: 'Pembelian stok', value: a.stock_purchases },
        { label: 'Barang (dibayar saat diterima)', value: a.stock_goods, kind: 'sub' },
        { label: 'Top up deposit pulsa', value: a.stock_pulsa, kind: 'sub' },
        { label: 'Pembayaran hutang', value: a.debt_payments, hint: 'Pelunasan penerimaan barang sebelumnya' },
        { label: 'Aset', value: a.assets, hint: 'Masuk ke akun aset tetap (1-2xxx) lewat jurnal' },
        { label: 'Sisa uang', value: a.remaining, kind: 'result', hint: 'Omset bersih − operasional − pembelian stok − hutang − aset' },
        { label: 'Sisa uang pulsa', value: a.pulsa_balance, hint: 'Saldo deposit pulsa di akhir bulan' },
      ]
    : [];

  const exportCsv = () => {
    if (!r) return;
    const flat = (rows: Row[]) => rows.map((row) => [typeof row.label === 'string' ? row.label : '', row.value ?? '']);
    downloadCsv(`rekap-bulanan-${r.month}`, ['Keterangan', monthLabel(r.month)], [
      ['REKAP OMSET', ''],
      ...flat(omsetRows),
      ...(a ? [['', ''], ['ALOKASI UANG', ''], ...flat(allocationRows)] : []),
      ['', ''],
      ['PER KATEGORI', ''],
      ...r.categories.flatMap((c) => [[`${c.name} — omset`, c.revenue], [`${c.name} — HPP`, c.cost], [`${c.name} — laba kotor`, c.gross_profit]]),
    ]);
  };

  return (
    <>
      <PageHeader
        title="Rekap Bulanan"
        description={
          access.can('accounting.view')
            ? 'Omset, pengeluaran dan ke mana uangnya dipakai dalam satu bulan, dihitung langsung dari transaksi.'
            : 'Omset dan pengeluaran cabang Anda dalam satu bulan, dihitung langsung dari transaksi.'
        }
        actions={<Button icon={<Download className="size-4" />} disabled={!r} onClick={exportCsv}>CSV</Button>}
      />
      <Toolbar>
        <LocationSelect choice={choice} />
        <Field label="Bulan" className="w-auto">
          <div className="flex items-center gap-1">
            <Button variant="ghost" aria-label="Bulan sebelumnya" icon={<ChevronLeft className="size-5" />} onClick={() => setMonth(shiftMonth(month, -1))} />
            <Input
              type="month"
              className="w-44"
              value={month}
              max={thisMonth}
              onChange={(e) => e.target.value && setMonth(e.target.value)}
            />
            <Button
              variant="ghost"
              aria-label="Bulan berikutnya"
              icon={<ChevronRight className="size-5" />}
              disabled={month >= thisMonth}
              onClick={() => setMonth(shiftMonth(month, 1))}
            />
          </div>
        </Field>
      </Toolbar>

      <QueryState query={report}>
        {r && (
          <div className="space-y-5">
            <p className="text-sm font-medium text-stone-600">
              {where} · {monthLabel(r.month)}
              {r.month === thisMonth && ' · sampai hari ini'}
            </p>
            <div className={cx('grid gap-5', a && 'xl:grid-cols-2')}>
              <section aria-labelledby="omset-title" className="flex flex-col">
                <h2 id="omset-title" className="mb-2 text-base font-extrabold">Rekap omset</h2>
                <SheetTable month={r.month} rows={omsetRows} caption="Rekap omset" />
              </section>
              {a && (
                <section aria-labelledby="alokasi-title" className="flex flex-col">
                  <h2 id="alokasi-title" className="mb-2 text-base font-extrabold">Alokasi uang</h2>
                  <SheetTable month={r.month} rows={allocationRows} caption="Alokasi uang" />
                </section>
              )}
            </div>

            <Card title="Per kategori">
              <p className="mb-3 text-sm text-stone-500">
                Pengganti &ldquo;sisa uang&rdquo; per lini (acc, hp, service, pulsa). Omset di sini sudah dikurangi diskon dan refund
                barang kategori itu; laba kotor = omset − harga pokok (HPP).
              </p>
              <DataTable
                rows={r.categories}
                rowKey={(c) => c.id ?? 0}
                empty="Belum ada penjualan bulan ini"
                columns={[
                  { header: 'Kategori', cell: (c) => <span className="font-bold">{c.name}</span> },
                  { header: 'Terjual', align: 'right', cell: (c) => formatNumber(c.qty) },
                  { header: 'Omset (stlh diskon & refund)', align: 'right', cell: (c) => formatRp(c.revenue) },
                  { header: 'HPP', align: 'right', cell: (c) => formatRp(c.cost) },
                  {
                    header: 'Laba kotor',
                    align: 'right',
                    cell: (c) => <span className={cx('font-bold', c.gross_profit < 0 && 'text-red-700')}>{formatRp(c.gross_profit)}</span>,
                  },
                ]}
                footer={
                  r.categories.length > 1 ? (
                    <tr>
                      <td className="px-3 py-2.5">Total</td>
                      <td className="num px-3 py-2.5 text-right">{formatNumber(r.categories.reduce((s, c) => s + c.qty, 0))}</td>
                      <td className="num px-3 py-2.5 text-right">{formatRp(r.categories.reduce((s, c) => s + c.revenue, 0))}</td>
                      <td className="num px-3 py-2.5 text-right">{formatRp(r.categories.reduce((s, c) => s + c.cost, 0))}</td>
                      <td className="num px-3 py-2.5 text-right">{formatRp(r.categories.reduce((s, c) => s + c.gross_profit, 0))}</td>
                    </tr>
                  ) : undefined
                }
              />
              {r.categories.length > 0 && <OmsetSteps omset={r.omset} categoryTotal={r.categories.reduce((s, c) => s + c.revenue, 0)} />}
            </Card>
          </div>
        )}
      </QueryState>
    </>
  );
}
