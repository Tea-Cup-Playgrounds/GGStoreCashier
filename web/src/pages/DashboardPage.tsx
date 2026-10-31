import { useQuery } from '@tanstack/react-query';
import { useNavigate } from 'react-router';
import { api } from '../api/client';
import { useAuth } from '../auth/AuthContext';
import { LocationSelect, useLocationChoice } from '../lib/locations';
import { formatDateTime, formatNumber, formatRp } from '../lib/format';
import { Badge, Card, DataTable, PageHeader, QueryState, Stat } from '../components/ui';

interface DashboardData {
  stats: {
    todayRevenue: number;
    todayTransactions: number;
    monthlyTransactions: number;
    monthlyRevenue: number;
    lowStockCount: number;
    outOfStockCount: number;
  };
  recentTransactions: Array<{
    id: string;
    number: string;
    final_amount: string;
    status: string;
    created_at: string;
    user_name: string | null;
    branch_name: string | null;
    payment_method: string | null;
    item_count: number;
  }>;
}

export function DashboardPage() {
  const { user, access } = useAuth();
  const navigate = useNavigate();
  // The dashboard covers locations where the user sells or reads reports; owners see everything.
  const choice = useLocationChoice(access.can('reports.view_location') ? 'reports.view_location' : 'sales.create', { allowAll: true });
  const dashboard = useQuery({
    queryKey: ['dashboard', choice.locationId],
    queryFn: () => api<DashboardData>('/dashboard', { query: { location_id: choice.locationId } }),
  });
  const s = dashboard.data?.stats;

  return (
    <>
      <PageHeader title={`Halo, ${user?.name ?? ''}`} description="Ringkasan penjualan dan stok." actions={<LocationSelect choice={choice} />} />
      <QueryState query={dashboard}>
        {s && (
          <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
            <Stat label="Pendapatan hari ini" value={formatRp(s.todayRevenue)} hint={`${formatNumber(s.todayTransactions)} transaksi`} />
            <Stat label="Pendapatan bulan ini" value={formatRp(s.monthlyRevenue)} hint={`${formatNumber(s.monthlyTransactions)} transaksi`} />
            <Stat label="Stok menipis" value={formatNumber(s.lowStockCount)} hint="Varian dengan stok 1–5 di cabang" />
            <Stat label="Stok habis" value={formatNumber(s.outOfStockCount)} hint="Varian dengan stok 0 di cabang" />
          </div>
        )}
        <Card title="Penjualan terbaru" className="mt-5">
          <DataTable
            rows={dashboard.data?.recentTransactions ?? []}
            rowKey={(t) => t.id}
            onRowClick={(t) => navigate(`/sales/${t.id}`)}
            empty="Belum ada penjualan"
            columns={[
              { header: 'Nomor', cell: (t) => <span className="font-mono text-xs">{t.number}</span> },
              { header: 'Waktu', cell: (t) => formatDateTime(t.created_at) },
              { header: 'Lokasi', cell: (t) => t.branch_name ?? '—' },
              { header: 'Kasir', cell: (t) => t.user_name ?? '—' },
              { header: 'Bayar', cell: (t) => t.payment_method ?? '—' },
              { header: 'Item', align: 'right', cell: (t) => formatNumber(t.item_count) },
              { header: 'Total', align: 'right', cell: (t) => formatRp(t.final_amount) },
              { header: '', cell: (t) => t.status === 'voided' && <Badge tone="red">Batal</Badge> },
            ]}
          />
        </Card>
      </QueryState>
    </>
  );
}
