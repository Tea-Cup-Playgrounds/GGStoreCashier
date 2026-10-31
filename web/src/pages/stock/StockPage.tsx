import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Plus, Trash2 } from 'lucide-react';
import { api, errorMessage } from '../../api/client';
import type { Grade, StockRow } from '../../api/types';
import { useAuth } from '../../auth/AuthContext';
import { LocationSelect, useLocationChoice } from '../../lib/locations';
import { GRADES, VariantPicker, type PickedVariant } from '../../lib/catalog';
import { formatRp } from '../../lib/format';
import { Badge, Button, Checkbox, DataTable, Field, Input, Modal, PageHeader, QueryState, Select, Toolbar, useToast } from '../../components/ui';

type Action = { kind: 'adjust' | 'price' | 'units'; row: Pick<StockRow, 'variant_id' | 'name' | 'is_serialized' | 'on_hand' | 'sell_price' | 'location_price' | 'base_price'> };

export function StockPage() {
  const { access } = useAuth();
  const qc = useQueryClient();
  const choice = useLocationChoice('stock.view');
  const locationId = choice.locationId;
  const [search, setSearch] = useState('');
  const [lowOnly, setLowOnly] = useState(false);
  const [action, setAction] = useState<Action | null>(null);
  const [adding, setAdding] = useState(false);

  const stock = useQuery({
    queryKey: ['stock', locationId, search, lowOnly],
    queryFn: () => api<{ stock: StockRow[] }>('/stock', { query: { location_id: locationId, search, low_stock: lowOnly || undefined } }).then((r) => r.stock),
    enabled: locationId !== null,
  });
  const canAdjust = locationId !== null && access.can('stock.adjust', locationId);
  const canPrice = locationId !== null && access.can('prices.manage_location', locationId);
  const canRegister = locationId !== null && access.can('units.register', locationId);
  const showCost = stock.data?.some((r) => r.avg_cost !== undefined);
  const refresh = () => qc.invalidateQueries({ queryKey: ['stock'] });

  return (
    <>
      <PageHeader
        title="Stok"
        description="Stok per lokasi. Barang ber-IMEI ditambah lewat pendaftaran unit atau penerimaan barang."
        actions={
          (canAdjust || canRegister) && (
            <Button variant="primary" icon={<Plus className="size-4" />} onClick={() => setAdding(true)}>
              Tambah stok
            </Button>
          )
        }
      />
      <Toolbar>
        <LocationSelect choice={choice} />
        <Field label="Cari" className="w-64">
          <Input placeholder="Nama, SKU, barcode" value={search} onChange={(e) => setSearch(e.target.value)} />
        </Field>
        <div className="pb-2.5">
          <Checkbox label="Hanya stok menipis" checked={lowOnly} onChange={(e) => setLowOnly(e.target.checked)} />
        </div>
      </Toolbar>
      {locationId === null ? (
        <p className="text-sm text-stone-500">Anda belum ditugaskan ke lokasi mana pun.</p>
      ) : (
        <QueryState query={stock}>
          <DataTable
            rows={stock.data ?? []}
            rowKey={(r) => r.variant_id}
            empty="Belum ada stok di lokasi ini"
            columns={[
              {
                header: 'Produk',
                cell: (r) => (
                  <div>
                    <div className="font-medium">{r.name} {r.is_serialized && <Badge tone="blue">IMEI</Badge>}</div>
                    <div className="font-mono text-xs text-stone-500">{r.sku}</div>
                  </div>
                ),
              },
              { header: 'Kategori', cell: (r) => r.category_name ?? '—' },
              {
                header: 'Stok',
                align: 'right',
                cell: (r) => <span className={r.on_hand <= (r.reorder_level ?? 5) ? 'font-semibold text-red-600' : ''}>{r.on_hand}</span>,
              },
              {
                header: 'Harga jual',
                align: 'right',
                cell: (r) => <>{formatRp(r.sell_price)}{r.location_price != null && <div className="text-xs text-brand-700">harga lokasi</div>}</>,
              },
              ...(showCost ? [{ header: 'HPP rata-rata', align: 'right' as const, cell: (r: StockRow) => formatRp(r.avg_cost) }] : []),
              {
                header: '',
                align: 'right',
                cell: (r) => (
                  <div className="flex justify-end gap-1">
                    {r.is_serialized
                      ? canRegister && <Button size="sm" variant="ghost" onClick={() => setAction({ kind: 'units', row: r })}>Unit</Button>
                      : canAdjust && <Button size="sm" variant="ghost" onClick={() => setAction({ kind: 'adjust', row: r })}>Sesuaikan</Button>}
                    {canPrice && <Button size="sm" variant="ghost" onClick={() => setAction({ kind: 'price', row: r })}>Harga</Button>}
                  </div>
                ),
              },
            ]}
          />
        </QueryState>
      )}

      {adding && locationId !== null && (
        <Modal open onClose={() => setAdding(false)} title="Tambah stok: pilih produk">
          <VariantPicker
            locationId={locationId}
            onPick={(v: PickedVariant) => {
              setAdding(false);
              const row = { variant_id: v.variantId, name: v.name, is_serialized: v.isSerialized, on_hand: v.onHand ?? 0, sell_price: v.basePrice, location_price: null, base_price: v.basePrice };
              setAction({ kind: v.isSerialized ? 'units' : 'adjust', row });
            }}
          />
        </Modal>
      )}
      {action && locationId !== null && action.kind === 'adjust' && <AdjustDialog locationId={locationId} row={action.row} onClose={() => setAction(null)} onSaved={refresh} />}
      {action && locationId !== null && action.kind === 'price' && <PriceDialog locationId={locationId} row={action.row} onClose={() => setAction(null)} onSaved={refresh} />}
      {action && locationId !== null && action.kind === 'units' && <RegisterUnitsDialog locationId={locationId} row={action.row} onClose={() => setAction(null)} onSaved={refresh} />}
    </>
  );
}

