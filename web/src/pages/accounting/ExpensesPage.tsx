import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Download, Plus } from 'lucide-react';
import { api, errorMessage } from '../../api/client';
import type { Expense, ExpenseCategory, ExpenseList } from '../../api/types';
import { useAuth } from '../../auth/AuthContext';
import { LocationSelect, useLocationChoice, useLocations } from '../../lib/locations';
import { downloadCsv } from '../../lib/csv';
import { firstOfMonth, formatDate, formatRp, today } from '../../lib/format';
import { Badge, Button, Card, ConfirmButton, DataTable, Field, Input, Modal, PageHeader, QueryState, Select, Toolbar, useToast } from '../../components/ui';

const PAID_FROM: Record<Expense['paid_from'], string> = { cash: 'Kas', bank: 'Bank' };

export const useExpenseCategories = () =>
  useQuery({
    queryKey: ['expense-categories'],
    queryFn: () => api<{ categories: ExpenseCategory[] }>('/expenses/categories').then((r) => r.categories),
    staleTime: 60_000,
  });

/** Biaya: rent, salaries, electricity, internet... Each one posts its journal (Dr expense, Cr cash or bank). */
export function ExpensesPage() {
  const { access } = useAuth();
  const canRecord = access.can('expenses.manage');
  const choice = useLocationChoice(canRecord ? 'expenses.manage' : 'accounting.view', { allowAll: true });
  const categories = useExpenseCategories();
  const [from, setFrom] = useState(firstOfMonth());
  const [to, setTo] = useState(today());
  const [accountId, setAccountId] = useState('');
  const [status, setStatus] = useState('');
  const [creating, setCreating] = useState(false);
  const [selected, setSelected] = useState<Expense | null>(null);

  const list = useQuery({
    queryKey: ['expenses', choice.locationId, from, to, accountId, status],
    queryFn: () => api<ExpenseList>('/expenses', { query: { location_id: choice.locationId, from, to, account_id: accountId, status } }),
  });
  const rows = list.data?.expenses ?? [];

  const exportCsv = () =>
    downloadCsv(`biaya-${from}-${to}`, ['Nomor', 'Tanggal', 'Lokasi', 'Kategori', 'Dibayar ke', 'Catatan', 'Dari', 'Jumlah', 'Status'],
      rows.map((x) => [x.number, x.expense_date, x.location_code ?? 'Pusat', `${x.account_code} ${x.account_name}`, x.payee, x.note, PAID_FROM[x.paid_from], x.amount, x.status === 'void' ? 'Dibatalkan' : 'Tercatat']));

  return (
    <>
      <PageHeader
        title="Biaya"
        description="Biaya operasional: sewa, gaji, listrik, internet, transport. Setiap biaya langsung dijurnal; koreksi dengan membatalkan."
        actions={
          <>
            <Button icon={<Download className="size-4" />} disabled={rows.length === 0} onClick={exportCsv}>CSV</Button>
            {canRecord && <Button variant="primary" icon={<Plus className="size-4" />} onClick={() => setCreating(true)}>Catat biaya</Button>}
          </>
        }
      />
      <Toolbar>
        <LocationSelect choice={choice} />
        <Field label="Dari" className="w-40"><Input type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></Field>
        <Field label="Sampai" className="w-40"><Input type="date" value={to} onChange={(e) => setTo(e.target.value)} /></Field>
        <Field label="Kategori" className="w-56">
          <Select value={accountId} onChange={(e) => setAccountId(e.target.value)}>
            <option value="">Semua</option>
            {categories.data?.map((c) => <option key={c.id} value={c.id}>{c.code} {c.name}</option>)}
          </Select>
        </Field>
        <Field label="Status" className="w-40">
          <Select value={status} onChange={(e) => setStatus(e.target.value)}>
            <option value="">Semua</option>
            <option value="posted">Tercatat</option>
            <option value="void">Dibatalkan</option>
          </Select>
        </Field>
      </Toolbar>
      <QueryState query={list}>
        <div className="grid gap-5 lg:grid-cols-[1fr_280px]">
          <DataTable
            rows={rows}
            rowKey={(x) => x.id}
            onRowClick={(x) => setSelected(x)}
            empty="Belum ada biaya pada periode ini"
            columns={[
              { header: 'Tanggal', cell: (x) => formatDate(x.expense_date) },
              { header: 'Nomor', cell: (x) => <span className="font-mono text-xs">{x.number}</span> },
              { header: 'Lokasi', cell: (x) => x.location_code ?? 'Pusat' },
              { header: 'Kategori', cell: (x) => x.account_name },
              { header: 'Keterangan', wrap: true, cell: (x) => <span className="text-stone-600">{[x.payee, x.note].filter(Boolean).join(' · ')}</span> },
              { header: 'Dari', cell: (x) => PAID_FROM[x.paid_from] },
              {
                header: 'Jumlah',
                align: 'right',
                cell: (x) => <span className={x.status === 'void' ? 'text-stone-400 line-through' : ''}>{formatRp(x.amount)}</span>,
              },
              { header: '', cell: (x) => x.status === 'void' && <Badge tone="red">Dibatalkan</Badge> },
            ]}
          />
          <Card title="Per kategori">
            <dl className="space-y-1.5 text-sm">
              {(list.data?.by_category ?? []).map((c) => (
                <div key={c.category} className="flex justify-between gap-3">
                  <dt className="text-stone-600">{c.category}</dt>
                  <dd className="num">{formatRp(c.amount)}</dd>
                </div>
              ))}
              <div className="flex justify-between gap-3 border-t border-stone-100 pt-2 font-semibold">
                <dt>Total</dt>
                <dd className="num">{formatRp(list.data?.total ?? 0)}</dd>
              </div>
            </dl>
          </Card>
        </div>
      </QueryState>
      {creating && <ExpenseDialog categories={categories.data ?? []} onClose={() => setCreating(false)} />}
      {selected && <ExpenseDetail expense={selected} onClose={() => setSelected(null)} />}
    </>
  );
}

