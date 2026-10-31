import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Plus } from 'lucide-react';
import { api, errorMessage } from '../../api/client';
import type { Voucher } from '../../api/types';
import { useCategories, VariantPicker } from '../../lib/catalog';
import { formatDate, formatRp, toDateInput, toNumber } from '../../lib/format';
import { Badge, Button, Checkbox, ConfirmButton, DataTable, Field, Input, Modal, PageHeader, QueryState, Select, useToast } from '../../components/ui';

export function VouchersPage() {
  const qc = useQueryClient();
  const [editing, setEditing] = useState<Voucher | 'new' | null>(null);
  const vouchers = useQuery({ queryKey: ['vouchers'], queryFn: () => api<{ vouchers: Voucher[] }>('/vouchers').then((r) => r.vouchers) });
  const categories = useCategories();
  const target = (v: Voucher) =>
    v.target_type === 'category' ? `Kategori: ${categories.data?.find((c) => c.id === v.target_id)?.name ?? v.target_id}` : v.target_type === 'product' ? `Varian #${v.target_id}` : 'Semua barang';

  return (
    <>
      <PageHeader title="Voucher" description="Kode diskon yang dimasukkan kasir saat checkout." actions={<Button variant="primary" icon={<Plus className="size-4" />} onClick={() => setEditing('new')}>Voucher baru</Button>} />
      <QueryState query={vouchers}>
        <DataTable
          rows={vouchers.data ?? []}
          rowKey={(v) => v.id}
          onRowClick={(v) => setEditing(v)}
          empty="Belum ada voucher"
          columns={[
            { header: 'Kode', cell: (v) => <span className="font-mono font-medium">{v.code}</span> },
            { header: 'Diskon', cell: (v) => (v.discount_type === 'percent' ? `${toNumber(v.discount_value)}%` : formatRp(v.discount_value)) },
            { header: 'Berlaku untuk', cell: target },
            { header: 'Periode', cell: (v) => `${formatDate(v.valid_from)} – ${formatDate(v.valid_to)}` },
            { header: 'Status', cell: (v) => (v.is_active ? <Badge tone="green">Aktif</Badge> : <Badge>Nonaktif</Badge>) },
            { header: 'Keterangan', cell: (v) => v.description ?? '' },
          ]}
        />
      </QueryState>
      {editing && <VoucherDialog voucher={editing === 'new' ? null : editing} onClose={() => setEditing(null)} onSaved={() => qc.invalidateQueries({ queryKey: ['vouchers'] })} />}
    </>
  );
}

function VoucherDialog({ voucher, onClose, onSaved }: { voucher: Voucher | null; onClose: () => void; onSaved: () => void }) {
  const toast = useToast();
  const categories = useCategories();
  const [code, setCode] = useState(voucher?.code ?? '');
  const [description, setDescription] = useState(voucher?.description ?? '');
  const [discountType, setDiscountType] = useState<Voucher['discount_type']>(voucher?.discount_type ?? 'percent');
  const [value, setValue] = useState(voucher ? String(toNumber(voucher.discount_value)) : '');
  const [targetType, setTargetType] = useState<string>(voucher?.target_type ?? '');
  const [targetId, setTargetId] = useState<string>(voucher?.target_id ? String(voucher.target_id) : '');
  const [targetLabel, setTargetLabel] = useState<string>(voucher?.target_type === 'product' ? `Varian #${voucher.target_id}` : '');
  const [validFrom, setValidFrom] = useState(toDateInput(voucher?.valid_from));
  const [validTo, setValidTo] = useState(toDateInput(voucher?.valid_to));
  const [active, setActive] = useState(voucher ? !!voucher.is_active : true);

  const save = useMutation({
    mutationFn: () => {
      const body = {
        code: code.trim().toUpperCase(),
        description: description.trim() || null,
        discount_type: discountType,
        discount_value: Number(value),
        target_type: targetType || null,
        target_id: targetType ? Number(targetId) : null,
        valid_from: validFrom || null,
        valid_to: validTo || null,
        is_active: active ? 1 : 0,
      };
      return voucher ? api(`/vouchers/${voucher.id}`, { method: 'PUT', body }) : api('/vouchers', { method: 'POST', body });
    },
    onSuccess: () => {
      toast.success('Voucher disimpan');
      onSaved();
      onClose();
    },
    onError: (error) => toast.error(errorMessage(error)),
  });

  return (
    <Modal
      open
      onClose={onClose}
      title={voucher ? `Voucher ${voucher.code}` : 'Voucher baru'}
      footer={
        <>
          {voucher && (
            <ConfirmButton
              label="Hapus"
              title="Hapus voucher?"
              message="Voucher tidak bisa dipakai lagi. Penjualan yang sudah memakai voucher ini tetap tersimpan."
              onConfirm={async () => {
                await api(`/vouchers/${voucher.id}`, { method: 'DELETE' });
                toast.success('Voucher dihapus');
                onSaved();
                onClose();
              }}
            />
          )}
          <div className="flex-1" />
          <Button onClick={onClose}>Batal</Button>
          <Button variant="primary" loading={save.isPending} disabled={!code.trim() || !value || (!!targetType && !targetId)} onClick={() => save.mutate()}>Simpan</Button>
        </>
      }
    >
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="Kode"><Input value={code} onChange={(e) => setCode(e.target.value.toUpperCase())} className="font-mono" /></Field>
        <Field label="Keterangan"><Input value={description} onChange={(e) => setDescription(e.target.value)} /></Field>
        <Field label="Jenis diskon">
          <Select value={discountType} onChange={(e) => setDiscountType(e.target.value as Voucher['discount_type'])}>
            <option value="percent">Persen</option>
            <option value="fixed">Nominal (Rp)</option>
          </Select>
        </Field>
        <Field label={discountType === 'percent' ? 'Diskon (%)' : 'Diskon (Rp)'}><Input type="number" min={0} value={value} onChange={(e) => setValue(e.target.value)} /></Field>
        <Field label="Berlaku untuk">
          <Select value={targetType} onChange={(e) => { setTargetType(e.target.value); setTargetId(''); setTargetLabel(''); }}>
            <option value="">Semua barang</option>
            <option value="category">Satu kategori</option>
            <option value="product">Satu produk (varian)</option>
          </Select>
        </Field>
        {targetType === 'category' && (
          <Field label="Kategori">
            <Select value={targetId} onChange={(e) => setTargetId(e.target.value)}>
              <option value="">Pilih…</option>
              {categories.data?.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
            </Select>
          </Field>
        )}
        {targetType === 'product' && (
          <div className="sm:col-span-2">
            {targetId ? (
              <div className="flex items-center justify-between rounded-lg border border-stone-200 px-3 py-2 text-sm">
                {targetLabel}
                <Button size="sm" variant="ghost" onClick={() => { setTargetId(''); setTargetLabel(''); }}>Ganti</Button>
              </div>
            ) : (
              <VariantPicker goodsOnly={false} onPick={(v) => { setTargetId(String(v.variantId)); setTargetLabel(v.name); }} />
            )}
          </div>
        )}
        <Field label="Berlaku dari"><Input type="date" value={validFrom} onChange={(e) => setValidFrom(e.target.value)} /></Field>
        <Field label="Berlaku sampai"><Input type="date" value={validTo} onChange={(e) => setValidTo(e.target.value)} /></Field>
        <Checkbox label="Aktif" checked={active} onChange={(e) => setActive(e.target.checked)} />
      </div>
    </Modal>
  );
}
