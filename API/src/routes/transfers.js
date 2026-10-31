const express = require('express');
const pool = require('../db');
const { authenticateToken, requirePermission } = require('../middleware/auth');
const { logAudit } = require('../services/audit');
const stock = require('../services/stock');
const { nextDocumentNumber } = require('../services/documents');
const { DISPLAY_NAME_SQL } = require('../services/catalog');
const { AppError, withTransaction } = require('../utils/transaction');
const { ctxOf } = require('../utils/request');
const { uuidv7 } = require('../utils/uuid');
const posting = require('../services/posting');

// Stock transfers between locations:
//   draft (editable) -> sent (stock leaves the source) -> received / partially_received (stock arrives)
// Quantity or units not received stay in transit until resolved: returned to the source or written off.
const router = express.Router();

router.use(authenticateToken);

const round2 = (n) => Math.round(n * 100) / 100;

// Loads the transfer header for :id into req.transfer, or answers 404.
const resolveTransfer = async (req, res, next) => {
    try {
        const [rows] = await pool.execute('SELECT * FROM stock_transfers WHERE id = ?', [req.params.id]);
        if (rows.length === 0) return res.status(404).json({ error: 'Transfer tidak ditemukan' });
        req.transfer = rows[0];
        next();
    } catch (error) {
        next(error);
    }
};

const fromLocation = (req) => req.transfer.from_location_id;
const toLocation = (req) => req.transfer.to_location_id;

const loadTransfer = async (db, id) => {
    const [[transfer]] = await db.execute(
        `SELECT t.*, lf.code AS from_code, lf.name AS from_name, lt.code AS to_code, lt.name AS to_name,
                cu.name AS created_by_name, su.name AS sent_by_name, ru.name AS received_by_name
         FROM stock_transfers t
         JOIN locations lf ON lf.id = t.from_location_id
         JOIN locations lt ON lt.id = t.to_location_id
         LEFT JOIN users cu ON cu.id = t.created_by
         LEFT JOIN users su ON su.id = t.sent_by
         LEFT JOIN users ru ON ru.id = t.received_by
         WHERE t.id = ?`,
        [id]
    );
    if (!transfer) return null;
    const [items] = await db.execute(
        `SELECT i.id, i.variant_id, ${DISPLAY_NAME_SQL} AS name, v.sku, p.is_serialized, p.serial_type,
                i.qty_sent, i.qty_received, i.qty_resolved, i.unit_cost, i.note
         FROM stock_transfer_items i
         JOIN product_variants v ON v.id = i.variant_id
         JOIN products p ON p.id = v.product_id
         WHERE i.transfer_id = ? ORDER BY i.sort_order`,
        [id]
    );
    const [units] = await db.execute(
        `SELECT tu.transfer_item_id, tu.unit_id, tu.outcome, u.imei1, u.imei2, u.serial_number, u.status, u.condition_grade
         FROM stock_transfer_units tu
         JOIN stock_transfer_items i ON i.id = tu.transfer_item_id
         JOIN product_units u ON u.id = tu.unit_id
         WHERE i.transfer_id = ?
         ORDER BY u.imei1, u.serial_number`,
        [id]
    );
    const isOpen = ['sent', 'partially_received'].includes(transfer.status);
    return {
        ...transfer,
        items: items.map((i) => {
            const itemUnits = units.filter((u) => u.transfer_item_id === i.id).map(({ transfer_item_id, ...u }) => u);
            const outstanding = !isOpen ? 0
                : i.is_serialized ? itemUnits.filter((u) => u.outcome === null).length
                    : i.qty_sent - (i.qty_received ?? 0) - i.qty_resolved;
            return { ...i, is_serialized: !!i.is_serialized, units: itemUnits, outstanding };
        }),
    };
};