function ExpenseDialog({ categories, onClose }: { categories: ExpenseCategory[]; onClose: () => void }) {
  const { access } = useAuth();
  const qc = useQueryClient();
  const toast = useToast();
  const locations = useLocations();
  // Company-wide expenses (head office) need the permission at every location.
  const companyWide = access.locationsFor('expenses.manage') === null;
  const allowed = locations.data?.filter((l) => access.can('expenses.manage', l.id)) ?? [];
  const [date, setDate] = useState(today());
  const [locationId, setLocationId] = useState('');
  const [accountId, setAccountId] = useState('');
  const [amount, setAmount] = useState('');
  const [paidFrom, setPaidFrom] = useState<'cash' | 'bank'>('cash');
  const [payee, setPayee] = useState('');
  const [note, setNote] = useState('');

  const save = useMutation({
    mutationFn: () =>
      api<{ message: string }>('/expenses', {
        method: 'POST',
        body: {
          date,
          location_id: locationId ? Number(locationId) : null,
          account_id: Number(accountId),
          amount: Number(amount),
          paid_from: paidFrom,
          payee: payee.trim() || null,
          note: note.trim() || null,
        },
      }),
    onSuccess: (res) => {
      toast.success(res.message);
      qc.invalidateQueries({ queryKey: ['expenses'] });
      qc.invalidateQueries({ queryKey: ['journals'] });
      onClose();
    },
    onError: (error) => toast.error(errorMessage(error)),
  });
  const valid = accountId && Number(amount) > 0 && (locationId || companyWide);

  return (
    <Modal
      open
      onClose={onClose}
      title="Catat biaya"
      footer={
        <>
          <Button onClick={onClose}>Batal</Button>
          <Button variant="primary" loading={save.isPending} disabled={!valid} onClick={() => save.mutate()}>Simpan</Button>
        </>
      }
    >
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="Tanggal"><Input type="date" value={date} max={today()} onChange={(e) => setDate(e.target.value)} /></Field>
        <Field label="Lokasi" hint={companyWide ? 'Kosongkan untuk biaya kantor pusat' : undefined}>
          <Select value={locationId} onChange={(e) => setLocationId(e.target.value)}>
            {companyWide ? <option value="">Pusat (tanpa lokasi)</option> : <option value="">Pilih lokasi…</option>}
            {allowed.map((l) => <option key={l.id} value={l.id}>{l.name}</option>)}
          </Select>
        </Field>
        <Field label="Kategori" hint="Kategori baru = akun beban baru di Bagan Akun">
          <Select value={accountId} onChange={(e) => setAccountId(e.target.value)}>
            <option value="">Pilih kategori…</option>
            {categories.map((c) => <option key={c.id} value={c.id}>{c.code} {c.name}</option>)}
          </Select>
        </Field>
        <Field label="Jumlah"><Input type="number" min={0} value={amount} onChange={(e) => setAmount(e.target.value)} /></Field>
        <Field label="Dibayar dari">
          <Select value={paidFrom} onChange={(e) => setPaidFrom(e.target.value as 'cash' | 'bank')}>
            <option value="cash">Kas</option>
            <option value="bank">Bank</option>
          </Select>
        </Field>
        <Field label="Dibayar ke (opsional)"><Input value={payee} onChange={(e) => setPayee(e.target.value)} placeholder="mis. PLN, pemilik ruko" /></Field>
        <Field label="Catatan (opsional)" className="sm:col-span-2"><Input value={note} onChange={(e) => setNote(e.target.value)} placeholder="mis. Listrik bulan Oktober" /></Field>
      </div>
    </Modal>
  );
}

