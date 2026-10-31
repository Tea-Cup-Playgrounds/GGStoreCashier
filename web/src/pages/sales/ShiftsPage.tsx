import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { api } from '../../api/client';
import type { CashSession } from '../../api/types';
import { LocationSelect, useLocationChoice } from '../../lib/locations';
import { formatDateTime, formatRp, toNumber } from '../../lib/format';
import { Badge, DataTable, Modal, PageHeader, QueryState, Spinner, Toolbar } from '../../components/ui';

export function ShiftsPage() {
  const choice = useLocationChoice('sales.create');
  const [selected, setSelected] = useState<string | null>(null);
  const sessions = useQuery({
    queryKey: ['cash-sessions', choice.locationId],
    queryFn: () => api<{ sessions: CashSession[] }>('/cash-sessions', { query: { location_id: choice.locationId } }).then((r) => r.sessions),
    enabled: choice.locationId !== null,
  });

  const diff = (s: CashSession) => {
    if (s.difference === null) return '—';
    const d = toNumber(s.difference);
    return <span className={d < 0 ? 'text-red-600' : d > 0 ? 'text-green-700' : ''}>{d > 0 ? '+' : ''}{formatRp(d)}</span>;
  };

  return (
    <>
      <PageHeader title="Shift Kasir" description="Shift dibuka dan ditutup dari aplikasi kasir. Selisih kas dijurnal ke akun Selisih Kas saat ditutup." />
      <Toolbar>
        <LocationSelect choice={choice} />
      </Toolbar>
      <QueryState query={sessions}>
        <DataTable
          rows={sessions.data ?? []}
          rowKey={(s) => s.id}
          onRowClick={(s) => setSelected(s.id)}
          empty="Belum ada shift"
          columns={[
            { header: 'Kasir', cell: (s) => s.opened_by_name ?? '—' },
            { header: 'Buka', cell: (s) => formatDateTime(s.opened_at) },
            { header: 'Tutup', cell: (s) => formatDateTime(s.closed_at) },
            { header: 'Kas awal', align: 'right', cell: (s) => formatRp(s.opening_cash) },
            { header: 'Kas seharusnya', align: 'right', cell: (s) => (s.expected_cash === null ? '—' : formatRp(s.expected_cash)) },
            { header: 'Kas dihitung', align: 'right', cell: (s) => (s.counted_cash === null ? '—' : formatRp(s.counted_cash)) },
            { header: 'Selisih', align: 'right', cell: diff },
            { header: '', cell: (s) => (s.status === 'open' ? <Badge tone="amber">Buka</Badge> : <Badge>Tutup</Badge>) },
          ]}
        />
      </QueryState>
      {selected && <ShiftDialog id={selected} onClose={() => setSelected(null)} />}
    </>
  );
}

function ShiftDialog({ id, onClose }: { id: string; onClose: () => void }) {
  const session = useQuery({ queryKey: ['cash-session', id], queryFn: () => api<{ session: CashSession }>(`/cash-sessions/${id}`).then((r) => r.session) });
  const s = session.data;
  return (
    <Modal open onClose={onClose} title="Ringkasan shift">
      {!s ? (
        <div className="flex justify-center py-6"><Spinner /></div>
      ) : (
        <div className="space-y-4 text-sm">
          <div className="text-stone-600">
            {s.opened_by_name} · {s.location_name} · {formatDateTime(s.opened_at)} – {s.closed_at ? formatDateTime(s.closed_at) : 'masih buka'}
          </div>
          <dl className="grid grid-cols-2 gap-2">
            <dt className="text-stone-500">Transaksi</dt><dd className="num text-right">{s.summary?.sales_count ?? 0}</dd>
            <dt className="text-stone-500">Total penjualan</dt><dd className="num text-right">{formatRp(s.summary?.sales_total)}</dd>
            <dt className="text-stone-500">Kas awal</dt><dd className="num text-right">{formatRp(s.opening_cash)}</dd>
            <dt className="text-stone-500">Kembalian diberikan</dt><dd className="num text-right">{formatRp(s.summary?.change_total)}</dd>
            <dt className="text-stone-500">Refund tunai</dt><dd className="num text-right">{formatRp(s.summary?.cash_refunds)}</dd>
            <dt className="font-medium">Kas seharusnya</dt><dd className="num text-right font-medium">{formatRp(s.summary?.expected_cash)}</dd>
            {s.counted_cash !== null && (<><dt className="text-stone-500">Kas dihitung</dt><dd className="num text-right">{formatRp(s.counted_cash)}</dd></>)}
          </dl>
          <div>
            <div className="mb-1 font-medium">Per metode pembayaran</div>
            <dl className="grid grid-cols-2 gap-1">
              {s.summary?.by_method.map((m) => (
                <div key={m.id} className="contents">
                  <dt className="text-stone-500">{m.name} ({m.sales})</dt>
                  <dd className="num text-right">{formatRp(m.amount)}</dd>
                </div>
              ))}
            </dl>
          </div>
          {s.note && <p className="text-stone-600">Catatan: {s.note}</p>}
        </div>
      )}
    </Modal>
  );
}
