const express = require('express');
const pool = require('../db');
const { authenticateToken, requirePermission } = require('../middleware/auth');
const { logAudit } = require('../services/audit');
const stock = require('../services/stock');
const { ON_HAND_SQL, AVG_COST_SQL, DISPLAY_NAME_SQL, canSeeCost } = require('../services/catalog');

const router = express.Router();

router.use(authenticateToken);

const ctxOf = (req) => ({ userId: req.user.id, deviceId: req.deviceId || null });

// Runs fn(conn) in a transaction; StockError becomes a 4xx response.
const withTransaction = async (res, fallbackMessage, fn) => {
    const conn = await pool.getConnection();
    try {
        await conn.beginTransaction();
        const result = await fn(conn);
        await conn.commit();
        return result;
    } catch (error) {
        await conn.rollback();
        if (error instanceof stock.StockError) {
            res.status(error.status).json({ error: error.message });
        } else {
            console.error(`${fallbackMessage}:`, error);
            res.status(500).json({ error: fallbackMessage });
        }
        return undefined;
    } finally {
        conn.release();
    }
};

const requireLocation = (req, res, next) => {
    if (!req.locationId) return res.status(400).json({ error: 'location_id wajib diisi' });
    next();
};

const unitLocation = async (req) => {
    const [rows] = await pool.execute('SELECT location_id FROM product_units WHERE id = ?', [req.params.id]);
    // Units in transit or sold have no location; only owners/global roles can touch them.
    return rows.length === 0 ? undefined : rows[0].location_id;
};

// ── stock levels ─────────────────────────────────────────────────────────────

// GET /api/stock?location_id=&search=&low_stock=true
// Every variant stocked at the location, with on-hand qty and effective price.
router.get('/', requirePermission('stock.view'), requireLocation, async (req, res) => {
    try {
        const showCost = canSeeCost(req.access, req.locationId);
        let query = `
            SELECT v.id AS variant_id, v.sku, v.barcode, ${DISPLAY_NAME_SQL} AS name, p.id AS product_id,
                   p.is_serialized, p.serial_type, p.image, c.name AS category_name, b.name AS brand_name,
                   ${ON_HAND_SQL} AS on_hand, sl.reorder_level,
                   v.base_price, sl.sell_price AS location_price, COALESCE(sl.sell_price, v.base_price) AS sell_price
                   ${showCost ? `, ${AVG_COST_SQL} AS avg_cost` : ''}, sl.updated_at
            FROM stock_levels sl
            JOIN product_variants v ON v.id = sl.variant_id
            JOIN products p ON p.id = v.product_id
            LEFT JOIN categories c ON c.id = p.category_id
            LEFT JOIN brands b ON b.id = p.brand_id
            WHERE sl.location_id = ? AND v.deleted_at IS NULL AND p.deleted_at IS NULL`;
        const params = [req.locationId];
        if (req.query.search) {
            query += ' AND (p.name LIKE ? OR v.name LIKE ? OR v.sku LIKE ? OR v.barcode = ?)';
            params.push(`%${req.query.search}%`, `%${req.query.search}%`, `%${req.query.search}%`, req.query.search);
        }
        query += ' ORDER BY name';

        let [rows] = await pool.execute(query, params);
        rows = rows.map((r) => ({ ...r, is_serialized: !!r.is_serialized, on_hand: Number(r.on_hand) }));
        if (req.query.low_stock === 'true') {
            rows = rows.filter((r) => r.on_hand <= (r.reorder_level ?? 5));
        }
        res.json({ stock: rows });
    } catch (error) {
        console.error('Get stock error:', error);
        res.status(500).json({ error: 'Gagal mengambil data stok' });
    }
});

// Body: { location_id, variant_id, qty_change, unit_cost?, note }
// Manual correction or opening stock for non-serialized items. Incoming stock with unit_cost
// updates the average cost.
router.post('/adjust', requirePermission('stock.adjust'), requireLocation, async (req, res) => {
    const { variant_id, qty_change, unit_cost, note } = req.body;
    if (!note || !String(note).trim()) return res.status(400).json({ error: 'Alasan penyesuaian (note) wajib diisi' });

    const result = await withTransaction(res, 'Gagal menyesuaikan stok', async (conn) => {
        const r = await stock.adjustQuantity(conn, ctxOf(req), {
            locationId: req.locationId, variantId: Number(variant_id), qtyChange: Number(qty_change),
            unitCost: unit_cost, reason: 'adjustment', note: String(note).trim(),
        });
        await logAudit(conn, req, {
            action: 'adjust', entity: 'stock', entityId: variant_id, locationId: req.locationId,
            after: { qty_change: Number(qty_change), unit_cost: unit_cost ?? null, note, qty: r.qty },
        });
        return r;
    });
    if (result) res.json({ message: 'Stok berhasil disesuaikan', qty: result.qty, movementId: result.movementId });
});

