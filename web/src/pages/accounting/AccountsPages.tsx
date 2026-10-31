import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Plus } from 'lucide-react';
import { api, errorMessage } from '../../api/client';
import type { Account, AccountType } from '../../api/types';
import { useAuth } from '../../auth/AuthContext';
import { useLocations } from '../../lib/locations';
import { formatDateTime } from '../../lib/format';
import { Badge, Button, Card, Checkbox, ConfirmButton, DataTable, Field, Input, Modal, PageHeader, QueryState, Select, useToast } from '../../components/ui';
import { useAccounts } from './JournalsPage';
import { TYPE_LABELS } from './ReportsPages';

// ── chart of accounts ──

export function AccountsPage() {
  const { access } = useAuth();
  const qc = useQueryClient();
  const accounts = useAccounts();
  const [editing, setEditing] = useState<Account | 'new' | null>(null);
  const canEdit = access.can('accounting.post_manual');
  const depth = (a: Account): number => {
    const parent = accounts.data?.find((p) => p.code === a.parent_code);
    return parent ? 1 + depth(parent) : 0;
  };

  return (
    <>
      <PageHeader
        title="Bagan Akun"
        description="Akun induk hanya pengelompokan; jurnal diposting ke akun anak. Tambah akun baru untuk biaya seperti sewa, PBB, atau gaji."
        actions={canEdit && <Button variant="primary" icon={<Plus className="size-4" />} onClick={() => setEditing('new')}>Akun baru</Button>}
      />
      <QueryState query={accounts}>
        <DataTable
          rows={accounts.data ?? []}
          rowKey={(a) => a.id}
          onRowClick={canEdit ? (a) => setEditing(a) : undefined}
          columns={[
            { header: 'Kode', cell: (a) => <span className="font-mono text-xs">{a.code}</span> },
            { header: 'Nama', cell: (a) => <span style={{ paddingLeft: `${depth(a) * 1.25}rem` }} className={a.is_postable ? '' : 'font-semibold'}>{a.name}</span> },
            { header: 'Tipe', cell: (a) => TYPE_LABELS[a.type] },
            {
              header: '',
              cell: (a) => (
                <div className="flex gap-1">
                  {!a.is_postable && <Badge>Induk</Badge>}
                  {a.is_system && <Badge tone="blue">Sistem</Badge>}
                  {!a.is_active && <Badge tone="red">Nonaktif</Badge>}
                </div>
              ),
            },
          ]}
        />
      </QueryState>
      {editing && <AccountDialog account={editing === 'new' ? null : editing} accounts={accounts.data ?? []} onClose={() => setEditing(null)} onSaved={() => qc.invalidateQueries({ queryKey: ['accounts'] })} />}
    </>
  );
}