// GET /api/transfers?location_id=&direction=in|out&status=
router.get('/', requirePermission('stock.view'), async (req, res) => {
    try {
        let query = `
            SELECT t.id, t.number, t.status, t.from_location_id, lf.code AS from_code, lf.name AS from_name,
                   t.to_location_id, lt.code AS to_code, lt.name AS to_name, t.note,
                   (SELECT COALESCE(SUM(i.qty_sent), 0) FROM stock_transfer_items i WHERE i.transfer_id = t.id) AS qty_total,
                   t.sent_at, t.received_at, t.resolved_at, t.created_at
            FROM stock_transfers t
            JOIN locations lf ON lf.id = t.from_location_id
            JOIN locations lt ON lt.id = t.to_location_id
            WHERE 1 = 1`;
        const params = [];
        if (req.locationId) {
            if (req.query.direction === 'in') { query += ' AND t.to_location_id = ?'; params.push(req.locationId); }
            else if (req.query.direction === 'out') { query += ' AND t.from_location_id = ?'; params.push(req.locationId); }
            else { query += ' AND (t.from_location_id = ? OR t.to_location_id = ?)'; params.push(req.locationId, req.locationId); }
        } else {
            const scope = req.access.locationsFor('stock.view');
            if (scope !== null) {
                if (scope.length === 0) return res.json({ transfers: [] });
                const marks = scope.map(() => '?').join(', ');
                query += ` AND (t.from_location_id IN (${marks}) OR t.to_location_id IN (${marks}))`;
                params.push(...scope, ...scope);
            }
        }
        if (req.query.status) {
            const statuses = String(req.query.status).split(',').filter((s) => ['draft', 'sent', 'received', 'partially_received', 'cancelled'].includes(s));
            if (statuses.length > 0) {
                query += ` AND t.status IN (${statuses.map(() => '?').join(', ')})`;
                params.push(...statuses);
            }
        }
        query += ' ORDER BY t.created_at DESC LIMIT 200';
        const [transfers] = await pool.execute(query, params);
        res.json({ transfers: transfers.map((t) => ({ ...t, qty_total: Number(t.qty_total) })) });
    } catch (error) {
        console.error('Get transfers error:', error);
        res.status(500).json({ error: 'Gagal mengambil data transfer' });
    }
});

router.get('/:id', resolveTransfer, async (req, res) => {
    const t = req.transfer;
    if (!req.access.can('stock.view', t.from_location_id) && !req.access.can('stock.view', t.to_location_id)) {
        return res.status(403).json({ error: 'Akses tidak diizinkan' });
    }
    try {
        res.json({ transfer: await loadTransfer(pool, t.id) });
    } catch (error) {
        console.error('Get transfer error:', error);
        res.status(500).json({ error: 'Gagal mengambil data transfer' });
    }
});

// items: [{ variant_id, qty }] for quantity items, [{ variant_id, unit_ids: [...] }] for serialized items.
const readTransferBody = async (conn, body, fromLocationId) => {
    const toLocationId = Number(body.to_location_id);
    if (!Number.isInteger(toLocationId) || toLocationId === fromLocationId) throw new AppError('Lokasi tujuan harus berbeda dari lokasi asal');
    const [[to]] = await conn.execute('SELECT id FROM locations WHERE id = ? AND is_active = 1 AND deleted_at IS NULL', [toLocationId]);
    if (!to) throw new AppError('Lokasi tujuan tidak ditemukan atau tidak aktif');

    if (!Array.isArray(body.items) || body.items.length === 0) throw new AppError('Minimal satu barang wajib diisi');
    const items = [];
    const seenUnits = new Set();
    for (const input of body.items) {
        const variant = await stock.getVariant(conn, Number(input.variant_id));
        if (variant.is_serialized) {
            const unitIds = Array.isArray(input.unit_ids) ? input.unit_ids.map(String) : [];
            if (unitIds.length === 0) throw new AppError('Pilih unit (IMEI) yang akan dikirim');
            for (const unitId of unitIds) {
                if (seenUnits.has(unitId)) throw new AppError('Unit yang sama dipilih lebih dari sekali');
                seenUnits.add(unitId);
            }
            const marks = unitIds.map(() => '?').join(', ');
            const [units] = await conn.execute(
                `SELECT id FROM product_units WHERE id IN (${marks}) AND variant_id = ? AND location_id = ? AND status = 'in_stock'`,
                [...unitIds, variant.id, fromLocationId]
            );
            if (units.length !== unitIds.length) throw new AppError('Sebagian unit tidak tersedia di lokasi asal');
            items.push({ variantId: variant.id, qty: unitIds.length, unitIds, note: input.note || null });
        } else {
            const qty = Number(input.qty);
            if (!Number.isInteger(qty) || qty <= 0) throw new AppError('Jumlah barang harus bilangan bulat lebih dari 0');
            items.push({ variantId: variant.id, qty, unitIds: [], note: input.note || null });
        }
    }
    return { toLocationId, note: body.note ? String(body.note) : null, items };
};

