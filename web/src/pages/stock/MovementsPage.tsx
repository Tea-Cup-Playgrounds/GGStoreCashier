import { useInfiniteQuery } from '@tanstack/react-query';
import { api } from '../../api/client';
import type { Movement } from '../../api/types';
import { LocationSelect, useLocationChoice } from '../../lib/locations';
import { formatDateTime, formatRp } from '../../lib/format';
import { Button, DataTable, PageHeader, QueryState, Toolbar } from '../../components/ui';

const REASONS: Record<string, string> = {
  purchase: 'Pembelian',
  purchase_return: 'Retur pembelian',
  sale: 'Penjualan',
  sale_return: 'Retur penjualan',
  transfer_out: 'Transfer keluar',
  transfer_in: 'Transfer masuk',
  adjustment: 'Penyesuaian',
  opname: 'Stok opname',
  write_off: 'Penghapusan',
  service_part: 'Suku cadang servis',
  trade_in: 'Tukar tambah',
};

const PAGE = 100;

export function MovementsPage() {
  const choice = useLocationChoice('stock.view');
  const movements = useInfiniteQuery({
    queryKey: ['movements', choice.locationId],
    queryFn: ({ pageParam }) =>
      api<{ movements: Movement[] }>('/stock/movements', { query: { location_id: choice.locationId, limit: PAGE, before: pageParam } }).then((r) => r.movements),
    initialPageParam: undefined as string | undefined,
    getNextPageParam: (last) => (last.length < PAGE ? undefined : last[last.length - 1].created_at),
    enabled: choice.locationId !== null,
  });
  const rows = movements.data?.pages.flat() ?? [];
  const showCost = rows.some((m) => m.unit_cost !== undefined);

  return (
    <>
      <PageHeader title="Riwayat Stok" description="Setiap perubahan stok tercatat di sini; stok di lokasi selalu sama dengan jumlah riwayatnya." />
      <Toolbar>
        <LocationSelect choice={choice} />
      </Toolbar>
      <QueryState query={movements}>
        <DataTable
          rows={rows}
          rowKey={(m) => m.id}
          empty="Belum ada riwayat"
          columns={[
            { header: 'Waktu', cell: (m) => formatDateTime(m.created_at) },
            { header: 'Produk', cell: (m) => <div><div>{m.name}</div>{(m.imei1 || m.serial_number) && <div className="font-mono text-xs text-stone-500">{m.imei1 ?? m.serial_number}</div>}</div> },
            { header: 'Jenis', cell: (m) => REASONS[m.reason] ?? m.reason },
            { header: 'Jumlah', align: 'right', cell: (m) => <span className={m.qty_change < 0 ? 'text-red-600' : 'text-green-700'}>{m.qty_change > 0 ? `+${m.qty_change}` : m.qty_change}</span> },
            ...(showCost ? [{ header: 'HPP/unit', align: 'right' as const, cell: (m: Movement) => formatRp(m.unit_cost) }] : []),
            { header: 'Oleh', cell: (m) => m.user_name ?? '—' },
            { header: 'Catatan', cell: (m) => <span className="text-stone-600">{m.note ?? ''}</span> },
          ]}
        />
        {movements.hasNextPage && (
          <div className="mt-3 flex justify-center">
            <Button loading={movements.isFetchingNextPage} onClick={() => movements.fetchNextPage()}>
              Muat lebih banyak
            </Button>
          </div>
        )}
      </QueryState>
    </>
  );
}
