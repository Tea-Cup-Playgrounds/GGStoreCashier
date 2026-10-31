import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useNavigate } from 'react-router';
import { Plus } from 'lucide-react';
import { api, errorMessage } from '../../api/client';
import type { Opname, OpnameSummary } from '../../api/types';
import { useAuth } from '../../auth/AuthContext';
import { LocationSelect, useLocationChoice } from '../../lib/locations';
import { useCategories } from '../../lib/catalog';
import { formatDateTime } from '../../lib/format';
import { Badge, Button, DataTable, Field, Input, Modal, PageHeader, QueryState, Select, Toolbar, useToast, type Tone } from '../../components/ui';

export const OPNAME_STATUS: Record<OpnameSummary['status'], [string, Tone]> = {
  counting: ['Sedang dihitung', 'amber'],
  approved: ['Disetujui', 'green'],
  cancelled: ['Dibatalkan', 'red'],
};

export function OpnamesPage() {
  const { access } = useAuth();
  const navigate = useNavigate();
  const choice = useLocationChoice('stock.view', { allowAll: true });
  const [starting, setStarting] = useState(false);
  const opnames = useQuery({
    queryKey: ['opnames', choice.locationId],
    queryFn: () => api<{ opnames: OpnameSummary[] }>('/opnames', { query: { location_id: choice.locationId } }).then((r) => r.opnames),
  });

  return (
    <>
      <PageHeader
        title="Stok Opname"
        description="Saat dimulai, stok sistem dicatat. Selisih (hitungan − catatan) diterapkan saat disetujui, jadi penjualan selama penghitungan tetap aman."
        actions={access.can('stock.opname') && <Button variant="primary" icon={<Plus className="size-4" />} onClick={() => setStarting(true)}>Mulai opname</Button>}
      />
      <Toolbar>
        <LocationSelect choice={choice} />
      </Toolbar>
      <QueryState query={opnames}>
        <DataTable
          rows={opnames.data ?? []}
          rowKey={(o) => o.id}
          onRowClick={(o) => navigate(`/opnames/${o.id}`)}
          empty="Belum ada stok opname"
          columns={[
            { header: 'Nomor', cell: (o) => <span className="font-mono text-xs">{o.number}</span> },
            { header: 'Lokasi', cell: (o) => o.location_name },
            { header: 'Kategori', cell: (o) => o.category_name ?? 'Semua' },
            { header: 'Item', align: 'right', cell: (o) => o.item_count },
            { header: 'Status', cell: (o) => <Badge tone={OPNAME_STATUS[o.status][1]}>{OPNAME_STATUS[o.status][0]}</Badge> },
            { header: 'Mulai', cell: (o) => formatDateTime(o.created_at) },
            { header: 'Disetujui', cell: (o) => formatDateTime(o.approved_at) },
          ]}
        />
      </QueryState>
      {starting && <StartDialog onClose={() => setStarting(false)} onStarted={(id) => navigate(`/opnames/${id}`)} />}
    </>
  );
}

function StartDialog({ onClose, onStarted }: { onClose: () => void; onStarted: (id: string) => void }) {
  const qc = useQueryClient();
  const toast = useToast();
  const choice = useLocationChoice('stock.opname');
  const categories = useCategories();
  const [categoryId, setCategoryId] = useState('');
  const [note, setNote] = useState('');
  const start = useMutation({
    mutationFn: () => api<{ opname: Opname }>('/opnames', { method: 'POST', body: { location_id: choice.locationId, category_id: categoryId || null, note: note.trim() || null } }),
    onSuccess: (res) => {
      toast.success('Stok opname dimulai');
      qc.invalidateQueries({ queryKey: ['opnames'] });
      onClose();
      onStarted(res.opname.id);
    },
    onError: (error) => toast.error(errorMessage(error)),
  });
  return (
    <Modal
      open
      onClose={onClose}
      title="Mulai stok opname"
      footer={
        <>
          <Button onClick={onClose}>Batal</Button>
          <Button variant="primary" loading={start.isPending} disabled={choice.locationId === null} onClick={() => start.mutate()}>Mulai</Button>
        </>
      }
    >
      <div className="space-y-4">
        <LocationSelect choice={choice} />
        <Field label="Kategori" hint="Kosongkan untuk menghitung semua barang di lokasi">
          <Select value={categoryId} onChange={(e) => setCategoryId(e.target.value)}>
            <option value="">Semua</option>
            {categories.data?.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
          </Select>
        </Field>
        <Field label="Catatan"><Input value={note} onChange={(e) => setNote(e.target.value)} /></Field>
      </div>
    </Modal>
  );
}
