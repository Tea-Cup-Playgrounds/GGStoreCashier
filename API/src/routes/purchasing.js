const express = require('express');
const pool = require('../db');
const { authenticateToken, requirePermission } = require('../middleware/auth');
const { logAudit } = require('../services/audit');
const stock = require('../services/stock');
const { nextDocumentNumber } = require('../services/documents');
const { DISPLAY_NAME_SQL } = require('../services/catalog');
const { AppError, withTransaction } = require('../utils/transaction');
const { ctxOf, requireLocation, parseDate, parseMoney } = require('../utils/request');
const { uuidv7 } = require('../utils/uuid');
const posting = require('../services/posting');

const router = express.Router();

router.use(authenticateToken);

const round2 = (n) => Math.round(n * 100) / 100;
const PAYMENT_METHODS = ['cash', 'transfer', 'giro', 'other'];

// Viewing suppliers is needed both to manage them and to record purchases.
const requireSupplierAccess = (req, res, next) => {
    if (req.access.can('suppliers.manage') || req.access.can('purchases.manage')) return next();
    return res.status(403).json({ error: 'Akses tidak diizinkan' });
};

// ── suppliers ────────────────────────────────────────────────────────────────

// Outstanding = unpaid part of posted receipts.
router.get('/suppliers', requireSupplierAccess, async (req, res) => {
    try {
        let query = `
            SELECT s.id, s.code, s.name, s.phone, s.email, s.address, s.notes, s.is_active, s.created_at, s.updated_at,
                   COALESCE((SELECT SUM(r.grand_total - r.paid_total) FROM goods_receipts r
                             WHERE r.supplier_id = s.id AND r.status = 'posted'), 0) AS outstanding
            FROM suppliers s
            WHERE s.deleted_at IS NULL`;
        const params = [];
        if (req.query.include_inactive !== 'true') query += ' AND s.is_active = 1';
        if (req.query.search) {
            query += ' AND (s.name LIKE ? OR s.code LIKE ? OR s.phone LIKE ?)';
            params.push(`%${req.query.search}%`, `%${req.query.search}%`, `%${req.query.search}%`);
        }
        query += ' ORDER BY s.name';
        const [suppliers] = await pool.execute(query, params);
        res.json({ suppliers: suppliers.map((s) => ({ ...s, is_active: !!s.is_active })) });
    } catch (error) {
        console.error('Get suppliers error:', error);
        res.status(500).json({ error: 'Gagal mengambil data supplier' });
    }
});

const readSupplier = (body, { partial }) => {
    const fields = {};
    if (!partial || body.name !== undefined) {
        const name = typeof body.name === 'string' ? body.name.trim() : '';
        if (!name || name.length > 150) return { error: 'Nama supplier wajib diisi (maks. 150 karakter)' };
        fields.name = name;
    }
    if (body.code !== undefined && body.code !== null && body.code !== '') {
        const code = String(body.code).trim().toUpperCase();
        if (!/^[A-Z0-9-]{2,20}$/.test(code)) return { error: 'Kode supplier 2–20 karakter (A–Z, 0–9, -)' };
        fields.code = code;
    }
    for (const [key, max] of [['phone', 30], ['email', 100], ['address', 1000], ['notes', 2000]]) {
        if (body[key] === undefined) continue;
        const value = body[key] === null ? '' : String(body[key]).trim();
        if (value.length > max) return { error: `${key} terlalu panjang` };
        fields[key] = value || null;
    }
    if (body.is_active !== undefined) fields.is_active = body.is_active === true || body.is_active === 'true' || body.is_active === 1 ? 1 : 0;
    return { fields };
};

router.post('/suppliers', requirePermission('suppliers.manage'), async (req, res) => {
    const { fields, error } = readSupplier(req.body, { partial: false });
    if (error) return res.status(400).json({ error });

    const result = await withTransaction(res, 'Gagal membuat supplier', async (conn) => {
        const generated = !fields.code;
        if (generated) fields.code = `TMP-${uuidv7().slice(-12)}`;
        const columns = Object.keys(fields);
        let insert;
        try {
            [insert] = await conn.execute(
                `INSERT INTO suppliers (${columns.join(', ')}) VALUES (${columns.map(() => '?').join(', ')})`,
                columns.map((c) => fields[c])
            );
        } catch (err) {
            if (err.code === 'ER_DUP_ENTRY') throw new AppError('Kode supplier sudah digunakan');
            throw err;
        }
        if (generated) {
            await conn.execute("UPDATE suppliers SET code = CONCAT('SUP-', LPAD(id, 4, '0')) WHERE id = ?", [insert.insertId]);
        }
        const [[supplier]] = await conn.execute('SELECT * FROM suppliers WHERE id = ?', [insert.insertId]);
        await logAudit(conn, req, { action: 'create', entity: 'supplier', entityId: supplier.id, after: supplier });
        return supplier;
    });
    if (result) res.status(201).json({ message: 'Supplier berhasil dibuat', supplier: { ...result, is_active: !!result.is_active } });
});