// Body: { location_id, variant_id, sell_price }  — sell_price null removes the location override.
router.put('/price', requirePermission('prices.manage_location'), requireLocation, async (req, res) => {
    const { variant_id } = req.body;
    const sellPrice = req.body.sell_price === null || req.body.sell_price === '' ? null : Number(req.body.sell_price);
    const result = await withTransaction(res, 'Gagal mengubah harga', async (conn) => {
        const price = await stock.setLocationPrice(conn, { locationId: req.locationId, variantId: Number(variant_id), sellPrice });
        await logAudit(conn, req, { action: 'set_price', entity: 'stock', entityId: variant_id, locationId: req.locationId, after: { sell_price: price } });
        return { price };
    });
    if (result) res.json({ message: 'Harga lokasi berhasil diperbarui', sell_price: result.price });
});

// GET /api/stock/movements?location_id=&variant_id=&unit_id=&limit=&before=<created_at ISO>
router.get('/movements', requirePermission('stock.view'), requireLocation, async (req, res) => {
    try {
        const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 50, 1), 200);
        const showCost = canSeeCost(req.access, req.locationId);
        let query = `
            SELECT m.id, m.variant_id, ${DISPLAY_NAME_SQL} AS name, v.sku, m.unit_id, u.imei1, u.serial_number,
                   m.qty_change, ${showCost ? 'm.unit_cost,' : ''} m.reason, m.ref_type, m.ref_id, m.note,
                   m.user_id, us.name AS user_name, m.created_at
            FROM stock_movements m
            JOIN product_variants v ON v.id = m.variant_id
            JOIN products p ON p.id = v.product_id
            LEFT JOIN product_units u ON u.id = m.unit_id
            LEFT JOIN users us ON us.id = m.user_id
            WHERE m.location_id = ?`;
        const params = [req.locationId];
        if (req.query.variant_id) { query += ' AND m.variant_id = ?'; params.push(Number(req.query.variant_id)); }
        if (req.query.unit_id) { query += ' AND m.unit_id = ?'; params.push(req.query.unit_id); }
        if (req.query.before) { query += ' AND m.created_at < ?'; params.push(new Date(req.query.before)); }
        query += ` ORDER BY m.created_at DESC, m.id DESC LIMIT ${limit}`;

        const [movements] = await pool.execute(query, params);
        res.json({ movements });
    } catch (error) {
        console.error('Get movements error:', error);
        res.status(500).json({ error: 'Gagal mengambil riwayat stok' });
    }
});

// ── serialized units ─────────────────────────────────────────────────────────

// GET /api/stock/units?location_id=&variant_id=&status=&search=<IMEI/serial>
// With search and no location_id, looks across every location the user may view.
router.get('/units', requirePermission('stock.view'), async (req, res) => {
    try {
        const showCost = req.locationId ? canSeeCost(req.access, req.locationId) : req.access.isOwner;
        let query = `
            SELECT u.id, u.variant_id, ${DISPLAY_NAME_SQL} AS name, v.sku, u.location_id, l.code AS location_code,
                   l.name AS location_name, u.imei1, u.imei2, u.serial_number, u.status, u.condition_grade,
                   ${showCost ? 'u.unit_cost,' : ''} COALESCE(u.sell_price, sl.sell_price, v.base_price) AS sell_price,
                   u.source_type, u.warranty_until, u.notes, u.created_at, u.updated_at
            FROM product_units u
            JOIN product_variants v ON v.id = u.variant_id
            JOIN products p ON p.id = v.product_id
            LEFT JOIN locations l ON l.id = u.location_id
            LEFT JOIN stock_levels sl ON sl.variant_id = u.variant_id AND sl.location_id = u.location_id
            WHERE 1 = 1`;
        const params = [];

        if (req.locationId) {
            query += ' AND u.location_id = ?';
            params.push(req.locationId);
        } else {
            if (!req.query.search) return res.status(400).json({ error: 'location_id atau search wajib diisi' });
            const visible = req.access.locationsFor('stock.view');
            if (visible !== null) {
                if (visible.length === 0) return res.json({ units: [] });
                query += ` AND u.location_id IN (${visible.map(() => '?').join(', ')})`;
                params.push(...visible);
            }
        }
        if (req.query.variant_id) { query += ' AND u.variant_id = ?'; params.push(Number(req.query.variant_id)); }
        if (req.query.status) { query += ' AND u.status = ?'; params.push(req.query.status); }
        if (req.query.search) {
            query += ' AND (u.imei1 = ? OR u.imei2 = ? OR u.serial_number = ? OR u.imei1 LIKE ? OR u.serial_number LIKE ?)';
            const s = String(req.query.search).replace(/\s+/g, '');
            params.push(s, s, s, `%${s}%`, `%${s}%`);
        }
        query += ' ORDER BY u.created_at DESC LIMIT 500';

        const [units] = await pool.execute(query, params);
        res.json({ units });
    } catch (error) {
        console.error('Get units error:', error);
        res.status(500).json({ error: 'Gagal mengambil data unit' });
    }
});

