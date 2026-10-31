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

  const sales = useQuery({
    queryKey: ['sales', choice.locationId, from, to, status, search],
    queryFn: () => api<{ sales: SaleSummary[] }>('/sales', { query: { location_id: choice.locationId, from, to, status, search } }).then((r) => r.sales),
  });
  const rows = sales.data ?? [];
  const net = rows.filter((s) => s.status !== 'voided').reduce((sum, s) => sum + toNumber(s.grand_total) - toNumber(s.refunded_total), 0);

  return (
    <>
      <PageHeader title="Penjualan" description="Maksimal 200 transaksi terbaru sesuai filter." />
      <Toolbar>
        <LocationSelect choice={choice} />
        <Field label="Dari" className="w-40"><Input type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></Field>
        <Field label="Sampai" className="w-40"><Input type="date" value={to} onChange={(e) => setTo(e.target.value)} /></Field>
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
            { header: 'Status', cell: (s) => <Badge tone={SALE_STATUS[s.status][1]}>{SALE_STATUS[s.status][0]}</Badge> },
          ]}
        />
      </QueryState>
    </>
  );
}
