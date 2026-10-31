import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { api, errorMessage } from '../../api/client';
import type { Grade, Unit, UnitStatus } from '../../api/types';
import { useAuth } from '../../auth/AuthContext';
import { LocationSelect, useLocationChoice } from '../../lib/locations';
import { GRADES, UNIT_STATUS, unitLabel, unitStatusBadge } from '../../lib/catalog';
import { formatDate, formatRp } from '../../lib/format';
import { Button, DataTable, Field, Input, Modal, PageHeader, QueryState, Select, Textarea, Toolbar, useToast } from '../../components/ui';

export function UnitsPage() {
  const qc = useQueryClient();
  const choice = useLocationChoice('stock.view');
  const [search, setSearch] = useState('');
  const [status, setStatus] = useState<UnitStatus | ''>('in_stock');
  const [selected, setSelected] = useState<Unit | null>(null);
  const term = search.replace(/\s+/g, '');
  // An IMEI search looks across every location you can see; otherwise list the chosen location.
  const acrossLocations = term.length >= 4;

  const units = useQuery({
    queryKey: ['units', acrossLocations ? null : choice.locationId, term, status],
    queryFn: () =>
      api<{ units: Unit[] }>('/stock/units', {
        query: acrossLocations ? { search: term } : { location_id: choice.locationId, status: status || undefined },
      }).then((r) => r.units),
    enabled: acrossLocations || choice.locationId !== null,
  });
  const showCost = units.data?.some((u) => u.unit_cost !== undefined);

  return (
    <>
      <PageHeader title="Unit IMEI / Serial" description="Setiap HP/elektronik yang dilacak per unit. Cari IMEI untuk melihat di mana unit berada." />
      <Toolbar>
        <Field label="Cari IMEI / serial" className="w-64">
          <Input placeholder="Min. 4 digit, semua lokasi" value={search} onChange={(e) => setSearch(e.target.value)} />
        </Field>
        {!acrossLocations && (
          <>
            <LocationSelect choice={choice} />
            <Field label="Status" className="w-44">
              <Select value={status} onChange={(e) => setStatus(e.target.value as UnitStatus | '')}>
                <option value="">Semua</option>
                {Object.entries(UNIT_STATUS).map(([s, [label]]) => <option key={s} value={s}>{label}</option>)}
              </Select>
            </Field>
          </>
        )}
      </Toolbar>
      <QueryState query={units}>
        <DataTable
          rows={units.data ?? []}
          rowKey={(u) => u.id}
          onRowClick={(u) => setSelected(u)}
          empty="Tidak ada unit"
          columns={[
            { header: 'IMEI / Serial', cell: (u) => <span className="font-mono text-xs">{unitLabel(u)}</span> },
            { header: 'Produk', cell: (u) => u.name },
            { header: 'Lokasi', cell: (u) => u.location_name ?? '—' },
            { header: 'Status', cell: (u) => unitStatusBadge(u.status) },
            { header: 'Kondisi', cell: (u) => GRADES.find(([g]) => g === u.condition_grade)?.[1] ?? u.condition_grade },
            { header: 'Harga jual', align: 'right', cell: (u) => formatRp(u.sell_price) },
            ...(showCost ? [{ header: 'HPP', align: 'right' as const, cell: (u: Unit) => formatRp(u.unit_cost) }] : []),
            { header: 'Garansi s/d', cell: (u) => formatDate(u.warranty_until) },
          ]}
        />
      </QueryState>
      {selected && <UnitDialog unit={selected} onClose={() => setSelected(null)} onSaved={() => qc.invalidateQueries({ queryKey: ['units'] })} />}
    </>
  );
}