router.put('/suppliers/:id', requirePermission('suppliers.manage'), async (req, res) => {
    const { fields, error } = readSupplier(req.body, { partial: true });
    if (error) return res.status(400).json({ error });
    if (Object.keys(fields).length === 0) return res.status(400).json({ error: 'Tidak ada field yang valid untuk diperbarui' });

    const result = await withTransaction(res, 'Gagal memperbarui supplier', async (conn) => {
        const [[before]] = await conn.execute('SELECT * FROM suppliers WHERE id = ? AND deleted_at IS NULL', [req.params.id]);
        if (!before) throw new AppError('Supplier tidak ditemukan', 404);
        const columns = Object.keys(fields);
        try {
            await conn.execute(`UPDATE suppliers SET ${columns.map((c) => `${c} = ?`).join(', ')} WHERE id = ?`, [...columns.map((c) => fields[c]), before.id]);
        } catch (err) {
            if (err.code === 'ER_DUP_ENTRY') throw new AppError('Kode supplier sudah digunakan');
            throw err;
        }
        await logAudit(conn, req, { action: 'update', entity: 'supplier', entityId: before.id, before, after: fields });
        return true;
    });
    if (result) res.json({ message: 'Supplier berhasil diperbarui' });
});

// ── goods receipts ───────────────────────────────────────────────────────────

const paymentStatusSql = `
    CASE WHEN r.status <> 'posted' THEN NULL
         WHEN r.paid_total >= r.grand_total THEN 'paid'
         WHEN r.paid_total > 0 THEN 'partial'
         ELSE 'unpaid' END`;

// Receipt location as the permission target for routes with :id.
const receiptLocation = async (req) => {
    const [rows] = await pool.execute('SELECT location_id FROM goods_receipts WHERE id = ?', [req.params.id]);
    if (rows.length === 0) throw new AppError('Penerimaan barang tidak ditemukan', 404);
    return rows[0].location_id;
};

// requirePermission() turns errors thrown by the location resolver into 500s; resolve 404s first.
const resolveReceipt = async (req, res, next) => {
    try {
        req.receiptLocationId = await receiptLocation(req);
        next();
    } catch (error) {
        if (error instanceof AppError) return res.status(error.status).json({ error: error.message });
        next(error);
    }
};

// GET /api/purchasing/receipts?location_id=&supplier_id=&status=&payment_status=&from=&to=
router.get('/receipts', requirePermission('purchases.manage'), async (req, res) => {
    try {
        let query = `
            SELECT r.id, r.number, r.supplier_id, s.name AS supplier_name, r.location_id, l.code AS location_code,
                   l.name AS location_name, r.invoice_no, DATE_FORMAT(r.invoice_date, '%Y-%m-%d') AS invoice_date,
                   DATE_FORMAT(r.due_date, '%Y-%m-%d') AS due_date, r.status,
                   r.subtotal, r.tax_total, r.grand_total, r.paid_total, ${paymentStatusSql} AS payment_status,
                   (SELECT COALESCE(SUM(i.qty), 0) FROM goods_receipt_items i WHERE i.receipt_id = r.id) AS item_qty,
                   r.posted_at, r.created_at
            FROM goods_receipts r
            JOIN suppliers s ON s.id = r.supplier_id
            JOIN locations l ON l.id = r.location_id
            WHERE 1 = 1`;
        const params = [];
        if (req.locationId) {
            query += ' AND r.location_id = ?';
            params.push(req.locationId);
        } else {
            const scope = req.access.locationsFor('purchases.manage');
            if (scope !== null) {
                if (scope.length === 0) return res.json({ receipts: [] });
                query += ` AND r.location_id IN (${scope.map(() => '?').join(', ')})`;
                params.push(...scope);
            }
        }
        if (req.query.supplier_id) { query += ' AND r.supplier_id = ?'; params.push(Number(req.query.supplier_id)); }
        if (['draft', 'posted'].includes(req.query.status)) { query += ' AND r.status = ?'; params.push(req.query.status); }
        if (['unpaid', 'partial', 'paid'].includes(req.query.payment_status)) {
            query += ` AND ${paymentStatusSql} = ?`;
            params.push(req.query.payment_status);
        }
        const from = parseDate(req.query.from);
        const to = parseDate(req.query.to);
        if (from) { query += ' AND r.created_at >= ?'; params.push(from); }
        if (to) { query += ' AND r.created_at < DATE_ADD(?, INTERVAL 1 DAY)'; params.push(to); }
        query += ' ORDER BY r.created_at DESC LIMIT 200';

        const [receipts] = await pool.execute(query, params);
        res.json({ receipts: receipts.map((r) => ({ ...r, item_qty: Number(r.item_qty) })) });
    } catch (error) {
        console.error('Get receipts error:', error);
        res.status(500).json({ error: 'Gagal mengambil data penerimaan barang' });
    }
});