function ExpenseDetail({ expense, onClose }: { expense: Expense; onClose: () => void }) {
  const { access } = useAuth();
  const qc = useQueryClient();
  const toast = useToast();
  const [reason, setReason] = useState('');
  const canVoid = expense.status === 'posted' && access.can('expenses.manage', expense.location_id) &&
    (expense.location_id !== null || access.locationsFor('expenses.manage') === null);

  return (
    <Modal
      open
      onClose={onClose}
      title={expense.number}
      footer={
        <>
          {canVoid && (
            <>
              <Input className="w-56" placeholder="Alasan pembatalan" value={reason} onChange={(e) => setReason(e.target.value)} />
              <ConfirmButton
                label="Batalkan"
                title="Batalkan biaya?"
                message="Jurnal pembalik dibuat dengan tanggal hari ini; biaya tetap tercantum sebagai dibatalkan."
                disabled={!reason.trim()}
                onConfirm={async () => {
                  await api(`/expenses/${expense.id}/void`, { method: 'POST', body: { reason: reason.trim() } });
                  toast.success('Biaya dibatalkan');
                  qc.invalidateQueries({ queryKey: ['expenses'] });
                  qc.invalidateQueries({ queryKey: ['journals'] });
                  onClose();
                }}
              />
            </>
          )}
          <div className="flex-1" />
          <Button onClick={onClose}>Tutup</Button>
        </>
      }
    >
      <dl className="grid grid-cols-[8rem_1fr] gap-y-1.5 text-sm">
        <dt className="text-stone-500">Tanggal</dt><dd>{formatDate(expense.expense_date)}</dd>
        <dt className="text-stone-500">Lokasi</dt><dd>{expense.location_code ?? 'Pusat'}</dd>
        <dt className="text-stone-500">Kategori</dt><dd>{expense.account_code} {expense.account_name}</dd>
        <dt className="text-stone-500">Jumlah</dt><dd className="num font-semibold">{formatRp(expense.amount)}</dd>
        <dt className="text-stone-500">Dibayar dari</dt><dd>{PAID_FROM[expense.paid_from]}</dd>
        <dt className="text-stone-500">Dibayar ke</dt><dd>{expense.payee ?? '—'}</dd>
        <dt className="text-stone-500">Catatan</dt><dd>{expense.note ?? '—'}</dd>
        <dt className="text-stone-500">Dicatat oleh</dt><dd>{expense.created_by_name ?? '—'}</dd>
        <dt className="text-stone-500">Status</dt><dd>{expense.status === 'void' ? <Badge tone="red">Dibatalkan</Badge> : <Badge tone="green">Tercatat</Badge>}</dd>
      </dl>
    </Modal>
  );
}