function AdjustDialog({ locationId, row, onClose, onSaved }: { locationId: number; row: Action['row']; onClose: () => void; onSaved: () => void }) {
  const toast = useToast();
  const [qty, setQty] = useState('');
  const [unitCost, setUnitCost] = useState('');
  const [note, setNote] = useState('');
  const change = Number(qty);
  const save = useMutation({
    mutationFn: () =>
      api('/stock/adjust', {
        method: 'POST',
        body: { location_id: locationId, variant_id: row.variant_id, qty_change: change, unit_cost: change > 0 && unitCost !== '' ? Number(unitCost) : undefined, note: note.trim() },
      }),
    onSuccess: () => {
      toast.success('Stok disesuaikan');
      onSaved();
      onClose();
    },
    onError: (error) => toast.error(errorMessage(error)),
  });
  return (
    <Modal
      open
      onClose={onClose}
      title={`Sesuaikan stok: ${row.name}`}
      footer={
        <>
          <Button onClick={onClose}>Batal</Button>
          <Button variant="primary" loading={save.isPending} disabled={!Number.isInteger(change) || change === 0 || !note.trim()} onClick={() => save.mutate()}>
            Simpan
          </Button>
        </>
      }
    >
      <p className="mb-4 text-sm text-stone-600">Stok sekarang: <b>{row.on_hand}</b>. Untuk barang dari supplier, gunakan Penerimaan Barang agar hutang dan pajak tercatat.</p>
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="Perubahan jumlah" hint="Positif menambah, negatif mengurangi">
          <Input type="number" step={1} value={qty} onChange={(e) => setQty(e.target.value)} />
        </Field>
        <Field label="HPP per unit" hint="Untuk penambahan; memengaruhi HPP rata-rata">
          <Input type="number" min={0} value={unitCost} onChange={(e) => setUnitCost(e.target.value)} disabled={!(change > 0)} />
        </Field>
        <Field label="Alasan" className="sm:col-span-2">
          <Input value={note} onChange={(e) => setNote(e.target.value)} placeholder="mis. Stok awal, barang rusak, koreksi hitung" />
        </Field>
      </div>
    </Modal>
  );
}