const loadReceipt = async (db, id) => {
    const [[receipt]] = await db.execute(
        `SELECT r.*, DATE_FORMAT(r.invoice_date, '%Y-%m-%d') AS invoice_date, DATE_FORMAT(r.due_date, '%Y-%m-%d') AS due_date,
                s.name AS supplier_name, s.code AS supplier_code, l.code AS location_code, l.name AS location_name,
                l.type AS location_type, ${paymentStatusSql} AS payment_status,
                cu.name AS created_by_name, pu.name AS posted_by_name
         FROM goods_receipts r
         JOIN suppliers s ON s.id = r.supplier_id
         JOIN locations l ON l.id = r.location_id
         LEFT JOIN users cu ON cu.id = r.created_by
         LEFT JOIN users pu ON pu.id = r.posted_by
         WHERE r.id = ?`,
        [id]
    );
    if (!receipt) return null;
    const [items] = await db.execute(
        `SELECT i.id, i.variant_id, ${DISPLAY_NAME_SQL} AS name, v.sku, p.is_serialized, p.serial_type,
                i.qty, i.unit_cost, i.tax_rate, i.tax_amount, i.line_total
         FROM goods_receipt_items i
         JOIN product_variants v ON v.id = i.variant_id
         JOIN products p ON p.id = v.product_id
         WHERE i.receipt_id = ?
         ORDER BY i.sort_order`,
        [id]
    );
    const [units] = await db.execute(
        `SELECT u.id, u.receipt_item_id, u.imei1, u.imei2, u.serial_number, u.condition_grade, u.unit_id
         FROM goods_receipt_units u JOIN goods_receipt_items i ON i.id = u.receipt_item_id
         WHERE i.receipt_id = ? ORDER BY u.id`,
        [id]
    );
    const [payments] = await db.execute(
        `SELECT sp.id, sp.amount, sp.method, sp.reference, DATE_FORMAT(sp.paid_at, '%Y-%m-%d') AS paid_at, sp.note, us.name AS created_by_name, sp.created_at
         FROM supplier_payments sp LEFT JOIN users us ON us.id = sp.created_by
         WHERE sp.receipt_id = ? ORDER BY sp.paid_at, sp.created_at`,
        [id]
    );
    return {
        ...receipt,
        items: items.map((i) => ({
            ...i,
            is_serialized: !!i.is_serialized,
            units: units.filter((u) => u.receipt_item_id === i.id).map(({ receipt_item_id, ...u }) => u),
        })),
        payments,
    };
};

router.get('/receipts/:id', resolveReceipt, requirePermission('purchases.manage', { location: (req) => req.receiptLocationId }), async (req, res) => {
    try {
        res.json({ receipt: await loadReceipt(pool, req.params.id) });
    } catch (error) {
        console.error('Get receipt error:', error);
        res.status(500).json({ error: 'Gagal mengambil data penerimaan barang' });
    }
});

