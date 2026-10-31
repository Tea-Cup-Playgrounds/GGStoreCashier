const express = require('express');
const pool = require('../db');
const { authenticateToken, requirePermission } = require('../middleware/auth');
const { logAudit } = require('../services/audit');
const stock = require('../services/stock');
const { nextDocumentNumber } = require('../services/documents');
const { DISPLAY_NAME_SQL, ON_HAND_SQL } = require('../services/catalog');
const { AppError, withTransaction } = require('../utils/transaction');
const { ctxOf, requireLocation } = require('../utils/request');
const { uuidv7 } = require('../utils/uuid');
const posting = require('../services/posting');

// Stock counts (opname). Starting one snapshots the system quantity of every stocked variant at
// the location (and the in-stock units of serialized ones). Staff enter counted quantities and
// scan IMEIs; approval applies (counted - snapshot) to current stock, so sales made while counting
// are not lost, and writes off expected units that were never scanned.
const router = express.Router();

router.use(authenticateToken);

const resolveOpname = async (req, res, next) => {
    try {
        const [rows] = await pool.execute('SELECT * FROM stock_opnames WHERE id = ?', [req.params.id]);
        if (rows.length === 0) return res.status(404).json({ error: 'Stok opname tidak ditemukan' });
        req.opname = rows[0];
        next();
    } catch (error) {
        next(error);
    }
};

const opnameLocation = (req) => req.opname.location_id;

const lockCounting = async (conn, id) => {
    const [[opname]] = await conn.execute('SELECT * FROM stock_opnames WHERE id = ? FOR UPDATE', [id]);
    if (opname.status !== 'counting') throw new AppError('Stok opname ini sudah selesai atau dibatalkan');
    return opname;
};

const loadOpname = async (db, id) => {
    const [[opname]] = await db.execute(
        `SELECT o.*, l.code AS location_code, l.name AS location_name, c.name AS category_name,
                cu.name AS created_by_name, au.name AS approved_by_name
         FROM stock_opnames o
         JOIN locations l ON l.id = o.location_id
         LEFT JOIN categories c ON c.id = o.category_id
         LEFT JOIN users cu ON cu.id = o.created_by
         LEFT JOIN users au ON au.id = o.approved_by
         WHERE o.id = ?`,
        [id]
    );
    if (!opname) return null;
    const [items] = await db.execute(
        `SELECT i.id, i.variant_id, ${DISPLAY_NAME_SQL} AS name, v.sku, v.barcode, p.is_serialized, p.serial_type,
                i.system_qty, i.counted_qty, i.note,
                (SELECT COUNT(*) FROM stock_opname_units ou JOIN product_units pu ON pu.id = ou.unit_id
                 WHERE ou.opname_id = i.opname_id AND pu.variant_id = i.variant_id AND ou.found = 1) AS found_units
         FROM stock_opname_items i
         JOIN product_variants v ON v.id = i.variant_id
         JOIN products p ON p.id = v.product_id
         WHERE i.opname_id = ?
         ORDER BY name`,
        [id]
    );
    const [units] = await db.execute(
        `SELECT ou.unit_id, ou.found, pu.variant_id, pu.imei1, pu.imei2, pu.serial_number, pu.status
         FROM stock_opname_units ou JOIN product_units pu ON pu.id = ou.unit_id
         WHERE ou.opname_id = ? ORDER BY pu.imei1, pu.serial_number`,
        [id]
    );
    const [extras] = await db.execute(
        `SELECT e.id, e.identifier, e.unit_id, pu.status AS unit_status, l.code AS unit_location_code,
                ${DISPLAY_NAME_SQL} AS unit_name, e.created_at
         FROM stock_opname_extras e
         LEFT JOIN product_units pu ON pu.id = e.unit_id
         LEFT JOIN locations l ON l.id = pu.location_id
         LEFT JOIN product_variants v ON v.id = pu.variant_id
         LEFT JOIN products p ON p.id = v.product_id
         WHERE e.opname_id = ? ORDER BY e.created_at`,
        [id]
    );
    return {
        ...opname,
        items: items.map((i) => {
            const isSerialized = !!i.is_serialized;
            // Serialized items are counted by scanning, so their count is the number of units found.
            const counted = isSerialized ? Number(i.found_units) : i.counted_qty;
            return {
                ...i,
                is_serialized: isSerialized,
                found_units: Number(i.found_units),
                counted_qty: counted,
                variance: counted === null ? null : counted - i.system_qty,
                units: isSerialized ? units.filter((u) => u.variant_id === i.variant_id).map(({ variant_id, ...u }) => ({ ...u, found: !!u.found })) : [],
            };
        }),
        extras,
    };
};

