import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Plus } from 'lucide-react';
import { api, errorMessage } from '../../api/client';
import type { PermissionInfo, Role } from '../../api/types';
import { useAuth } from '../../auth/AuthContext';
import { Badge, Button, Checkbox, ConfirmButton, DataTable, Field, Input, Modal, PageHeader, QueryState, Textarea, useToast } from '../../components/ui';
import { useRoles } from './UsersPage';

const GROUP_LABELS: Record<string, string> = {
  sales: 'Penjualan',
  cash_session: 'Shift kasir',
  catalog: 'Katalog',
  stock: 'Stok',
  transfers: 'Transfer',
  purchasing: 'Pembelian',
  customers: 'Pelanggan',
  accounting: 'Akuntansi',
  reports: 'Laporan',
  admin: 'Administrasi',
  data: 'Data',
};

export function RolesPage() {
  const { access } = useAuth();
  const qc = useQueryClient();
  const roles = useRoles();
  const permissions = useQuery({
    queryKey: ['permissions'],
    queryFn: () => api<{ permissions: PermissionInfo[] }>('/access/permissions').then((r) => r.permissions),
    staleTime: Infinity,
  });
  const [editing, setEditing] = useState<Role | 'new' | null>(null);
  const canManage = access.can('roles.manage');

  return (
    <>
      <PageHeader
        title="Role & Izin"
        description="Role adalah kumpulan izin. Role sistem tidak bisa dihapus; izin role owner tidak bisa diubah."
        actions={
          canManage && (
            <Button variant="primary" icon={<Plus className="size-4" />} onClick={() => setEditing('new')}>
              Role baru
            </Button>
          )
        }
      />
      <QueryState query={roles}>
        <DataTable
          rows={roles.data ?? []}
          rowKey={(r) => r.id}
          onRowClick={canManage ? (r) => setEditing(r) : undefined}
          columns={[
            {
              header: 'Role',
              cell: (r) => (
                <div>
                  <div className="font-medium">
                    {r.name} {r.isSystem && <Badge>Sistem</Badge>}
                  </div>
                  {r.description && <div className="text-xs text-stone-500">{r.description}</div>}
                </div>
              ),
            },
            { header: 'Izin', align: 'right', cell: (r) => (r.code === 'owner' ? 'Semua' : r.permissions.length) },
            { header: 'Pengguna', align: 'right', cell: (r) => r.userCount },
          ]}
        />
      </QueryState>
      {editing && permissions.data && (
        <RoleDialog
          role={editing === 'new' ? null : editing}
          permissions={permissions.data}
          onClose={() => setEditing(null)}
          onSaved={() => qc.invalidateQueries({ queryKey: ['roles'] })}
        />
      )}
    </>
  );
}

function RoleDialog({ role, permissions, onClose, onSaved }: { role: Role | null; permissions: PermissionInfo[]; onClose: () => void; onSaved: () => void }) {
  const { access } = useAuth();
  const toast = useToast();
  const [name, setName] = useState(role?.name ?? '');
  const [description, setDescription] = useState(role?.description ?? '');
  const [selected, setSelected] = useState<Set<string>>(new Set(role?.permissions ?? []));
  const locked = role?.code === 'owner';

  const save = useMutation({
    mutationFn: () => {
      const body = { name: name.trim(), description: description.trim() || null, permissions: [...selected] };
      return role ? api(`/access/roles/${role.id}`, { method: 'PUT', body }) : api('/access/roles', { method: 'POST', body });
    },
    onSuccess: () => {
      toast.success(role ? 'Role diperbarui' : 'Role dibuat');
      onSaved();
      onClose();
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  const groups = [...new Set(permissions.map((p) => p.group))];
  const toggle = (key: string) =>
    setSelected((s) => {
      const next = new Set(s);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });

  return (
    <Modal
      open
      wide
      onClose={onClose}
      title={role ? `Role: ${role.name}` : 'Role baru'}
      footer={
        <>
          {role && !role.isSystem && (
            <ConfirmButton
              label="Hapus role"
              title="Hapus role?"
              message={role.userCount > 0 ? 'Role ini masih dipakai pengguna, jadi tidak bisa dihapus.' : 'Role ini akan dihapus.'}
              disabled={role.userCount > 0}
              onConfirm={async () => {
                await api(`/access/roles/${role.id}`, { method: 'DELETE' });
                toast.success('Role dihapus');
                onSaved();
                onClose();
              }}
            />
          )}
          <div className="flex-1" />
          <Button onClick={onClose}>Batal</Button>
          {!locked && (
            <Button variant="primary" loading={save.isPending} disabled={!name.trim()} onClick={() => save.mutate()}>
              Simpan
            </Button>
          )}
        </>
      }
    >
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="Nama role">
          <Input value={name} onChange={(e) => setName(e.target.value)} disabled={role?.isSystem} />
        </Field>
        <Field label="Deskripsi">
          <Textarea rows={1} value={description} onChange={(e) => setDescription(e.target.value)} disabled={locked} />
        </Field>
      </div>
      {locked ? (
        <p className="mt-4 text-sm text-stone-600">Owner selalu memiliki semua izin di semua lokasi.</p>
      ) : (
        <div className="mt-5 grid gap-4 sm:grid-cols-2">
          {groups.map((group) => (
            <div key={group} className="rounded-lg border border-stone-200 p-3">
              <div className="mb-2 text-xs font-semibold uppercase tracking-wide text-stone-500">{GROUP_LABELS[group] ?? group}</div>
              <div className="space-y-1.5">
                {permissions
                  .filter((p) => p.group === group)
                  .map((p) => (
                    <div key={p.key}>
                      <Checkbox
                        checked={selected.has(p.key)}
                        onChange={() => toggle(p.key)}
                        // You can only grant permissions you hold yourself (the API enforces this too).
                        disabled={!access.isOwner && !access.can(p.key)}
                        label={
                          <span>
                            {p.description} <code className="text-[11px] text-stone-400">{p.key}</code>
                          </span>
                        }
                      />
                    </div>
                  ))}
              </div>
            </div>
          ))}
        </div>
      )}
    </Modal>
  );
}
