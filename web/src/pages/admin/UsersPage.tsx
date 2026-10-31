import { useState } from 'react';
import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Plus, Trash2 } from 'lucide-react';
import { api, errorMessage } from '../../api/client';
import type { ManagedUser, Pagination as Page, Role } from '../../api/types';
import { useAuth } from '../../auth/AuthContext';
import { useLocations, type Location } from '../../lib/locations';
import { formatDateTime } from '../../lib/format';
import {
  Badge,
  Button,
  Checkbox,
  ConfirmButton,
  DataTable,
  Field,
  Input,
  Modal,
  PageHeader,
  Pagination,
  QueryState,
  Select,
  Toolbar,
  useToast,
} from '../../components/ui';

export const useRoles = () =>
  useQuery({ queryKey: ['roles'], queryFn: () => api<{ roles: Role[] }>('/access/roles').then((r) => r.roles), staleTime: 60_000 });

const ALL = 'all'; // select value for "every location" (location_id null)

interface Row {
  location: string; // location id or ALL
  roleId: string;
}

export function UsersPage() {
  const qc = useQueryClient();
  const [search, setSearch] = useState('');
  const [locationId, setLocationId] = useState('');
  const [roleId, setRoleId] = useState('');
  const [inactive, setInactive] = useState(false);
  const [page, setPage] = useState(1);
  const [editing, setEditing] = useState<ManagedUser | 'new' | null>(null);
  const locations = useLocations();
  const roles = useRoles();

  const users = useQuery({
    queryKey: ['users', { search, locationId, roleId, inactive, page }],
    queryFn: () =>
      api<{ users: ManagedUser[]; pagination: Page }>('/users', {
        query: { search, location_id: locationId, role_id: roleId, include_inactive: inactive || undefined, page, limit: 20 },
      }),
    placeholderData: keepPreviousData,
  });

  return (
    <>
      <PageHeader
        title="Pengguna"
        description="Setiap pengguna mendapat role per lokasi. Anda hanya melihat pengguna di lokasi yang Anda kelola."
        actions={
          <Button variant="primary" icon={<Plus className="size-4" />} onClick={() => setEditing('new')}>
            Tambah pengguna
          </Button>
        }
      />
      <Toolbar>
        <Field label="Cari" className="w-64">
          <Input placeholder="Nama atau username" value={search} onChange={(e) => { setSearch(e.target.value); setPage(1); }} />
        </Field>
        <Field label="Lokasi" className="w-48">
          <Select value={locationId} onChange={(e) => { setLocationId(e.target.value); setPage(1); }}>
            <option value="">Semua</option>
            {locations.data?.map((l) => <option key={l.id} value={l.id}>{l.name}</option>)}
          </Select>
        </Field>
        <Field label="Role" className="w-48">
          <Select value={roleId} onChange={(e) => { setRoleId(e.target.value); setPage(1); }}>
            <option value="">Semua</option>
            {roles.data?.map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}
          </Select>
        </Field>
        <div className="pb-2.5">
          <Checkbox label="Tampilkan nonaktif" checked={inactive} onChange={(e) => { setInactive(e.target.checked); setPage(1); }} />
        </div>
      </Toolbar>
      <QueryState query={users}>
        <DataTable
          rows={users.data?.users ?? []}
          rowKey={(u) => u.id}
          onRowClick={(u) => setEditing(u)}
          columns={[
            {
              header: 'Nama',
              cell: (u) => (
                <div>
                  <div className="font-medium">{u.name}</div>
                  <div className="text-xs text-stone-500">@{u.username}</div>
                </div>
              ),
            },
            {
              header: 'Penugasan',
              cell: (u) =>
                u.assignments.length === 0 ? (
                  <span className="text-stone-400">Tanpa akses</span>
                ) : (
                  <div className="flex flex-wrap gap-1">
                    {u.assignments.map((a) => (
                      <Badge key={`${a.location_id}`} tone={a.role_code === 'owner' ? 'gold' : 'gray'}>
                        {a.role_name} · {a.location_id === null ? 'Semua lokasi' : a.location_name}
                      </Badge>
                    ))}
                  </div>
                ),
            },
            { header: 'Status', cell: (u) => (u.is_active ? <Badge tone="green">Aktif</Badge> : <Badge tone="red">Nonaktif</Badge>) },
            { header: 'Terakhir aktif', cell: (u) => formatDateTime(u.last_active_at) },
          ]}
        />
        <Pagination page={page} totalPages={users.data?.pagination.totalPages ?? 1} onChange={setPage} />
      </QueryState>
      {editing && (
        <UserDialog
          user={editing === 'new' ? null : editing}
          locations={locations.data ?? []}
          roles={roles.data ?? []}
          onClose={() => setEditing(null)}
          onSaved={() => qc.invalidateQueries({ queryKey: ['users'] })}
        />
      )}
    </>
  );
}