// Validates the header and items of a draft. Serialized items get one unit row per qty;
// identifiers are format-checked now and required (outside warehouses) when posting.
const readReceiptBody = async (conn, body) => {
    const [[supplier]] = await conn.execute('SELECT id FROM suppliers WHERE id = ? AND deleted_at IS NULL AND is_active = 1', [Number(body.supplier_id)]);
    if (!supplier) throw new AppError('Supplier tidak ditemukan atau tidak aktif');
    const invoiceDate = parseDate(body.invoice_date);
    const dueDate = parseDate(body.due_date);
    if (invoiceDate === undefined || dueDate === undefined) throw new AppError('Format tanggal harus YYYY-MM-DD');

    if (!Array.isArray(body.items) || body.items.length === 0) throw new AppError('Minimal satu barang wajib diisi');
    if (body.items.length > 300) throw new AppError('Maksimal 300 baris per penerimaan');

    const items = [];
    for (const input of body.items) {
        const variant = await stock.getVariant(conn, Number(input.variant_id));
        if (variant.deleted_at || variant.product_deleted_at) throw new AppError(`Varian ${input.variant_id} sudah dihapus`);
        const unitCost = parseMoney(input.unit_cost);
        const taxRate = input.tax_rate === undefined || input.tax_rate === null || input.tax_rate === '' ? 0 : Number(input.tax_rate);
        if (Number.isNaN(unitCost)) throw new AppError('Harga beli tidak valid');
        if (!Number.isFinite(taxRate) || taxRate < 0 || taxRate > 100) throw new AppError('Tarif pajak harus 0–100');

        let qty = Number(input.qty);
        let units = [];
        if (variant.is_serialized) {
            const given = Array.isArray(input.units) ? input.units : [];
            if (given.length > 0) qty = given.length;
            if (!Number.isInteger(qty) || qty <= 0) throw new AppError('Jumlah unit tidak valid');
            if (qty > 500) throw new AppError('Maksimal 500 unit per baris');
            units = Array.from({ length: qty }, (_, i) => {
                const u = given[i] || {};
                const grade = u.condition_grade || 'new';
                if (!['new', 'A', 'B', 'C'].includes(grade)) throw new AppError('Kondisi unit harus new, A, B, atau C');
                return {
                    imei1: stock.normalizeIdentifier(u.imei1),
                    imei2: stock.normalizeIdentifier(u.imei2),
                    serial_number: stock.normalizeIdentifier(u.serial_number),
                    condition_grade: grade,
                };
            });
        } else if (!Number.isInteger(qty) || qty <= 0) {
            throw new AppError('Jumlah barang harus bilangan bulat lebih dari 0');
        }

        const subtotal = round2(qty * unitCost);
        const taxAmount = round2(subtotal * taxRate / 100);
        items.push({ variantId: variant.id, qty, unitCost, taxRate, taxAmount, lineTotal: round2(subtotal + taxAmount), subtotal, units });
    }

    return {
        supplierId: supplier.id,
        invoiceNo: body.invoice_no ? String(body.invoice_no).trim().slice(0, 50) : null,
        invoiceDate,
        dueDate,
        note: body.note ? String(body.note) : null,
        items,
        subtotal: round2(items.reduce((s, i) => s + i.subtotal, 0)),
        taxTotal: round2(items.reduce((s, i) => s + i.taxAmount, 0)),
    };
};

const writeReceiptItems = async (conn, receiptId, items) => {
    await conn.execute('DELETE FROM goods_receipt_items WHERE receipt_id = ?', [receiptId]);
    for (const [index, item] of items.entries()) {
        const itemId = uuidv7();
        await conn.execute(
            `INSERT INTO goods_receipt_items (id, receipt_id, variant_id, qty, unit_cost, tax_rate, tax_amount, line_total, sort_order)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [itemId, receiptId, item.variantId, item.qty, item.unitCost, item.taxRate, item.taxAmount, item.lineTotal, index]
        );
        for (const u of item.units) {
            await conn.execute(
                `INSERT INTO goods_receipt_units (id, receipt_item_id, imei1, imei2, serial_number, condition_grade)
                 VALUES (?, ?, ?, ?, ?, ?)`,
                [uuidv7(), itemId, u.imei1, u.imei2, u.serial_number, u.condition_grade]
            );
        }
    }
};

// Body: { location_id, supplier_id, invoice_no, invoice_date, due_date, note,
//         items: [{ variant_id, qty, unit_cost, tax_rate, units?: [{ imei1, imei2, serial_number, condition_grade }] }] }
router.post('/receipts', requirePermission('purchases.manage'), requireLocation, async (req, res) => {
    const result = await withTransaction(res, 'Gagal membuat penerimaan barang', async (conn) => {
        const data = await readReceiptBody(conn, req.body);
        const id = uuidv7();
        const number = await nextDocumentNumber(conn, 'GR', req.locationId);
        await conn.execute(
            `INSERT INTO goods_receipts (id, number, supplier_id, location_id, invoice_no, invoice_date, due_date,
                                         subtotal, tax_total, grand_total, note, created_by)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [id, number, data.supplierId, req.locationId, data.invoiceNo, data.invoiceDate, data.dueDate,
                data.subtotal, data.taxTotal, round2(data.subtotal + data.taxTotal), data.note, req.user.id]
        );
        await writeReceiptItems(conn, id, data.items);
        await logAudit(conn, req, { action: 'create', entity: 'goods_receipt', entityId: id, locationId: req.locationId, after: { number, supplier_id: data.supplierId, items: data.items.length } });
        return loadReceipt(conn, id);
    });
    if (result) res.status(201).json({ message: 'Draf penerimaan barang dibuat', receipt: result });
});

