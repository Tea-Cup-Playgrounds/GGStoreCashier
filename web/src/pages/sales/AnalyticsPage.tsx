import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { api } from '../../api/client';
import { formatDate, formatNumber, formatRp, toNumber, today } from '../../lib/format';
import { Card, DataTable, Field, Input, PageHeader, QueryState, Select, Stat, Toolbar } from '../../components/ui';

interface Summary {
  today: { revenue: number; transactions: number };
  month: { revenue: number; transactions: number };
  allTime: { revenue: number; transactions: number };
  activeBranchesToday: number;
}

export function AnalyticsPage() {
  const [days, setDays] = useState(30);
  const [date, setDate] = useState(today());
  const summary = useQuery({ queryKey: ['analytics', 'summary'], queryFn: () => api<Summary>('/analytics/summary') });
  const trend = useQuery({
    queryKey: ['analytics', 'trend', days],
    queryFn: () => api<{ data: Array<{ date: string; revenue: string; transactions: number }> }>('/analytics/revenue-trend', { query: { days } }).then((r) => r.data),
  });
  const branches = useQuery({
    queryKey: ['analytics', 'branches', date],
    queryFn: () => api<{ data: Array<{ branch_id: number; branch_name: string; revenue: string; transactions: number }> }>('/analytics/branch-revenue', { query: { date } }).then((r) => r.data),
  });
  const categories = useQuery({
    queryKey: ['analytics', 'categories', days],
    queryFn: () => api<{ data: Array<{ category_id: number | null; category_name: string; total_qty: string; total_revenue: string }> }>('/analytics/category-sales', { query: { days } }).then((r) => r.data),
  });
  const top = useQuery({
    queryKey: ['analytics', 'top', days],
    queryFn: () => api<{ data: Array<{ id: number; name: string; total_qty: string; total_revenue: string; branch_name: string | null }> }>('/analytics/top-products', { query: { days, limit: 10 } }).then((r) => r.data),
  });

  const s = summary.data;
  const points = trend.data ?? [];
  const max = Math.max(1, ...points.map((p) => toNumber(p.revenue)));

  return (
    <>
      <PageHeader title="Analitik" description="Semua lokasi. Pendapatan = total penjualan dikurangi retur, tanpa transaksi yang dibatalkan." />
      <QueryState query={summary}>
        {s && (
          <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
            <Stat label="Hari ini" value={formatRp(s.today.revenue)} hint={`${formatNumber(s.today.transactions)} transaksi`} />
            <Stat label="Bulan ini" value={formatRp(s.month.revenue)} hint={`${formatNumber(s.month.transactions)} transaksi`} />
            <Stat label="Sepanjang waktu" value={formatRp(s.allTime.revenue)} hint={`${formatNumber(s.allTime.transactions)} transaksi`} />
            <Stat label="Lokasi aktif hari ini" value={formatNumber(s.activeBranchesToday)} />
          </div>
        )}
      </QueryState>

      <Toolbar>
        <div className="mt-5" />
        <Field label="Periode" className="w-40">
          <Select value={days} onChange={(e) => setDays(Number(e.target.value))}>
            <option value={7}>7 hari</option>
            <option value={30}>30 hari</option>
            <option value={90}>90 hari</option>
          </Select>
        </Field>
      </Toolbar>

      <Card title={`Pendapatan harian (${days} hari)`}>
        <QueryState query={trend}>
          {points.length === 0 ? (
            <p className="py-8 text-center text-sm text-stone-500">Belum ada penjualan pada periode ini</p>
          ) : (
            <div className="flex h-48 items-end gap-1" role="img" aria-label="Grafik pendapatan harian">
              {points.map((p) => {
                const v = toNumber(p.revenue);
                return (
                  <div key={p.date} className="group relative flex h-full flex-1 items-end">
                    <div className="w-full rounded-t bg-brand-500 transition-colors group-hover:bg-brand-600" style={{ height: `${Math.max(2, (v / max) * 100)}%` }} />
                    <div className="pointer-events-none absolute bottom-full left-1/2 z-10 mb-1 hidden -translate-x-1/2 rounded bg-ink-800 px-2 py-1 text-xs whitespace-nowrap text-white group-hover:block">
                      {formatDate(p.date)}: {formatRp(v)} · {p.transactions} trx
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </QueryState>
      </Card>

      <div className="mt-5 grid gap-5 lg:grid-cols-2">
        <Card title="Pendapatan per cabang" actions={<Input type="date" className="h-8 w-40" value={date} onChange={(e) => setDate(e.target.value)} />}>
          <QueryState query={branches}>
            <DataTable
              rows={branches.data ?? []}
              rowKey={(b) => b.branch_id}
              columns={[
                { header: 'Cabang', cell: (b) => b.branch_name },
                { header: 'Transaksi', align: 'right', cell: (b) => b.transactions },
                { header: 'Pendapatan', align: 'right', cell: (b) => formatRp(b.revenue) },
              ]}
            />
          </QueryState>
        </Card>
        <Card title={`Penjualan per kategori (${days} hari)`}>
          <QueryState query={categories}>
            <DataTable
              rows={categories.data ?? []}
              rowKey={(c) => c.category_id ?? 0}
              columns={[
                { header: 'Kategori', cell: (c) => c.category_name },
                { header: 'Qty', align: 'right', cell: (c) => formatNumber(c.total_qty) },
                { header: 'Pendapatan', align: 'right', cell: (c) => formatRp(c.total_revenue) },
              ]}
            />
          </QueryState>
        </Card>
      </div>

      <Card title={`Produk terlaris (${days} hari)`} className="mt-5">
        <QueryState query={top}>
          <DataTable
            rows={top.data ?? []}
            rowKey={(p) => `${p.id}-${p.branch_name}`}
            columns={[
              { header: 'Produk', cell: (p) => p.name },
              { header: 'Cabang', cell: (p) => p.branch_name ?? '—' },
              { header: 'Qty', align: 'right', cell: (p) => formatNumber(p.total_qty) },
              { header: 'Pendapatan', align: 'right', cell: (p) => formatRp(p.total_revenue) },
            ]}
          />
        </QueryState>
      </Card>
    </>
  );
}