function PriceDialog({ locationId, row, onClose, onSaved }: { locationId: number; row: Action['row']; onClose: () => void; onSaved: () => void }) {
  const toast = useToast();
  const [price, setPrice] = useState(row.location_price != null ? String(Number(row.location_price)) : '');
  const save = useMutation({
    mutationFn: () => api('/stock/price', { method: 'PUT', body: { location_id: locationId, variant_id: row.variant_id, sell_price: price === '' ? null : Number(price) } }),
    onSuccess: () => {
      toast.success('Harga lokasi disimpan');
      onSaved();
      onClose();
    },
    onError: (error) => toast.error(errorMessage(error)),
  });
  return (
    <Modal
      open
      onClose={onClose}
      title={`Harga di lokasi ini: ${row.name}`}
      footer={
        <>
          <Button onClick={onClose}>Batal</Button>
          <Button variant="primary" loading={save.isPending} onClick={() => save.mutate()}>Simpan</Button>
        </>
      }
    >
      <Field label="Harga jual khusus lokasi" hint={`Kosongkan untuk memakai harga dasar (${formatRp(row.base_price)})`}>
        <Input type="number" min={0} value={price} onChange={(e) => setPrice(e.target.value)} />
      </Field>
    </Modal>
  );
}

interface UnitRow {
  imei1: string;
  imei2: string;
  serial_number: string;
  condition_grade: Grade;
}

function RegisterUnitsDialog({ locationId, row, onClose, onSaved }: { locationId: number; row: Action['row']; onClose: () => void; onSaved: () => void }) {
  const toast = useToast();
  const [units, setUnits] = useState<UnitRow[]>([{ imei1: '', imei2: '', serial_number: '', condition_grade: 'new' }]);
  const [unitCost, setUnitCost] = useState('');
  const [note, setNote] = useState('');
  const save = useMutation({
    mutationFn: () =>
      api<{ message: string }>('/stock/units', {
        method: 'POST',
        body: {
          location_id: locationId,
          variant_id: row.variant_id,
          note: note.trim() || undefined,
          units: units.map((u) => ({
            imei1: u.imei1.trim() || null,
            imei2: u.imei2.trim() || null,
            serial_number: u.serial_number.trim() || null,
            condition_grade: u.condition_grade,
            unit_cost: unitCost === '' ? 0 : Number(unitCost),
          })),
        },
      }),
    onSuccess: (res) => {
      toast.success(res.message);
      onSaved();
      onClose();
    },
    onError: (error) => toast.error(errorMessage(error)),
  });
  const set = (i: number, patch: Partial<UnitRow>) => setUnits((us) => us.map((u, j) => (j === i ? { ...u, ...patch } : u)));
  return (
    <Modal
      open
      wide
      onClose={onClose}
      title={`Daftarkan unit: ${row.name}`}
      footer={
        <>
          <Button onClick={onClose}>Batal</Button>
          <Button variant="primary" loading={save.isPending} disabled={units.length === 0} onClick={() => save.mutate()}>
            Daftarkan {units.length} unit
          </Button>
        </>
      }
    >
      <p className="mb-3 text-sm text-stone-600">Untuk stok awal atau koreksi. IMEI diperiksa dengan digit Luhn. Di gudang, IMEI boleh dikosongkan dan diisi nanti.</p>
      <div className="mb-4 grid gap-4 sm:grid-cols-2">
        <Field label="HPP per unit">
          <Input type="number" min={0} value={unitCost} onChange={(e) => setUnitCost(e.target.value)} />
        </Field>
        <Field label="Catatan">
          <Input value={note} onChange={(e) => setNote(e.target.value)} placeholder="mis. Stok awal" />
        </Field>
      </div>
      <div className="space-y-2">
        {units.map((u, i) => (
          <div key={i} className="grid grid-cols-[1fr_1fr_1fr_8rem_auto] gap-2">
            <Input placeholder="IMEI 1" value={u.imei1} onChange={(e) => set(i, { imei1: e.target.value })} />
            <Input placeholder="IMEI 2" value={u.imei2} onChange={(e) => set(i, { imei2: e.target.value })} />
            <Input placeholder="Nomor seri" value={u.serial_number} onChange={(e) => set(i, { serial_number: e.target.value })} />
            <Select value={u.condition_grade} onChange={(e) => set(i, { condition_grade: e.target.value as Grade })}>
              {GRADES.map(([g, label]) => <option key={g} value={g}>{label}</option>)}
            </Select>
            <Button variant="ghost" aria-label="Hapus baris" onClick={() => setUnits((us) => us.filter((_, j) => j !== i))}>
              <Trash2 className="size-4" />
            </Button>
          </div>
        ))}
        <Button size="sm" variant="ghost" icon={<Plus className="size-4" />} onClick={() => setUnits((us) => [...us, { imei1: '', imei2: '', serial_number: '', condition_grade: 'new' }])}>
          Tambah unit
        </Button>
      </div>
    </Modal>
  );
}