const writeTransferItems = async (conn, transferId, items) => {
    await conn.execute('DELETE FROM stock_transfer_items WHERE transfer_id = ?', [transferId]);
    for (const [index, item] of items.entries()) {
        const itemId = uuidv7();
        await conn.execute(
            'INSERT INTO stock_transfer_items (id, transfer_id, variant_id, qty_sent, note, sort_order) VALUES (?, ?, ?, ?, ?, ?)',
            [itemId, transferId, item.variantId, item.qty, item.note, index]
        );
        for (const unitId of item.unitIds) {
            await conn.execute('INSERT INTO stock_transfer_units (transfer_item_id, unit_id) VALUES (?, ?)', [itemId, unitId]);
        }
    }
};

// Body: { from_location_id, to_location_id, note, items }
router.post('/', requirePermission('transfers.create', { location: (req) => req.body.from_location_id }), async (req, res) => {
    if (!req.locationId) return res.status(400).json({ error: 'from_location_id wajib diisi' });
    const result = await withTransaction(res, 'Gagal membuat transfer', async (conn) => {
        const data = await readTransferBody(conn, req.body, req.locationId);
        const id = uuidv7();
        const number = await nextDocumentNumber(conn, 'TF', req.locationId);
        await conn.execute(
            'INSERT INTO stock_transfers (id, number, from_location_id, to_location_id, note, created_by) VALUES (?, ?, ?, ?, ?, ?)',
            [id, number, req.locationId, data.toLocationId, data.note, req.user.id]
        );
        await writeTransferItems(conn, id, data.items);
        await logAudit(conn, req, { action: 'create', entity: 'transfer', entityId: id, locationId: req.locationId, after: { number, to: data.toLocationId, items: data.items.length } });
        return loadTransfer(conn, id);
    });
    if (result) res.status(201).json({ message: 'Draf transfer dibuat', transfer: result });
});

router.put('/:id', resolveTransfer, requirePermission('transfers.create', { location: fromLocation }), async (req, res) => {
    const result = await withTransaction(res, 'Gagal memperbarui transfer', async (conn) => {
        const [[t]] = await conn.execute('SELECT * FROM stock_transfers WHERE id = ? FOR UPDATE', [req.transfer.id]);
        if (t.status !== 'draft') throw new AppError('Transfer yang sudah dikirim tidak dapat diubah');
        const data = await readTransferBody(conn, req.body, t.from_location_id);
        await conn.execute('UPDATE stock_transfers SET to_location_id = ?, note = ? WHERE id = ?', [data.toLocationId, data.note, t.id]);
        await writeTransferItems(conn, t.id, data.items);
        await logAudit(conn, req, { action: 'update', entity: 'transfer', entityId: t.id, locationId: t.from_location_id, after: { items: data.items.length } });
        return loadTransfer(conn, t.id);
    });
    if (result) res.json({ message: 'Draf transfer diperbarui', transfer: result });
});

router.post('/:id/cancel', resolveTransfer, requirePermission('transfers.create', { location: fromLocation }), async (req, res) => {
    const result = await withTransaction(res, 'Gagal membatalkan transfer', async (conn) => {
        const [[t]] = await conn.execute('SELECT * FROM stock_transfers WHERE id = ? FOR UPDATE', [req.transfer.id]);
        if (t.status !== 'draft') throw new AppError('Hanya draf yang dapat dibatalkan; transfer yang sudah dikirim diselesaikan lewat penerimaan');
        await conn.execute("UPDATE stock_transfers SET status = 'cancelled' WHERE id = ?", [t.id]);
        await logAudit(conn, req, { action: 'cancel', entity: 'transfer', entityId: t.id, locationId: t.from_location_id });
        return true;
    });
    if (result) res.json({ message: 'Transfer dibatalkan' });
});