function AccountDialog({ account, accounts, onClose, onSaved }: { account: Account | null; accounts: Account[]; onClose: () => void; onSaved: () => void }) {
  const toast = useToast();
  const [code, setCode] = useState(account?.code ?? '');
  const [name, setName] = useState(account?.name ?? '');
  const [parentCode, setParentCode] = useState(account?.parent_code ?? '');
  const [type, setType] = useState<AccountType>(account?.type ?? 'expense');
  const [active, setActive] = useState(account?.is_active ?? true);
  const parents = accounts.filter((a) => !a.is_postable);
  const parent = parents.find((p) => p.code === parentCode);

  const save = useMutation({
    mutationFn: () =>
      account
        ? api(`/accounting/accounts/${account.id}`, { method: 'PUT', body: { name: name.trim(), is_active: active } })
        : api('/accounting/accounts', { method: 'POST', body: { code: code.trim(), name: name.trim(), type: parent?.type ?? type, parent_code: parentCode || undefined } }),
    onSuccess: () => {
      toast.success('Akun disimpan');
      onSaved();
      onClose();
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  return (
    <Modal
      open
      onClose={onClose}
      title={account ? `Akun ${account.code}` : 'Akun baru'}
      footer={
        <>
          <Button onClick={onClose}>Batal</Button>
          <Button variant="primary" loading={save.isPending} disabled={!name.trim() || (!account && !code.trim())} onClick={() => save.mutate()}>Simpan</Button>
        </>
      }
    >
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="Kode" hint="mis. 6-1200; tidak bisa diubah setelah dibuat"><Input value={code} onChange={(e) => setCode(e.target.value)} disabled={!!account} className="font-mono" /></Field>
        <Field label="Nama"><Input value={name} onChange={(e) => setName(e.target.value)} /></Field>
        {!account && (
          <>
            <Field label="Induk">
              <Select value={parentCode} onChange={(e) => setParentCode(e.target.value)}>
                <option value="">Tanpa induk</option>
                {parents.map((p) => <option key={p.id} value={p.code}>{p.code} {p.name}</option>)}
              </Select>
            </Field>
            <Field label="Tipe" hint={parent ? 'Mengikuti induk' : undefined}>
              <Select value={parent?.type ?? type} onChange={(e) => setType(e.target.value as AccountType)} disabled={!!parent}>
                {Object.entries(TYPE_LABELS).map(([k, label]) => <option key={k} value={k}>{label}</option>)}
              </Select>
            </Field>
          </>
        )}
        {account && <Checkbox label="Aktif" checked={active} onChange={(e) => setActive(e.target.checked)} />}
      </div>
    </Modal>
  );
}

// ── periods ──

interface Period {
  year: number;
  month: number;
  status: 'open' | 'closed';
  closed_at: string | null;
  closed_by_name: string | null;
}

const MONTHS = ['Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];

export function PeriodsPage() {
  const { access } = useAuth();
  const qc = useQueryClient();
  const toast = useToast();
  const now = new Date();
  const [year, setYear] = useState(String(now.getFullYear()));
  const [month, setMonth] = useState(String(now.getMonth() === 0 ? 12 : now.getMonth()));
  const periods = useQuery({ queryKey: ['periods'], queryFn: () => api<{ periods: Period[] }>('/accounting/periods').then((r) => r.periods) });
  const canClose = access.can('accounting.close_period');
  const refresh = () => qc.invalidateQueries({ queryKey: ['periods'] });

  return (
    <>
      <PageHeader title="Periode Akuntansi" description="Bulan yang ditutup tidak bisa menerima jurnal baru (termasuk penjualan bertanggal di bulan itu)." />
      {canClose && (
        <Card className="mb-5">
          <div className="flex flex-wrap items-end gap-3">
            <Field label="Tahun" className="w-28"><Input type="number" value={year} onChange={(e) => setYear(e.target.value)} /></Field>
            <Field label="Bulan" className="w-40">
              <Select value={month} onChange={(e) => setMonth(e.target.value)}>
                {MONTHS.map((m, i) => <option key={m} value={i + 1}>{m}</option>)}
              </Select>
            </Field>
            <ConfirmButton
              label="Tutup periode"
              variant="primary"
              confirmVariant="primary"
              title={`Tutup ${MONTHS[Number(month) - 1]} ${year}?`}
              message="Setelah ditutup, tidak ada jurnal yang bisa diposting ke bulan ini sampai dibuka kembali."
              confirmLabel="Tutup periode"
              onConfirm={async () => {
                const res = await api<{ message: string }>(`/accounting/periods/${year}/${month}/close`, { method: 'POST' });
                toast.success(res.message);
                refresh();
              }}
            />
          </div>
        </Card>
      )}
      <QueryState query={periods}>
        <DataTable
          rows={periods.data ?? []}
          rowKey={(p) => `${p.year}-${p.month}`}
          empty="Belum ada periode yang ditutup"
          columns={[
            { header: 'Periode', cell: (p) => `${MONTHS[p.month - 1]} ${p.year}` },
            { header: 'Status', cell: (p) => (p.status === 'closed' ? <Badge tone="red">Ditutup</Badge> : <Badge tone="green">Terbuka</Badge>) },
            { header: 'Ditutup', cell: (p) => (p.closed_at ? `${formatDateTime(p.closed_at)} · ${p.closed_by_name ?? ''}` : '—') },
            {
              header: '',
              align: 'right',
              cell: (p) =>
                canClose && p.status === 'closed' ? (
                  <ConfirmButton
                    size="sm"
                    label="Buka kembali"
                    title="Buka kembali periode?"
                    message="Jurnal bisa diposting lagi ke bulan ini."
                    confirmVariant="primary"
                    onConfirm={async () => {
                      await api(`/accounting/periods/${p.year}/${p.month}/reopen`, { method: 'POST' });
                      toast.success('Periode dibuka kembali');
                      refresh();
                    }}
                  />
                ) : null,
            },
          ]}
        />
      </QueryState>
    </>
  );
}

// ── account mappings ──

const MAPPING_LABELS: Record<string, string> = {
  cash: 'Kas (tunai)',
  bank: 'Bank (transfer)',
  ewallet_clearing: 'Piutang QRIS / e-wallet',
  card_clearing: 'Piutang EDC (kartu)',
  inventory: 'Persediaan barang',
  ppn_input: 'PPN masukan',
  accounts_payable: 'Hutang usaha (supplier)',
  ppn_output: 'PPN keluaran',
  opening_balance: 'Saldo awal / ekuitas',
  sales_goods: 'Penjualan barang',
  sales_service: 'Pendapatan jasa',
  sales_digital: 'Pendapatan pulsa & digital',
  cogs: 'Harga pokok penjualan',
  inventory_adjustment: 'Selisih / penyesuaian persediaan',
  cash_over_short: 'Selisih kas shift',
};

interface Mapping {
  id: number;
  key: string;
  location_id: number | null;
  location_code: string | null;
  account_code: string;
  account_name: string;
}

export function MappingsPage() {
  const { access } = useAuth();
  const qc = useQueryClient();
  const mappings = useQuery({ queryKey: ['mappings'], queryFn: () => api<{ mappings: Mapping[] }>('/accounting/mappings').then((r) => r.mappings) });
  const [editing, setEditing] = useState<Mapping | 'new' | null>(null);
  const canEdit = access.can('settings.manage');

  return (
    <>
      <PageHeader
        title="Pemetaan Akun"
        description="Akun yang dipakai jurnal otomatis. Pemetaan per lokasi (mis. rekening bank cabang) mengalahkan pemetaan umum."
        actions={canEdit && <Button variant="primary" icon={<Plus className="size-4" />} onClick={() => setEditing('new')}>Pemetaan lokasi</Button>}
      />
      <QueryState query={mappings}>
        <DataTable
          rows={mappings.data ?? []}
          rowKey={(m) => m.id}
          onRowClick={canEdit ? (m) => setEditing(m) : undefined}
          columns={[
            { header: 'Untuk', cell: (m) => <div>{MAPPING_LABELS[m.key] ?? m.key}<div className="font-mono text-xs text-stone-400">{m.key}</div></div> },
            { header: 'Lokasi', cell: (m) => m.location_code ?? 'Semua' },
            { header: 'Akun', cell: (m) => <span><span className="font-mono text-xs">{m.account_code}</span> {m.account_name}</span> },
          ]}
        />
      </QueryState>
      {editing && (
        <MappingDialog
          mapping={editing === 'new' ? null : editing}
          keys={[...new Set((mappings.data ?? []).map((m) => m.key))]}
          onClose={() => setEditing(null)}
          onSaved={() => qc.invalidateQueries({ queryKey: ['mappings'] })}
        />
      )}
    </>
  );
}

function MappingDialog({ mapping, keys, onClose, onSaved }: { mapping: Mapping | null; keys: string[]; onClose: () => void; onSaved: () => void }) {
  const toast = useToast();
  const accounts = useAccounts();
  const locations = useLocations();
  const [key, setKey] = useState(mapping?.key ?? keys[0] ?? '');
  const [locationId, setLocationId] = useState(String(mapping?.location_id ?? ''));
  const [accountCode, setAccountCode] = useState(mapping?.account_code ?? '');
  const save = useMutation({
    mutationFn: (code: string | null) => api('/accounting/mappings', { method: 'PUT', body: { key, account_code: code, location_id: locationId ? Number(locationId) : null } }),
    onSuccess: () => {
      toast.success('Pemetaan disimpan');
      onSaved();
      onClose();
    },
    onError: (error) => toast.error(errorMessage(error)),
  });
  return (
    <Modal
      open
      onClose={onClose}
      title={mapping ? MAPPING_LABELS[mapping.key] ?? mapping.key : 'Pemetaan per lokasi'}
      footer={
        <>
          {mapping?.location_id && <Button variant="danger" loading={save.isPending} onClick={() => save.mutate(null)}>Hapus pemetaan lokasi</Button>}
          <div className="flex-1" />
          <Button onClick={onClose}>Batal</Button>
          <Button variant="primary" loading={save.isPending} disabled={!key || !accountCode} onClick={() => save.mutate(accountCode)}>Simpan</Button>
        </>
      }
    >
      <div className="grid gap-4">
        <Field label="Untuk">
          <Select value={key} onChange={(e) => setKey(e.target.value)} disabled={!!mapping}>
            {keys.map((k) => <option key={k} value={k}>{MAPPING_LABELS[k] ?? k}</option>)}
          </Select>
        </Field>
        <Field label="Lokasi">
          <Select value={locationId} onChange={(e) => setLocationId(e.target.value)} disabled={!!mapping}>
            <option value="">Semua lokasi</option>
            {locations.data?.map((l) => <option key={l.id} value={l.id}>{l.name}</option>)}
          </Select>
        </Field>
        <Field label="Akun">
          <Select value={accountCode} onChange={(e) => setAccountCode(e.target.value)}>
            <option value="">Pilih akun…</option>
            {accounts.data?.filter((a) => a.is_postable && a.is_active).map((a) => <option key={a.id} value={a.code}>{a.code} {a.name}</option>)}
          </Select>
        </Field>
      </div>
    </Modal>
  );
}