// GET /api/opnames?location_id=&status=
router.get('/', requirePermission('stock.view'), async (req, res) => {
    try {
        let query = `
            SELECT o.id, o.number, o.location_id, l.code AS location_code, l.name AS location_name, o.status,
                   c.name AS category_name, o.note, o.created_at, o.approved_at,
                   (SELECT COUNT(*) FROM stock_opname_items i WHERE i.opname_id = o.id) AS item_count
            FROM stock_opnames o
            JOIN locations l ON l.id = o.location_id
            LEFT JOIN categories c ON c.id = o.category_id
            WHERE 1 = 1`;
        const params = [];
        if (req.locationId) {
            query += ' AND o.location_id = ?';
            params.push(req.locationId);
        } else {
            const scope = req.access.locationsFor('stock.view');
            if (scope !== null) {
                if (scope.length === 0) return res.json({ opnames: [] });
                query += ` AND o.location_id IN (${scope.map(() => '?').join(', ')})`;
                params.push(...scope);
            }
        }
        if (['counting', 'approved', 'cancelled'].includes(req.query.status)) { query += ' AND o.status = ?'; params.push(req.query.status); }
        query += ' ORDER BY o.created_at DESC LIMIT 100';
        const [opnames] = await pool.execute(query, params);
        res.json({ opnames: opnames.map((o) => ({ ...o, item_count: Number(o.item_count) })) });
    } catch (error) {
        console.error('Get opnames error:', error);
        res.status(500).json({ error: 'Gagal mengambil data stok opname' });
    }
});

router.get('/:id', resolveOpname, requirePermission('stock.view', { location: opnameLocation }), async (req, res) => {
    try {
        res.json({ opname: await loadOpname(pool, req.opname.id) });
    } catch (error) {
        console.error('Get opname error:', error);
        res.status(500).json({ error: 'Gagal mengambil data stok opname' });
    }
});

// Body: { location_id, category_id?, note }. One open count per location at a time.
router.post('/', requirePermission('stock.opname'), requireLocation, async (req, res) => {
    const categoryId = req.body.category_id ? Number(req.body.category_id) : null;
    const result = await withTransaction(res, 'Gagal memulai stok opname', async (conn) => {
        const [open] = await conn.execute("SELECT number FROM stock_opnames WHERE location_id = ? AND status = 'counting' FOR UPDATE", [req.locationId]);
        if (open.length > 0) throw new AppError(`Masih ada stok opname berjalan di lokasi ini (${open[0].number})`, 409);

        const id = uuidv7();
        const number = await nextDocumentNumber(conn, 'SO', req.locationId);
        await conn.execute(
            'INSERT INTO stock_opnames (id, number, location_id, category_id, note, created_by) VALUES (?, ?, ?, ?, ?, ?)',
            [id, number, req.locationId, categoryId, req.body.note || null, req.user.id]
        );

        const [rows] = await conn.execute(
            `SELECT v.id AS variant_id, ${ON_HAND_SQL} AS qty
             FROM stock_levels sl
             JOIN product_variants v ON v.id = sl.variant_id
             JOIN products p ON p.id = v.product_id
             WHERE sl.location_id = ? AND p.kind = 'goods' AND v.deleted_at IS NULL AND p.deleted_at IS NULL
               ${categoryId ? 'AND p.category_id = ?' : ''}`,
            categoryId ? [req.locationId, categoryId] : [req.locationId]
        );
        for (const row of rows) {
            await conn.execute('INSERT INTO stock_opname_items (id, opname_id, variant_id, system_qty) VALUES (?, ?, ?, ?)',
                [uuidv7(), id, row.variant_id, Number(row.qty)]);
        }
        await conn.execute(
            `INSERT INTO stock_opname_units (opname_id, unit_id)
             SELECT ?, u.id FROM product_units u
             JOIN stock_opname_items i ON i.variant_id = u.variant_id AND i.opname_id = ?
             WHERE u.location_id = ? AND u.status = 'in_stock'`,
            [id, id, req.locationId]
        );
        await logAudit(conn, req, { action: 'start', entity: 'opname', entityId: id, locationId: req.locationId, after: { number, items: rows.length } });
        return loadOpname(conn, id);
    });
    if (result) res.status(201).json({ message: 'Stok opname dimulai', opname: result });
});

