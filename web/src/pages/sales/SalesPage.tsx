import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useNavigate } from 'react-router';
import { api } from '../../api/client';
import type { SaleStatus, SaleSummary } from '../../api/types';
import { useAuth } from '../../auth/AuthContext';
import { LocationSelect, useLocationChoice } from '../../lib/locations';
import { firstOfMonth, formatDateTime, formatRp, toNumber, today } from '../../lib/format';
import { Badge, DataTable, Field, Input, PageHeader, QueryState, Select, Toolbar, type Tone } from '../../components/ui';

export const SALE_STATUS: Record<SaleStatus, [string, Tone]> = {
  completed: ['Selesai', 'green'],
  partially_returned: ['Retur sebagian', 'amber'],
  returned: ['Diretur', 'amber'],
  voided: ['Dibatalkan', 'red'],
};

export function SalesPage() {
  const navigate = useNavigate();
  const { access } = useAuth();
  const choice = useLocationChoice(access.can('reports.view_location') ? 'reports.view_location' : 'sales.create', { allowAll: true });
  const [from, setFrom] = useState(firstOfMonth());
  const [to, setTo] = useState(today());
  const [status, setStatus] = useState('');
  const [search, setSearch] = useState('');
  const [sync, setSync] = useState('');
  // Offline sales waiting for a check are shown whatever their date.
  const dates = sync === 'issues' ? {} : { from, to };

  const sales = useQuery({
    queryKey: ['sales', choice.locationId, from, to, status, search, sync],
    queryFn: () =>
      api<{ sales: SaleSummary[] }>('/sales', { query: { location_id: choice.locationId, ...dates, status, search, sync } }).then((r) => r.sales),
  });
  const toReview = useQuery({
    queryKey: ['sales', choice.locationId, 'sync-issues'],
    queryFn: () => api<{ sales: SaleSummary[] }>('/sales', { query: { location_id: choice.locationId, sync: 'issues' } }).then((r) => r.sales.length),
  });
  const rows = sales.data ?? [];
  const net = rows.filter((s) => s.status !== 'voided').reduce((sum, s) => sum + toNumber(s.grand_total) - toNumber(s.refunded_total), 0);

  return (
    <>
      <PageHeader title="Penjualan" description="Maksimal 200 transaksi terbaru sesuai filter." />
      {!!toReview.data && sync !== 'issues' && (
        <button
          type="button"
          onClick={() => setSync('issues')}
          className="mb-4 w-full rounded-lg bg-amber-50 px-3 py-2 text-left text-sm text-amber-800 hover:bg-amber-100"
        >
          <b>{toReview.data} penjualan offline</b> masuk dengan selisih (stok minus, harga berubah, shift sudah ditutup, …) dan belum dicek. Lihat →
        </button>
      )}
      <Toolbar>
        <LocationSelect choice={choice} />
        <Field label="Dari" className="w-40"><Input type="date" value={from} disabled={sync === 'issues'} onChange={(e) => setFrom(e.target.value)} /></Field>
        <Field label="Sampai" className="w-40"><Input type="date" value={to} disabled={sync === 'issues'} onChange={(e) => setTo(e.target.value)} /></Field>
        <Field label="Offline" className="w-44">
          <Select value={sync} onChange={(e) => setSync(e.target.value)}>
            <option value="">Semua</option>
            <option value="offline">Penjualan offline</option>
            <option value="issues">Offline, perlu dicek</option>
          </Select>
        </Field>
        <Field label="Status" className="w-40">
          <Select value={status} onChange={(e) => setStatus(e.target.value)}>
            <option value="">Semua</option>
            {Object.entries(SALE_STATUS).map(([k, [label]]) => <option key={k} value={k}>{label}</option>)}
          </Select>
        </Field>
        <Field label="Cari" className="w-56"><Input placeholder="Nomor, nama/HP pelanggan" value={search} onChange={(e) => setSearch(e.target.value)} /></Field>
      </Toolbar>
      <QueryState query={sales}>
        <div className="mb-3 text-sm text-stone-600">
          {rows.length} transaksi · penjualan bersih <b className="num">{formatRp(net)}</b>
        </div>
        <DataTable
          rows={rows}
          rowKey={(s) => s.id}
          onRowClick={(s) => navigate(`/sales/${s.id}`)}
          empty="Tidak ada penjualan"
          columns={[
            { header: 'Nomor', cell: (s) => <span className="font-mono text-xs">{s.number}</span> },
            { header: 'Waktu', cell: (s) => formatDateTime(s.occurred_at) },
            { header: 'Lokasi', cell: (s) => s.location_code },
            { header: 'Kasir', cell: (s) => s.cashier_name ?? '—' },
            { header: 'Pelanggan', cell: (s) => s.customer_name ?? '—' },
            { header: 'Bayar', cell: (s) => s.payment_methods ?? '—' },
            { header: 'Total', align: 'right', cell: (s) => <>{formatRp(s.grand_total)}{toNumber(s.refunded_total) > 0 && <div className="text-xs text-red-600">−{formatRp(s.refunded_total)}</div>}</> },
            {
              header: 'Status',
              cell: (s) => (
                <div className="flex flex-wrap gap-1">
                  <Badge tone={SALE_STATUS[s.status][1]}>{SALE_STATUS[s.status][0]}</Badge>
                  {s.is_offline &&
                    (s.sync_issue_count && !s.sync_reviewed ? (
                      <Badge tone="amber">Offline · {s.sync_issue_count} perlu dicek</Badge>
                    ) : (
                      <Badge>Offline</Badge>
                    ))}
                </div>
              ),
            },
          ]}
        />
      </QueryState>
    </>
  );
}