// Body: { location_id, variant_id, units: [{ imei1, imei2, serial_number, unit_cost, condition_grade, sell_price, notes }], note }
// Registers units as stock (opening stock / correction; supplier receipts come with purchasing).
// IMEI/serial may be left empty only when receiving at a warehouse.
router.post('/units', requirePermission('units.register'), requireLocation, async (req, res) => {
    const { variant_id, units, note } = req.body;
    const result = await withTransaction(res, 'Gagal mendaftarkan unit', async (conn) => {
        const [[location]] = await conn.execute('SELECT type FROM locations WHERE id = ?', [req.locationId]);
        const created = await stock.receiveUnits(conn, ctxOf(req), {
            locationId: req.locationId, variantId: Number(variant_id), units,
            reason: 'adjustment', sourceType: 'adjustment', note: note || 'Pendaftaran unit',
            requireIdentifiers: !location || location.type !== 'warehouse',
        });
        await logAudit(conn, req, {
            action: 'register_units', entity: 'stock', entityId: variant_id, locationId: req.locationId,
            after: { count: created.length, units: created.map(({ id, imei1, imei2, serial_number }) => ({ id, imei1, imei2, serial_number })) },
        });
        return created;
    });
    if (result) res.status(201).json({ message: `${result.length} unit berhasil didaftarkan`, units: result });
});

// Body: any of { imei1, imei2, serial_number, condition_grade, sell_price, notes }
router.put('/units/:id', requirePermission('units.register', { location: unitLocation }), async (req, res) => {
    const result = await withTransaction(res, 'Gagal memperbarui unit', async (conn) => {
        const { before, after } = await stock.updateUnit(conn, req.params.id, req.body);
        const pick = ({ imei1, imei2, serial_number, condition_grade, sell_price, notes }) => ({ imei1, imei2, serial_number, condition_grade, sell_price, notes });
        await logAudit(conn, req, { action: 'update', entity: 'unit', entityId: req.params.id, locationId: before.location_id, before: pick(before), after: pick(after) });
        return after;
    });
    if (result) res.json({ message: 'Unit berhasil diperbarui' });
});

// Body: { status: 'defective' | 'written_off', note }
router.post('/units/:id/write-off', requirePermission('stock.adjust', { location: unitLocation }), async (req, res) => {
    const { status, note } = req.body;
    if (!['defective', 'written_off'].includes(status)) return res.status(400).json({ error: 'status harus defective atau written_off' });
    if (!note || !String(note).trim()) return res.status(400).json({ error: 'Alasan (note) wajib diisi' });

    const result = await withTransaction(res, 'Gagal mengeluarkan unit', async (conn) => {
        const unit = await stock.removeUnit(conn, ctxOf(req), {
            unitId: req.params.id, status, reason: 'write_off', note: String(note).trim(),
        });
        await logAudit(conn, req, { action: status, entity: 'unit', entityId: req.params.id, locationId: unit.location_id, after: { status, note } });
        return unit;
    });
    if (result) res.json({ message: status === 'defective' ? 'Unit ditandai rusak' : 'Unit dihapus dari stok' });
});

module.exports = router;
