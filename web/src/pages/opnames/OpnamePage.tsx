import { useState, type FormEvent } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Link, useParams } from 'react-router';
import { ArrowLeft, ScanBarcode } from 'lucide-react';
import { api, errorMessage } from '../../api/client';
import type { Opname } from '../../api/types';
import { useAuth } from '../../auth/AuthContext';
import { unitLabel } from '../../lib/catalog';
import { formatDateTime } from '../../lib/format';
import { Badge, Button, Card, ConfirmButton, DataTable, Input, PageHeader, QueryState, useToast } from '../../components/ui';
import { OPNAME_STATUS } from './OpnamesPage';

interface ScanResult {
  result: 'found' | 'already' | 'elsewhere' | 'unknown';
  message: string;
}

export function OpnamePage() {
  const { id } = useParams();
  const { access } = useAuth();
  const qc = useQueryClient();
  const toast = useToast();
  const opname = useQuery({ queryKey: ['opname', id], queryFn: () => api<{ opname: Opname }>(`/opnames/${id}`).then((r) => r.opname) });
  const [counts, setCounts] = useState<Record<number, string>>({});
  const [identifier, setIdentifier] = useState('');
  const [lastScan, setLastScan] = useState<ScanResult | null>(null);
  const o = opname.data;
  const counting = o?.status === 'counting' && access.can('stock.opname', o.location_id);
  const refresh = () => qc.invalidateQueries({ queryKey: ['opname', id] });

  const saveCounts = useMutation({
    mutationFn: () =>
      api(`/opnames/${id}/counts`, {
        method: 'PUT',
        body: { counts: Object.entries(counts).map(([variantId, value]) => ({ variant_id: Number(variantId), counted_qty: value === '' ? null : Number(value) })) },
      }),
    onSuccess: () => {
      toast.success('Hitungan disimpan');
      setCounts({});
      refresh();
    },
    onError: (error) => toast.error(errorMessage(error)),
  });
  const scan = useMutation({
    mutationFn: (value: string) => api<ScanResult>(`/opnames/${id}/scan`, { method: 'POST', body: { identifier: value } }),
    onSuccess: (res) => {
      setLastScan(res);
      setIdentifier('');
      refresh();
    },
    onError: (error) => toast.error(errorMessage(error)),
  });
  const unscan = useMutation({
    mutationFn: (unitId: string) => api(`/opnames/${id}/unscan`, { method: 'POST', body: { unit_id: unitId } }),
    onSuccess: refresh,
    onError: (error) => toast.error(errorMessage(error)),
  });

  const submitScan = (e: FormEvent) => {
    e.preventDefault();
    if (identifier.trim()) scan.mutate(identifier.trim());
  };
  const dirty = Object.keys(counts).length > 0;

  return (
    <QueryState query={opname}>
      {o && (
        <>
          <Link to="/opnames" className="mb-3 inline-flex items-center gap-1 text-sm text-stone-500 hover:text-stone-800">
            <ArrowLeft className="size-4" /> Stok opname
          </Link>
          <PageHeader
            title={o.number}
            description={`${o.location_name}${o.category_name ? ` · ${o.category_name}` : ''} · dimulai ${formatDateTime(o.created_at)} oleh ${o.created_by_name ?? '—'}`}
            actions={
              <>
                <Badge tone={OPNAME_STATUS[o.status][1]}>{OPNAME_STATUS[o.status][0]}</Badge>
                {counting && (
                  <>
                    <ConfirmButton
                      label="Batalkan"
                      title="Batalkan opname?"
                      message="Hitungan dibuang; stok tidak berubah."
                      onConfirm={async () => {
                        await api(`/opnames/${o.id}/cancel`, { method: 'POST' });
                        toast.success('Opname dibatalkan');
                        refresh();
                        qc.invalidateQueries({ queryKey: ['opnames'] });
                      }}
                    />
                    <Button loading={saveCounts.isPending} disabled={!dirty} onClick={() => saveCounts.mutate()}>Simpan hitungan</Button>
                    <ConfirmButton
                      label="Setujui"
                      variant="primary"
                      confirmVariant="primary"
                      disabled={dirty}
                      title="Setujui stok opname?"
                      message="Selisih hitungan diterapkan ke stok dan unit yang tidak dipindai dihapus dari stok. Barang yang belum dihitung tidak diubah."
                      confirmLabel="Setujui"
                      onConfirm={async () => {
                        await api(`/opnames/${o.id}/approve`, { method: 'POST' });
                        toast.success('Stok opname disetujui, stok disesuaikan');
                        refresh();
                        qc.invalidateQueries({ queryKey: ['opnames'] });
                        qc.invalidateQueries({ queryKey: ['stock'] });
                      }}
                    />
                  </>
                )}
              </>
            }
          />

          {counting && (
            <Card className="mb-5">
              <form onSubmit={submitScan} className="flex flex-wrap items-center gap-2">
                <ScanBarcode className="size-5 text-stone-500" />
                <Input className="max-w-sm font-mono" placeholder="Pindai / ketik IMEI atau nomor seri, lalu Enter" value={identifier} onChange={(e) => setIdentifier(e.target.value)} />
                <Button type="submit" loading={scan.isPending}>Pindai</Button>
                {lastScan && <Badge tone={lastScan.result === 'found' ? 'green' : lastScan.result === 'already' ? 'gray' : 'amber'}>{lastScan.message}</Badge>}
              </form>
            </Card>
          )}

          <DataTable
            rows={o.items}
            rowKey={(i) => i.id}
            empty="Tidak ada barang dalam opname ini"
            columns={[
              {
                header: 'Barang',
                cell: (i) => (
                  <div>
                    <div className="font-medium">{i.name} {i.is_serialized && <Badge tone="blue">IMEI</Badge>}</div>
                    <div className="font-mono text-xs text-stone-500">{i.sku}</div>
                    {i.units.length > 0 && (
                      <div className="mt-1 space-y-0.5">
                        {i.units.map((u) => (
                          <div key={u.unit_id} className="flex items-center gap-2 font-mono text-xs">
                            <span className={u.found ? 'text-green-700' : 'text-stone-500'}>{u.found ? '✓' : '○'} {unitLabel(u)}</span>
                            {counting && u.found && (
                              <button type="button" className="text-stone-400 underline hover:text-stone-700" onClick={() => unscan.mutate(u.unit_id)}>batal</button>
                            )}
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                ),
              },
              { header: 'Catatan sistem', align: 'right', cell: (i) => i.system_qty },
              {
                header: 'Hitungan',
                align: 'right',
                cell: (i) =>
                  counting && !i.is_serialized ? (
                    <Input
                      type="number"
                      min={0}
                      className="ml-auto w-24 text-right"
                      value={counts[i.variant_id] ?? (i.counted_qty === null ? '' : String(i.counted_qty))}
                      onChange={(e) => setCounts((c) => ({ ...c, [i.variant_id]: e.target.value }))}
                    />
                  ) : (
                    i.counted_qty ?? '—'
                  ),
              },
              {
                header: 'Selisih',
                align: 'right',
                cell: (i) => (i.variance === null ? '—' : <span className={i.variance < 0 ? 'text-red-600' : i.variance > 0 ? 'text-green-700' : ''}>{i.variance > 0 ? `+${i.variance}` : i.variance}</span>),
              },
            ]}
          />

          {o.extras.length > 0 && (
            <Card title="Temuan (unit tidak terduga)" className="mt-5">
              <DataTable
                rows={o.extras}
                rowKey={(e) => e.id}
                columns={[
                  { header: 'IMEI / serial', cell: (e) => <span className="font-mono text-xs">{e.identifier}</span> },
                  { header: 'Produk', cell: (e) => e.unit_name ?? 'Belum terdaftar' },
                  { header: 'Tercatat di', cell: (e) => (e.unit_id ? `${e.unit_location_code ?? 'luar stok'} (${e.unit_status})` : '—') },
                  { header: 'Waktu', cell: (e) => formatDateTime(e.created_at) },
                ]}
              />
            </Card>
          )}
        </>
      )}
    </QueryState>
  );
}