// Replaces a draft's header and items. location_id cannot change.
router.put('/receipts/:id', resolveReceipt, requirePermission('purchases.manage', { location: (req) => req.receiptLocationId }), async (req, res) => {
    const result = await withTransaction(res, 'Gagal memperbarui penerimaan barang', async (conn) => {
        const [[receipt]] = await conn.execute('SELECT * FROM goods_receipts WHERE id = ? FOR UPDATE', [req.params.id]);
        if (receipt.status !== 'draft') throw new AppError('Penerimaan yang sudah diposting tidak dapat diubah');
        const data = await readReceiptBody(conn, req.body);
        await conn.execute(
            `UPDATE goods_receipts SET supplier_id = ?, invoice_no = ?, invoice_date = ?, due_date = ?, note = ?,
                                       subtotal = ?, tax_total = ?, grand_total = ?
             WHERE id = ?`,
            [data.supplierId, data.invoiceNo, data.invoiceDate, data.dueDate, data.note,
                data.subtotal, data.taxTotal, round2(data.subtotal + data.taxTotal), receipt.id]
        );
        await writeReceiptItems(conn, receipt.id, data.items);
        await logAudit(conn, req, { action: 'update', entity: 'goods_receipt', entityId: receipt.id, locationId: receipt.location_id, after: { items: data.items.length } });
        return loadReceipt(conn, receipt.id);
    });
    if (result) res.json({ message: 'Draf penerimaan barang diperbarui', receipt: result });
});

router.delete('/receipts/:id', resolveReceipt, requirePermission('purchases.manage', { location: (req) => req.receiptLocationId }), async (req, res) => {
    const result = await withTransaction(res, 'Gagal menghapus penerimaan barang', async (conn) => {
        const [[receipt]] = await conn.execute('SELECT * FROM goods_receipts WHERE id = ? FOR UPDATE', [req.params.id]);
        if (receipt.status !== 'draft') throw new AppError('Penerimaan yang sudah diposting tidak dapat dihapus');
        await conn.execute('DELETE FROM goods_receipts WHERE id = ?', [receipt.id]);
        await logAudit(conn, req, { action: 'delete', entity: 'goods_receipt', entityId: receipt.id, locationId: receipt.location_id, before: { number: receipt.number } });
        return true;
    });
    if (result) res.json({ message: 'Draf penerimaan barang dihapus' });
});