// Body: { counts: [{ variant_id, counted_qty, note }] } — quantity items only.
// counted_qty null clears a count. Variants not in the snapshot are added (system qty = current).
router.put('/:id/counts', resolveOpname, requirePermission('stock.opname', { location: opnameLocation }), async (req, res) => {
    if (!Array.isArray(req.body.counts) || req.body.counts.length === 0) return res.status(400).json({ error: 'counts wajib diisi' });
    const result = await withTransaction(res, 'Gagal menyimpan hitungan', async (conn) => {
        const opname = await lockCounting(conn, req.opname.id);
        for (const c of req.body.counts) {
            const variant = await stock.getVariant(conn, Number(c.variant_id));
            if (variant.is_serialized) throw new AppError('Produk ber-IMEI dihitung dengan memindai unit');
            const counted = c.counted_qty === null || c.counted_qty === '' ? null : Number(c.counted_qty);
            if (counted !== null && (!Number.isInteger(counted) || counted < 0)) throw new AppError('Jumlah hitungan harus bilangan bulat ≥ 0');

            const [[item]] = await conn.execute('SELECT id FROM stock_opname_items WHERE opname_id = ? AND variant_id = ?', [opname.id, variant.id]);
            if (item) {
                await conn.execute('UPDATE stock_opname_items SET counted_qty = ?, note = ? WHERE id = ?', [counted, c.note || null, item.id]);
            } else {
                const [[level]] = await conn.execute('SELECT qty FROM stock_levels WHERE location_id = ? AND variant_id = ?', [opname.location_id, variant.id]);
                await conn.execute('INSERT INTO stock_opname_items (id, opname_id, variant_id, system_qty, counted_qty, note) VALUES (?, ?, ?, ?, ?, ?)',
                    [uuidv7(), opname.id, variant.id, level ? Number(level.qty) : 0, counted, c.note || null]);
            }
        }
        return loadOpname(conn, opname.id);
    });
    if (result) res.json({ message: 'Hitungan disimpan', opname: result });
});

// Body: { identifier } — an IMEI or serial number scanned during the count.
// result: 'found' (expected here), 'already' (scanned before), 'elsewhere' (registered at another
// location or not in stock), 'unknown' (not registered at all).
router.post('/:id/scan', resolveOpname, requirePermission('stock.opname', { location: opnameLocation }), async (req, res) => {
    const identifier = stock.normalizeIdentifier(req.body.identifier);
    if (!identifier) return res.status(400).json({ error: 'IMEI / nomor seri wajib diisi' });

    const result = await withTransaction(res, 'Gagal memindai unit', async (conn) => {
        const opname = await lockCounting(conn, req.opname.id);
        const [[unit]] = await conn.execute(
            `SELECT u.id, u.status, u.location_id, ${DISPLAY_NAME_SQL} AS name, l.code AS location_code
             FROM product_units u
             JOIN product_variants v ON v.id = u.variant_id
             JOIN products p ON p.id = v.product_id
             LEFT JOIN locations l ON l.id = u.location_id
             WHERE u.imei1 = ? OR u.imei2 = ? OR u.serial_number = ?`,
            [identifier, identifier, identifier]
        );
        if (unit) {
            const [[expected]] = await conn.execute('SELECT found FROM stock_opname_units WHERE opname_id = ? AND unit_id = ?', [opname.id, unit.id]);
            if (expected) {
                if (expected.found) return { result: 'already', unit };
                await conn.execute('UPDATE stock_opname_units SET found = 1 WHERE opname_id = ? AND unit_id = ?', [opname.id, unit.id]);
                return { result: 'found', unit };
            }
        }
        await conn.execute(
            'INSERT IGNORE INTO stock_opname_extras (id, opname_id, identifier, unit_id) VALUES (?, ?, ?, ?)',
            [uuidv7(), opname.id, identifier, unit ? unit.id : null]
        );
        return { result: unit ? 'elsewhere' : 'unknown', unit: unit || null };
    });
    if (result) {
        const messages = {
            found: `Ditemukan: ${result.unit?.name}`,
            already: 'Unit ini sudah dipindai',
            elsewhere: `Unit terdaftar di ${result.unit?.location_code || 'luar stok'} (${result.unit?.status}) — dicatat sebagai temuan`,
            unknown: 'IMEI / nomor seri belum terdaftar — dicatat sebagai temuan',
        };
        res.json({ ...result, message: messages[result.result] });
    }
});