function UnitDialog({ unit, onClose, onSaved }: { unit: Unit; onClose: () => void; onSaved: () => void }) {
  const { access } = useAuth();
  const toast = useToast();
  const [imei1, setImei1] = useState(unit.imei1 ?? '');
  const [imei2, setImei2] = useState(unit.imei2 ?? '');
  const [serial, setSerial] = useState(unit.serial_number ?? '');
  const [grade, setGrade] = useState<Grade>(unit.condition_grade);
  const [price, setPrice] = useState('');
  const [notes, setNotes] = useState(unit.notes ?? '');
  const [removing, setRemoving] = useState<'defective' | 'written_off' | null>(null);
  const [reason, setReason] = useState('');
  const inStock = unit.status === 'in_stock' && unit.location_id !== null;
  const canEdit = unit.location_id !== null && access.can('units.register', unit.location_id);
  const canRemove = inStock && access.can('stock.adjust', unit.location_id);

  const save = useMutation({
    mutationFn: () =>
      api(`/stock/units/${unit.id}`, {
        method: 'PUT',
        body: { imei1: imei1.trim() || null, imei2: imei2.trim() || null, serial_number: serial.trim() || null, condition_grade: grade, notes: notes.trim() || null, ...(price !== '' ? { sell_price: Number(price) } : {}) },
      }),
    onSuccess: () => {
      toast.success('Unit diperbarui');
      onSaved();
      onClose();
    },
    onError: (error) => toast.error(errorMessage(error)),
  });
  const remove = useMutation({
    mutationFn: () => api<{ message: string }>(`/stock/units/${unit.id}/write-off`, { method: 'POST', body: { status: removing, note: reason.trim() } }),
    onSuccess: (res) => {
      toast.success(res.message);
      onSaved();
      onClose();
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  return (
    <Modal
      open
      onClose={onClose}
      title={unit.name}
      footer={
        removing ? (
          <>
            <Button onClick={() => setRemoving(null)}>Kembali</Button>
            <Button variant="danger" loading={remove.isPending} disabled={!reason.trim()} onClick={() => remove.mutate()}>
              {removing === 'defective' ? 'Tandai rusak' : 'Hapus dari stok'}
            </Button>
          </>
        ) : (
          <>
            {canRemove && <Button onClick={() => setRemoving('defective')}>Tandai rusak</Button>}
            {canRemove && <Button onClick={() => setRemoving('written_off')}>Hapus dari stok</Button>}
            <div className="flex-1" />
            <Button onClick={onClose}>Tutup</Button>
            {canEdit && <Button variant="primary" loading={save.isPending} onClick={() => save.mutate()}>Simpan</Button>}
          </>
        )
      }
    >
      <div className="mb-4 flex items-center gap-2 text-sm text-stone-600">
        {unitStatusBadge(unit.status)} {unit.location_name ?? 'Tidak di lokasi mana pun'}
      </div>
      {removing ? (
        <Field label="Alasan" hint="Nilai unit dicatat sebagai kerugian persediaan.">
          <Textarea rows={2} value={reason} onChange={(e) => setReason(e.target.value)} autoFocus />
        </Field>
      ) : (
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="IMEI 1"><Input value={imei1} onChange={(e) => setImei1(e.target.value)} disabled={!canEdit} /></Field>
          <Field label="IMEI 2"><Input value={imei2} onChange={(e) => setImei2(e.target.value)} disabled={!canEdit} /></Field>
          <Field label="Nomor seri"><Input value={serial} onChange={(e) => setSerial(e.target.value)} disabled={!canEdit} /></Field>
          <Field label="Kondisi">
            <Select value={grade} onChange={(e) => setGrade(e.target.value as Grade)} disabled={!canEdit}>
              {GRADES.map(([g, label]) => <option key={g} value={g}>{label}</option>)}
            </Select>
          </Field>
          <Field label="Harga jual unit ini" hint={`Sekarang ${formatRp(unit.sell_price)}; kosongkan jika tidak diubah`}>
            <Input type="number" min={0} value={price} onChange={(e) => setPrice(e.target.value)} disabled={!canEdit} />
          </Field>
          <Field label="Catatan" className="sm:col-span-2"><Textarea rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} disabled={!canEdit} /></Field>
        </div>
      )}
    </Modal>
  );
}