// Sending takes the stock out of the source: transfer_out movements, units go in_transit.
router.post('/:id/send', resolveTransfer, requirePermission('transfers.send', { location: fromLocation }), async (req, res) => {
    const result = await withTransaction(res, 'Gagal mengirim transfer', async (conn) => {
        const [[t]] = await conn.execute('SELECT * FROM stock_transfers WHERE id = ? FOR UPDATE', [req.transfer.id]);
        if (t.status !== 'draft') throw new AppError('Transfer ini sudah dikirim atau dibatalkan');
        const full = await loadTransfer(conn, t.id);
        const ctx = ctxOf(req);
        const common = { refType: 'transfer', refId: t.id, note: t.number };

        for (const item of full.items) {
            let unitCost;
            if (item.is_serialized) {
                let total = 0;
                for (const u of item.units) {
                    const shipped = await stock.shipUnit(conn, ctx, { unitId: u.unit_id, fromLocationId: t.from_location_id, ...common });
                    total += Number(shipped.unit_cost);
                }
                unitCost = round2(total / item.units.length);
            } else {
                const moved = await stock.adjustQuantity(conn, ctx, {
                    locationId: t.from_location_id, variantId: item.variant_id, qtyChange: -item.qty_sent, reason: 'transfer_out', ...common,
                });
                unitCost = moved.unitCost;
            }
            await conn.execute('UPDATE stock_transfer_items SET unit_cost = ? WHERE id = ?', [unitCost, item.id]);
        }

        await conn.execute("UPDATE stock_transfers SET status = 'sent', sent_by = ?, sent_at = NOW(3) WHERE id = ?", [req.user.id, t.id]);
        await logAudit(conn, req, { action: 'send', entity: 'transfer', entityId: t.id, locationId: t.from_location_id });
        return loadTransfer(conn, t.id);
    });
    if (result) res.json({ message: 'Transfer dikirim', transfer: result });
});

// Body (all optional; omitted means everything arrived):
//   { items: [{ item_id, qty_received }], missing_unit_ids: [...], note }
router.post('/:id/receive', resolveTransfer, requirePermission('transfers.receive', { location: toLocation }), async (req, res) => {
    const result = await withTransaction(res, 'Gagal menerima transfer', async (conn) => {
        const [[t]] = await conn.execute('SELECT * FROM stock_transfers WHERE id = ? FOR UPDATE', [req.transfer.id]);
        if (t.status !== 'sent') throw new AppError(t.status === 'draft' ? 'Transfer belum dikirim' : 'Transfer ini sudah diterima');
        const full = await loadTransfer(conn, t.id);
        const ctx = ctxOf(req);
        const common = { refType: 'transfer', refId: t.id, note: t.number };
        const qtyOverrides = new Map((Array.isArray(req.body.items) ? req.body.items : []).map((i) => [String(i.item_id), Number(i.qty_received)]));
        const missing = new Set((Array.isArray(req.body.missing_unit_ids) ? req.body.missing_unit_ids : []).map(String));
        let complete = true;

        for (const item of full.items) {
            if (item.is_serialized) {
                let received = 0;
                for (const u of item.units) {
                    if (missing.has(u.unit_id)) { complete = false; continue; }
                    await stock.landUnit(conn, ctx, { unitId: u.unit_id, locationId: t.to_location_id, ...common });
                    await conn.execute("UPDATE stock_transfer_units SET outcome = 'received' WHERE transfer_item_id = ? AND unit_id = ?", [item.id, u.unit_id]);
                    received += 1;
                }
                await conn.execute('UPDATE stock_transfer_items SET qty_received = ? WHERE id = ?', [received, item.id]);
            } else {
                const qty = qtyOverrides.has(item.id) ? qtyOverrides.get(item.id) : item.qty_sent;
                if (!Number.isInteger(qty) || qty < 0 || qty > item.qty_sent) {
                    throw new AppError(`Jumlah diterima untuk "${item.name}" harus 0–${item.qty_sent}`);
                }
                if (qty < item.qty_sent) complete = false;
                if (qty > 0) {
                    await stock.adjustQuantity(conn, ctx, {
                        locationId: t.to_location_id, variantId: item.variant_id, qtyChange: qty,
                        unitCost: Number(item.unit_cost), reason: 'transfer_in', ...common,
                    });
                }
                await conn.execute('UPDATE stock_transfer_items SET qty_received = ? WHERE id = ?', [qty, item.id]);
            }
        }

        await conn.execute(
            'UPDATE stock_transfers SET status = ?, received_by = ?, received_at = NOW(3), receive_note = ? WHERE id = ?',
            [complete ? 'received' : 'partially_received', req.user.id, req.body.note || null, t.id]
        );
        await logAudit(conn, req, { action: 'receive', entity: 'transfer', entityId: t.id, locationId: t.to_location_id, after: { complete, missing_units: [...missing] } });
        return loadTransfer(conn, t.id);
    });
    if (result) {
        const message = result.status === 'received' ? 'Transfer diterima lengkap' : 'Transfer diterima sebagian; selisih menunggu penyelesaian';
        res.json({ message, transfer: result });
    }
});