// Body: { unit_id } — undo a scan.
router.post('/:id/unscan', resolveOpname, requirePermission('stock.opname', { location: opnameLocation }), async (req, res) => {
    const result = await withTransaction(res, 'Gagal membatalkan pindaian', async (conn) => {
        const opname = await lockCounting(conn, req.opname.id);
        await conn.execute('UPDATE stock_opname_units SET found = 0 WHERE opname_id = ? AND unit_id = ?', [opname.id, String(req.body.unit_id || '')]);
        return true;
    });
    if (result) res.json({ message: 'Pindaian dibatalkan' });
});

// Applies the count: quantity variances become 'opname' movements; expected units that were
// never scanned (and are still in stock here) are written off. Uncounted quantity items are left alone.
router.post('/:id/approve', resolveOpname, requirePermission('stock.opname', { location: opnameLocation }), async (req, res) => {
    const result = await withTransaction(res, 'Gagal menyetujui stok opname', async (conn) => {
        const opname = await lockCounting(conn, req.opname.id);
        const full = await loadOpname(conn, opname.id);
        const ctx = ctxOf(req);
        const common = { refType: 'opname', refId: opname.id, note: opname.number };
        const summary = { adjusted: 0, unitsWrittenOff: 0, qtyChange: 0 };

        for (const item of full.items) {
            if (item.is_serialized) {
                for (const u of item.units.filter((x) => !x.found && x.status === 'in_stock')) {
                    await stock.removeUnit(conn, ctx, {
                        unitId: u.unit_id, status: 'written_off', reason: 'opname', expectedLocationId: opname.location_id, ...common,
                    }).then(() => { summary.unitsWrittenOff += 1; }, (error) => {
                        // Moved or sold since counting started: nothing to write off.
                        if (!(error instanceof stock.StockError) || error.status !== 409) throw error;
                    });
                }
            } else if (item.variance) {
                await stock.adjustQuantity(conn, ctx, {
                    locationId: opname.location_id, variantId: item.variant_id, qtyChange: item.variance,
                    reason: 'opname', allowNegative: true, ...common,
                });
                summary.adjusted += 1;
                summary.qtyChange += item.variance;
            }
        }

        await conn.execute("UPDATE stock_opnames SET status = 'approved', approved_by = ?, approved_at = NOW(3) WHERE id = ?", [req.user.id, opname.id]);
        await posting.postStockValue(conn, ctx, {
            sourceType: 'opname', sourceId: opname.id, locationId: opname.location_id,
            value: await posting.movementValue(conn, 'opname', opname.id), memo: `Stok opname ${opname.number}`,
        });
        await logAudit(conn, req, { action: 'approve', entity: 'opname', entityId: opname.id, locationId: opname.location_id, after: summary });
        return { opname: await loadOpname(conn, opname.id), summary };
    });
    if (result) res.json({ message: 'Stok opname disetujui, stok disesuaikan', ...result });
});

router.post('/:id/cancel', resolveOpname, requirePermission('stock.opname', { location: opnameLocation }), async (req, res) => {
    const result = await withTransaction(res, 'Gagal membatalkan stok opname', async (conn) => {
        const opname = await lockCounting(conn, req.opname.id);
        await conn.execute("UPDATE stock_opnames SET status = 'cancelled' WHERE id = ?", [opname.id]);
        await logAudit(conn, req, { action: 'cancel', entity: 'opname', entityId: opname.id, locationId: opname.location_id });
        return true;
    });
    if (result) res.json({ message: 'Stok opname dibatalkan' });
});

module.exports = router;