// Posting brings the goods into stock (purchase movements, new IMEI units, average cost update).
// It is final: corrections go through purchase returns.
router.post('/receipts/:id/post', resolveReceipt, requirePermission('purchases.manage', { location: (req) => req.receiptLocationId }), async (req, res) => {
    const result = await withTransaction(res, 'Gagal memposting penerimaan barang', async (conn) => {
        const [[receipt]] = await conn.execute('SELECT * FROM goods_receipts WHERE id = ? FOR UPDATE', [req.params.id]);
        if (receipt.status !== 'draft') throw new AppError('Penerimaan ini sudah diposting');
        const [[location]] = await conn.execute('SELECT type FROM locations WHERE id = ?', [receipt.location_id]);
        const ctx = ctxOf(req);
        const full = await loadReceipt(conn, receipt.id);

        for (const item of full.items) {
            const common = { refType: 'goods_receipt', refId: receipt.id, note: receipt.number };
            if (item.is_serialized) {
                const created = await stock.receiveUnits(conn, ctx, {
                    locationId: receipt.location_id,
                    variantId: item.variant_id,
                    units: item.units.map((u) => ({ ...u, unit_cost: item.unit_cost })),
                    reason: 'purchase',
                    sourceType: 'purchase',
                    sourceId: receipt.id,
                    requireIdentifiers: location.type !== 'warehouse',
                    ...common,
                });
                for (const [i, u] of item.units.entries()) {
                    await conn.execute('UPDATE goods_receipt_units SET unit_id = ? WHERE id = ?', [created[i].id, u.id]);
                }
            } else {
                await stock.adjustQuantity(conn, ctx, {
                    locationId: receipt.location_id, variantId: item.variant_id, qtyChange: item.qty,
                    unitCost: Number(item.unit_cost), reason: 'purchase', ...common,
                });
            }
        }

        await conn.execute("UPDATE goods_receipts SET status = 'posted', posted_by = ?, posted_at = NOW(3) WHERE id = ?", [req.user.id, receipt.id]);
        await posting.postGoodsReceipt(conn, ctx, receipt.id);
        await logAudit(conn, req, { action: 'post', entity: 'goods_receipt', entityId: receipt.id, locationId: receipt.location_id, after: { number: receipt.number, grand_total: receipt.grand_total } });
        return loadReceipt(conn, receipt.id);
    });
    if (result) res.json({ message: 'Penerimaan barang diposting, stok bertambah', receipt: result });
});

// ── supplier payments ────────────────────────────────────────────────────────

// Body: { receipt_id, amount, method, reference, paid_at, note }
router.post('/payments', async (req, res, next) => {
    // The permission target is the receipt's location.
    try {
        const [rows] = await pool.execute('SELECT location_id FROM goods_receipts WHERE id = ?', [req.body.receipt_id || '']);
        if (rows.length === 0) return res.status(404).json({ error: 'Penerimaan barang tidak ditemukan' });
        req.receiptLocationId = rows[0].location_id;
        next();
    } catch (error) {
        next(error);
    }
}, requirePermission('purchases.manage', { location: (req) => req.receiptLocationId }), async (req, res) => {
    const amount = parseMoney(req.body.amount);
    const paidAt = parseDate(req.body.paid_at) ?? new Date().toISOString().slice(0, 10);
    if (Number.isNaN(amount) || amount <= 0) return res.status(400).json({ error: 'Jumlah pembayaran harus lebih dari 0' });
    if (!PAYMENT_METHODS.includes(req.body.method)) return res.status(400).json({ error: 'Metode harus cash, transfer, giro, atau other' });
    if (paidAt === undefined) return res.status(400).json({ error: 'Format tanggal harus YYYY-MM-DD' });

    const result = await withTransaction(res, 'Gagal mencatat pembayaran', async (conn) => {
        const [[receipt]] = await conn.execute('SELECT * FROM goods_receipts WHERE id = ? FOR UPDATE', [req.body.receipt_id]);
        if (receipt.status !== 'posted') throw new AppError('Hanya penerimaan yang sudah diposting yang dapat dibayar');
        const outstanding = round2(Number(receipt.grand_total) - Number(receipt.paid_total));
        if (amount > outstanding) throw new AppError(`Pembayaran melebihi sisa tagihan (${outstanding})`);

        const id = uuidv7();
        await conn.execute(
            `INSERT INTO supplier_payments (id, supplier_id, receipt_id, amount, method, reference, paid_at, note, created_by)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [id, receipt.supplier_id, receipt.id, amount, req.body.method,
                req.body.reference ? String(req.body.reference).slice(0, 100) : null, paidAt,
                req.body.note || null, req.user.id]
        );
        await conn.execute('UPDATE goods_receipts SET paid_total = paid_total + ? WHERE id = ?', [amount, receipt.id]);
        await posting.postSupplierPayment(conn, ctxOf(req), id);
        await logAudit(conn, req, { action: 'pay', entity: 'goods_receipt', entityId: receipt.id, locationId: receipt.location_id, after: { payment_id: id, amount, method: req.body.method } });
        return { id, outstanding: round2(outstanding - amount) };
    });
    if (result) res.status(201).json({ message: 'Pembayaran dicatat', paymentId: result.id, outstanding: result.outstanding });
});

module.exports = router;