// Settles everything still in transit. Body: { action: 'return' | 'write_off', note }
// 'return' puts it back into the source's stock; 'write_off' records it as lost.
// Decided at the source, by someone allowed to adjust stock there.
router.post('/:id/resolve', resolveTransfer, requirePermission('stock.adjust', { location: fromLocation }), async (req, res) => {
    const { action } = req.body;
    if (!['return', 'write_off'].includes(action)) return res.status(400).json({ error: 'action harus return atau write_off' });
    if (!req.body.note || !String(req.body.note).trim()) return res.status(400).json({ error: 'Alasan (note) wajib diisi' });

    const result = await withTransaction(res, 'Gagal menyelesaikan transfer', async (conn) => {
        const [[t]] = await conn.execute('SELECT * FROM stock_transfers WHERE id = ? FOR UPDATE', [req.transfer.id]);
        if (!['sent', 'partially_received'].includes(t.status)) throw new AppError('Tidak ada barang dalam pengiriman pada transfer ini');
        const full = await loadTransfer(conn, t.id);
        const ctx = ctxOf(req);
        const note = `${t.number}: ${String(req.body.note).trim()}`;
        let settled = 0;
        let lostValue = 0;

        for (const item of full.items) {
            if (item.outstanding <= 0) continue;
            if (item.is_serialized) {
                for (const u of item.units.filter((x) => x.outcome === null)) {
                    if (action === 'return') {
                        await stock.landUnit(conn, ctx, { unitId: u.unit_id, locationId: t.from_location_id, refType: 'transfer', refId: t.id, note });
                    } else {
                        const lost = await stock.writeOffInTransitUnit(conn, { unitId: u.unit_id });
                        lostValue += Number(lost.unit_cost);
                    }
                    await conn.execute('UPDATE stock_transfer_units SET outcome = ? WHERE transfer_item_id = ? AND unit_id = ?',
                        [action === 'return' ? 'returned' : 'written_off', item.id, u.unit_id]);
                }
            } else if (action === 'return') {
                await stock.adjustQuantity(conn, ctx, {
                    locationId: t.from_location_id, variantId: item.variant_id, qtyChange: item.outstanding,
                    unitCost: Number(item.unit_cost), reason: 'transfer_in', refType: 'transfer', refId: t.id, note,
                });
            }
            if (action === 'write_off' && !item.is_serialized) lostValue += item.outstanding * Number(item.unit_cost);
            await conn.execute('UPDATE stock_transfer_items SET qty_received = COALESCE(qty_received, 0), qty_resolved = qty_resolved + ? WHERE id = ?', [item.outstanding, item.id]);
            settled += item.outstanding;
        }
        if (settled === 0) throw new AppError('Tidak ada barang dalam pengiriman pada transfer ini');
        // Goods lost in transit already left the source's stock when sent; this records the loss.
        await posting.postStockValue(conn, ctx, { sourceType: 'transfer', sourceId: t.id, locationId: t.from_location_id, value: -lostValue, memo: note });

        await conn.execute(
            "UPDATE stock_transfers SET status = 'partially_received', resolved_by = ?, resolved_at = NOW(3) WHERE id = ?",
            [req.user.id, t.id]
        );
        await logAudit(conn, req, { action: `resolve_${action}`, entity: 'transfer', entityId: t.id, locationId: t.from_location_id, after: { settled, note: req.body.note } });
        return loadTransfer(conn, t.id);
    });
    if (result) res.json({ message: action === 'return' ? 'Sisa barang dikembalikan ke lokasi asal' : 'Sisa barang dihapus sebagai hilang', transfer: result });
});

module.exports = router;