function UserDialog({
  user,
  locations,
  roles,
  onClose,
  onSaved,
}: {
  user: ManagedUser | null;
  locations: Location[];
  roles: Role[];
  onClose: () => void;
  onSaved: () => void;
}) {
  const { user: me, access } = useAuth();
  const toast = useToast();
  const isSelf = user?.id === me?.id;
  const scope = access.locationsFor('users.manage');
  const mine = (locationId: number | null) => (scope === null ? access.isOwner || locationId !== null : locationId !== null && scope.includes(locationId));

  const [name, setName] = useState(user?.name ?? '');
  const [username, setUsername] = useState(user?.username ?? '');
  const [password, setPassword] = useState('');
  const [active, setActive] = useState(user?.is_active ?? true);
  const [rows, setRows] = useState<Row[]>(() =>
    user
      ? user.assignments.filter((a) => mine(a.location_id)).map((a) => ({ location: a.location_id === null ? ALL : String(a.location_id), roleId: String(a.role_id) }))
      : [{ location: '', roleId: '' }],
  );
  const others = user?.assignments.filter((a) => !mine(a.location_id)) ?? [];
  const offeredLocations = locations.filter((l) => scope === null || scope.includes(l.id));

  const save = useMutation({
    mutationFn: () => {
      const body: Record<string, unknown> = { name: name.trim(), username: username.trim() };
      if (password) body.password = password;
      if (!isSelf) {
        body.assignments = rows.map((r) => ({ location_id: r.location === ALL ? null : Number(r.location), role_id: Number(r.roleId) }));
      }
      if (user) {
        if (!isSelf && active !== user.is_active) body.is_active = active;
        return api(`/users/${user.id}`, { method: 'PUT', body });
      }
      return api('/users', { method: 'POST', body });
    },
    onSuccess: () => {
      toast.success(user ? 'Pengguna diperbarui' : 'Pengguna dibuat');
      onSaved();
      onClose();
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  const incomplete = rows.some((r) => !r.location || !r.roleId) || (!user && (rows.length === 0 || !password));
  const setRow = (i: number, patch: Partial<Row>) => setRows((rs) => rs.map((r, j) => (j === i ? { ...r, ...patch } : r)));

  return (
    <Modal
      open
      onClose={onClose}
      title={user ? `Edit ${user.name}` : 'Tambah pengguna'}
      footer={
        <>
          {user && !isSelf && (
            <ConfirmButton
              label="Hapus"
              icon={<Trash2 className="size-4" />}
              title="Hapus pengguna?"
              message="Pengguna yang sudah punya riwayat transaksi akan dinonaktifkan, bukan dihapus. Jika ia juga bertugas di lokasi lain, hanya penugasan di lokasi Anda yang dihapus."
              confirmLabel="Hapus"
              onConfirm={async () => {
                const res = await api<{ message: string }>(`/users/${user.id}`, { method: 'DELETE' });
                toast.success(res.message);
                onSaved();
                onClose();
              }}
            />
          )}
          <div className="flex-1" />
          <Button onClick={onClose}>Batal</Button>
          <Button variant="primary" loading={save.isPending} disabled={incomplete || !name || !username} onClick={() => save.mutate()}>
            Simpan
          </Button>
        </>
      }
    >
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="Nama lengkap">
          <Input value={name} onChange={(e) => setName(e.target.value)} />
        </Field>
        <Field label="Username">
          <Input value={username} onChange={(e) => setUsername(e.target.value)} autoComplete="off" />
        </Field>
        <Field label={user ? 'Password baru' : 'Password'} hint="Min. 8 karakter, campuran huruf besar, kecil, angka, simbol" className="sm:col-span-2">
          <Input type="password" value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="new-password" placeholder={user ? 'Kosongkan jika tidak diubah' : ''} />
        </Field>
      </div>

      <div className="mt-5">
        <div className="mb-2 text-sm font-medium text-stone-700">Penugasan (lokasi & role)</div>
        {isSelf ? (
          <p className="text-sm text-stone-500">Penugasan akun Anda sendiri hanya dapat diubah oleh pengguna lain.</p>
        ) : (
          <div className="space-y-2">
            {rows.map((row, i) => {
              const everywhere = row.location === ALL;
              // The owner role applies everywhere, so it is only offered on an "every location" row (owners only).
              const roleOptions = everywhere ? roles : roles.filter((r) => r.code !== 'owner');
              return (
                <div key={i} className="flex gap-2">
                  <Select value={row.location} onChange={(e) => setRow(i, { location: e.target.value, roleId: '' })}>
                    <option value="">Pilih lokasi…</option>
                    {access.isOwner && <option value={ALL}>Semua lokasi</option>}
                    {offeredLocations.map((l) => <option key={l.id} value={l.id}>{l.name} ({l.code})</option>)}
                  </Select>
                  <Select value={row.roleId} onChange={(e) => setRow(i, { roleId: e.target.value })}>
                    <option value="">Pilih role…</option>
                    {roleOptions.map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}
                  </Select>
                  <Button variant="ghost" aria-label="Hapus penugasan" onClick={() => setRows((rs) => rs.filter((_, j) => j !== i))}>
                    <Trash2 className="size-4" />
                  </Button>
                </div>
              );
            })}
            {others.map((a) => (
              <p key={`${a.location_id}`} className="text-xs text-stone-500">
                {a.location_id === null ? 'Semua lokasi' : a.location_name} — {a.role_name} (dikelola pengguna lain, tidak diubah)
              </p>
            ))}
            <Button size="sm" variant="ghost" icon={<Plus className="size-4" />} onClick={() => setRows((rs) => [...rs, { location: '', roleId: '' }])}>
              Tambah penugasan
            </Button>
          </div>
        )}
      </div>

      {user && !isSelf && (
        <div className="mt-5">
          <Checkbox label="Akun aktif (bisa login)" checked={active} onChange={(e) => setActive(e.target.checked)} />
        </div>
      )}
    </Modal>
  );
}
