import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Plus } from 'lucide-react';
import { Link } from 'react-router';
import { api, errorMessage } from '../../api/client';
import type { PulsaDeposit } from '../../api/types';
import { useAuth } from '../../auth/AuthContext';
import { LocationSelect, useLocationChoice, useLocations } from '../../lib/locations';
import { formatDate, formatRp, today } from '../../lib/format';
import { Badge, Button, Card, DataTable, Field, Input, Modal, PageHeader, QueryState, Select, Stat, Toolbar, useToast } from '../../components/ui';
import { JournalDialog } from './JournalsPage';

const monthLabel = (ym: string) => new Date(`${ym}-01T00:00:00`).toLocaleDateString('id-ID', { month: 'long', year: 'numeric' });

/** Deposit Pulsa: money paid in advance to the pulsa / digital provider. Top-ups add to it; each pulsa sale uses it at the item's harga modal. */
export function PulsaDepositPage() {
  const { access } = useAuth();
  const canTopUp = access.can('expenses.manage');
  const choice = useLocationChoice(canTopUp ? 'expenses.manage' : 'accounting.view', { allowAll: true });
  const [from, setFrom] = useState(`${today().slice(0, 4)}-01-01`);
  const [to, setTo] = useState(today());
  const [topping, setTopping] = useState(false);
  const [selected, setSelected] = useState<string | null>(null);
  const deposit = useQuery({
    queryKey: ['pulsa-deposit', choice.locationId, from, to],
    queryFn: () => api<PulsaDeposit>('/pulsa-deposit', { query: { location_id: choice.locationId, from, to } }),
  });
  const d = deposit.data;

  return (
    <>
      <PageHeader
        title="Deposit Pulsa"
        description={
          <>
            Saldo di penyedia pulsa / produk digital. Top up menambah saldo; setiap penjualan pulsa memakai saldo sebesar harga modalnya
            (atur di <Link className="underline" to="/catalog">Produk</Link> → varian → Harga modal).
          </>
        }
        actions={canTopUp && <Button variant="primary" icon={<Plus className="size-4" />} onClick={() => setTopping(true)}>Top up</Button>}
      />
      <Toolbar>
        <LocationSelect choice={choice} />
        <Field label="Dari" className="w-40"><Input type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></Field>
        <Field label="Sampai" className="w-40"><Input type="date" value={to} onChange={(e) => setTo(e.target.value)} /></Field>
      </Toolbar>
      <QueryState query={deposit}>
        {d && (
          <div className="space-y-5">
            <div className="grid gap-4 sm:grid-cols-3">
              <Stat
                label="Saldo deposit sekarang"
                value={<span className={d.balance < 0 ? 'text-red-600' : ''}>{formatRp(d.balance)}</span>}
                hint={d.balance < 0 ? 'Minus: catat top up yang belum masuk' : undefined}
              />
              <Stat label="Top up pada periode" value={formatRp(d.top_ups.filter((t) => t.status === 'posted').reduce((s, t) => s + t.amount, 0))} />
              <Stat label="Terpakai pada periode" value={formatRp(d.usage.reduce((s, u) => s + u.used, 0))} />
            </div>
            <div className="grid gap-5 lg:grid-cols-2">
              <Card title="Top up">
                <DataTable
                  rows={d.top_ups}
                  rowKey={(t) => t.entry_id}
                  onRowClick={(t) => setSelected(t.entry_id)}
                  empty="Belum ada top up pada periode ini"
                  columns={[
                    { header: 'Tanggal', cell: (t) => formatDate(t.date) },
                    { header: 'Nomor', cell: (t) => <span className="font-mono text-xs">{t.number}</span> },
                    { header: 'Lokasi', cell: (t) => t.location_code ?? 'Pusat' },
                    { header: 'Jumlah', align: 'right', cell: (t) => formatRp(t.amount) },
                    { header: '', cell: (t) => t.status === 'void' && <Badge tone="red">Dibatalkan</Badge> },
                  ]}
                />
              </Card>
              <Card title="Pemakaian per bulan">
                <DataTable
                  rows={d.usage}
                  rowKey={(u) => u.month}
                  empty="Belum ada penjualan pulsa dengan harga modal pada periode ini"
                  columns={[
                    { header: 'Bulan', cell: (u) => monthLabel(u.month) },
                    { header: 'Transaksi', align: 'right', cell: (u) => u.sales },
                    { header: 'Terpakai', align: 'right', cell: (u) => formatRp(u.used) },
                  ]}
                />
              </Card>
            </div>
          </div>
        )}
      </QueryState>
      {topping && <TopUpDialog onClose={() => setTopping(false)} />}
      {selected && <JournalDialog id={selected} onClose={() => setSelected(null)} />}
    </>
  );
}

function TopUpDialog({ onClose }: { onClose: () => void }) {
  const { access } = useAuth();
  const qc = useQueryClient();
  const toast = useToast();
  const locations = useLocations();
  const companyWide = access.locationsFor('expenses.manage') === null;
  const allowed = locations.data?.filter((l) => access.can('expenses.manage', l.id)) ?? [];
  const [date, setDate] = useState(today());
  const [locationId, setLocationId] = useState('');
  const [amount, setAmount] = useState('');
  const [paidFrom, setPaidFrom] = useState<'cash' | 'bank'>('bank');
  const [note, setNote] = useState('');
  const save = useMutation({
    mutationFn: () =>
      api<{ message: string }>('/pulsa-deposit/top-ups', {
        method: 'POST',
        body: { date, location_id: locationId ? Number(locationId) : null, amount: Number(amount), paid_from: paidFrom, note: note.trim() || null },
      }),
    onSuccess: (res) => {
      toast.success(res.message);
      qc.invalidateQueries({ queryKey: ['pulsa-deposit'] });
      qc.invalidateQueries({ queryKey: ['journals'] });
      onClose();
    },
    onError: (error) => toast.error(errorMessage(error)),
  });
  return (
    <Modal
      open
      onClose={onClose}
      title="Top up deposit pulsa"
      footer={
        <>
          <Button onClick={onClose}>Batal</Button>
          <Button variant="primary" loading={save.isPending} disabled={!(Number(amount) > 0) || (!locationId && !companyWide)} onClick={() => save.mutate()}>
            Simpan
          </Button>
        </>
      }
    >
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="Tanggal"><Input type="date" value={date} max={today()} onChange={(e) => setDate(e.target.value)} /></Field>
        <Field label="Lokasi" hint="Lokasi yang memakai deposit ini">
          <Select value={locationId} onChange={(e) => setLocationId(e.target.value)}>
            {companyWide ? <option value="">Pusat (tanpa lokasi)</option> : <option value="">Pilih lokasi…</option>}
            {allowed.map((l) => <option key={l.id} value={l.id}>{l.name}</option>)}
          </Select>
        </Field>
        <Field label="Jumlah"><Input type="number" min={0} value={amount} onChange={(e) => setAmount(e.target.value)} /></Field>
        <Field label="Dibayar dari">
          <Select value={paidFrom} onChange={(e) => setPaidFrom(e.target.value as 'cash' | 'bank')}>
            <option value="bank">Bank</option>
            <option value="cash">Kas</option>
          </Select>
        </Field>
        <Field label="Catatan (opsional)" className="sm:col-span-2"><Input value={note} onChange={(e) => setNote(e.target.value)} placeholder="mis. Transfer ke server pulsa" /></Field>
      </div>
    </Modal>
  );
}
