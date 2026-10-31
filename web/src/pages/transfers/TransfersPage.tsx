import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useNavigate } from 'react-router';
import { Plus } from 'lucide-react';
import { api } from '../../api/client';
import type { TransferStatus, TransferSummary } from '../../api/types';
import { useAuth } from '../../auth/AuthContext';
import { LocationSelect, useLocationChoice } from '../../lib/locations';
import { formatDateTime } from '../../lib/format';
import { Badge, Button, DataTable, Field, PageHeader, QueryState, Select, Toolbar, type Tone } from '../../components/ui';

export const TRANSFER_STATUS: Record<TransferStatus, [string, Tone]> = {
  draft: ['Draf', 'gray'],
  sent: ['Dikirim', 'blue'],
  partially_received: ['Diterima sebagian', 'amber'],
  received: ['Diterima', 'green'],
  cancelled: ['Dibatalkan', 'red'],
};

export function TransfersPage() {
  const { access } = useAuth();
  const navigate = useNavigate();
  const choice = useLocationChoice('stock.view', { allowAll: true });
  const [direction, setDirection] = useState('');
  const [status, setStatus] = useState('');

  const transfers = useQuery({
    queryKey: ['transfers', choice.locationId, direction, status],
    queryFn: () =>
      api<{ transfers: TransferSummary[] }>('/transfers', {
        query: { location_id: choice.locationId, direction: choice.locationId ? direction : undefined, status },
      }).then((r) => r.transfers),
  });

  return (
    <>
      <PageHeader
        title="Transfer Stok"
        description="Draf → dikirim (stok keluar dari asal, dalam pengiriman) → diterima. Yang tidak sampai diselesaikan oleh lokasi asal."
        actions={access.can('transfers.create') && <Button variant="primary" icon={<Plus className="size-4" />} onClick={() => navigate('/transfers/new')}>Transfer baru</Button>}
      />
      <Toolbar>
        <LocationSelect choice={choice} />
        {choice.locationId !== null && (
          <Field label="Arah" className="w-36">
            <Select value={direction} onChange={(e) => setDirection(e.target.value)}>
              <option value="">Masuk & keluar</option>
              <option value="in">Masuk</option>
              <option value="out">Keluar</option>
            </Select>
          </Field>
        )}
        <Field label="Status" className="w-44">
          <Select value={status} onChange={(e) => setStatus(e.target.value)}>
            <option value="">Semua</option>
            <option value="draft">Draf</option>
            <option value="sent,partially_received">Perlu tindakan</option>
            <option value="received">Diterima</option>
            <option value="cancelled">Dibatalkan</option>
          </Select>
        </Field>
      </Toolbar>
      <QueryState query={transfers}>
        <DataTable
          rows={transfers.data ?? []}
          rowKey={(t) => t.id}
          onRowClick={(t) => navigate(`/transfers/${t.id}`)}
          empty="Belum ada transfer"
          columns={[
            { header: 'Nomor', cell: (t) => <span className="font-mono text-xs">{t.number}</span> },
            { header: 'Dari → Ke', cell: (t) => `${t.from_code} → ${t.to_code}` },
            { header: 'Qty', align: 'right', cell: (t) => t.qty_total },
            { header: 'Status', cell: (t) => <Badge tone={TRANSFER_STATUS[t.status][1]}>{TRANSFER_STATUS[t.status][0]}</Badge> },
            { header: 'Dibuat', cell: (t) => formatDateTime(t.created_at) },
            { header: 'Dikirim', cell: (t) => formatDateTime(t.sent_at) },
            { header: 'Catatan', cell: (t) => <span className="text-stone-600">{t.note ?? ''}</span> },
          ]}
        />
      </QueryState>
    </>
  );
}
