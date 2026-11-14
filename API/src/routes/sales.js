const express = require('express');
const pool = require('../db');
const { authenticateToken, requirePermission } = require('../middleware/auth');
const { logAudit } = require('../services/audit');
const stock = require('../services/stock');
const posting = require('../services/posting');
const { nextDocumentNumber } = require('../services/documents');
const { getSetting } = require('../services/settings');
const { DISPLAY_NAME_SQL, ACTIVE_VARIANT_SQL } = require('../services/catalog');
const { AppError, withTransaction } = require('../utils/transaction');
const { ctxOf, parseDate, parseMoney } = require('../utils/request');
const { uuidv7 } = require('../utils/uuid');
const { loadAccess } = require('../services/access');
const { documentDate } = require('../services/documentDate');
const { dateOnly } = require('../services/journal');
const { toCents, fromCents, grossCents, voucherShare, finalizeLines, fitToPaid } = require('../services/pricing');
const { createCustomer } = require('./customers');

// Sales at the counter.
//   - Prices come from the catalog at the location; changing them needs sales.price_override,
//     manual discounts need sales.discount_override. Service / digital lines (repairs, pulsa)
//     take the price typed at the counter.
//   - Prices include PPN (setting tax.prices_include_tax); the tax inside each line is recorded.
//   - Serialized units are sold one line each and need a customer (warranty).
//   - The client may send its own UUID: posting the same id again returns the stored sale, so an
//     offline device can safely retry.
//
// Offline sales (body.offline = true) were made without a connection and are uploaded later.
// They already happened (the customer paid and left), so instead of refusing what no longer
// fits (stock sold elsewhere meanwhile, a price or voucher that changed, a closed shift), the sale
// is stored as it happened and each difference goes to sales.sync_flags.issues for a manager to
// check (GET /?sync=issues, POST /:id/sync-review).
//   - body.priced_on_device = true: the device priced the cart itself (no quote). Its line prices
//     (unit_price) and the discount it gave (discount) are kept, and only cash is accepted.
//   - Otherwise (a sale whose response was lost, queued for retry) the cart is priced like an
//     online sale, with the same relaxed stock / voucher / shift rules.
//   - Still refused: unknown items, an IMEI unit that is no longer in stock (one phone can't be
//     sold twice) and malformed data. The device keeps those and shows the error.
const router = express.Router();

router.use(authenticateToken);

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// An offline sale more than this old is still stored, but flagged.
const OFFLINE_LATE_HOURS = 72;

// Parses a JSON column whether the driver returned text or an object.
const parseJson = (value) => (typeof value === 'string' ? JSON.parse(value) : value);

// ── payment methods ──────────────────────────────────────────────────────────

// Active methods usable at a location; with { all: true } every method, inactive ones included.
const loadPaymentMethods = async (db, locationId, { all = false } = {}) => {
    const [rows] = await db.execute(
        `SELECT pm.id, pm.name, pm.type, pm.requires_reference, pm.location_id, pm.sort_order, pm.is_active, a.code AS account_code
         FROM payment_methods pm JOIN accounts a ON a.id = pm.account_id
         ${all ? '' : 'WHERE pm.is_active = 1 AND (pm.location_id IS NULL OR pm.location_id = ?)'}
         ORDER BY pm.sort_order, pm.id`,
        all ? [] : [locationId || null]
    );
    return rows.map((r) => ({ ...r, requires_reference: !!r.requires_reference, is_active: !!r.is_active }));
};

// ?all=true (settings.manage) lists every method for the settings screen.
router.get('/payment-methods', async (req, res, next) => {
    if (req.query.all === 'true' && req.access.can('settings.manage')) {
        try {
            return res.json({ paymentMethods: await loadPaymentMethods(pool, null, { all: true }) });
        } catch (error) {
            return next(error);
        }
    }
    next();
}, requirePermission('sales.create'), async (req, res) => {
    try {
        res.json({ paymentMethods: await loadPaymentMethods(pool, req.locationId) });
    } catch (error) {
        console.error('Get payment methods error:', error);
        res.status(500).json({ error: 'Gagal mengambil metode pembayaran' });
    }
});

// Body: { name, type, account_code, requires_reference, location_id?, sort_order, is_active }
const savePaymentMethod = async (req, res, id) => {
    const result = await withTransaction(res, 'Gagal menyimpan metode pembayaran', async (conn) => {
        const { name, type, account_code } = req.body;
        if (!name || String(name).trim().length > 50) throw new AppError('Nama metode wajib diisi (maks. 50 karakter)');
        if (!['cash', 'qris', 'ewallet', 'card', 'transfer'].includes(type)) throw new AppError('Tipe harus cash, qris, ewallet, card, atau transfer');
        const [[account]] = await conn.execute("SELECT id FROM accounts WHERE code = ? AND is_postable = 1 AND type = 'asset'", [account_code || '']);
        if (!account) throw new AppError('Akun harus akun aset yang dapat dijurnal (mis. 1-1200)');
        const values = [String(name).trim(), type, account.id, req.body.requires_reference ? 1 : 0,
            req.body.location_id || null, Number(req.body.sort_order) || 0, req.body.is_active === false ? 0 : 1];
        if (id) {
            const [r] = await conn.execute(
                'UPDATE payment_methods SET name = ?, type = ?, account_id = ?, requires_reference = ?, location_id = ?, sort_order = ?, is_active = ? WHERE id = ?',
                [...values, id]
            );
            if (r.affectedRows === 0) throw new AppError('Metode pembayaran tidak ditemukan', 404);
        } else {
            const [r] = await conn.execute(
                'INSERT INTO payment_methods (name, type, account_id, requires_reference, location_id, sort_order, is_active) VALUES (?, ?, ?, ?, ?, ?, ?)',
                values
            );
            id = r.insertId;
        }
        await logAudit(conn, req, { action: 'save', entity: 'payment_method', entityId: id, after: req.body });
        return id;
    });
    if (result) res.status(req.method === 'POST' ? 201 : 200).json({ message: 'Metode pembayaran disimpan', id: result });
};

router.post('/payment-methods', requirePermission('settings.manage'), (req, res) => savePaymentMethod(req, res, null));
router.put('/payment-methods/:pmId', requirePermission('settings.manage'), (req, res) => savePaymentMethod(req, res, Number(req.params.pmId)));

// ── reading sales ────────────────────────────────────────────────────────────

const canViewAt = (access, locationId) =>
    access.can('sales.create', locationId) || access.can('reports.view_location', locationId) || access.can('sales.void', locationId);

const loadSale = async (db, id) => {
    const [[sale]] = await db.execute(
        `SELECT s.*, l.code AS location_code, l.name AS location_name, l.address AS location_address, l.phone AS location_phone,
                u.name AS cashier_name, c.name AS customer_name, c.phone AS customer_phone, v.code AS voucher_code
         FROM sales s
         JOIN locations l ON l.id = s.location_id
         LEFT JOIN users u ON u.id = s.cashier_id
         LEFT JOIN customers c ON c.id = s.customer_id
         LEFT JOIN vouchers v ON v.id = s.voucher_id
         WHERE s.id = ?`,
        [id]
    );
    if (!sale) return null;
    const [lines] = await db.execute(
        `SELECT sl.id, sl.line_type, sl.variant_id, sl.unit_id, sl.description, sl.qty, sl.unit_price, sl.discount,
                sl.tax_rate, sl.tax_amount, sl.line_total, sl.returned_qty, DATE_FORMAT(sl.warranty_until, '%Y-%m-%d') AS warranty_until,
                v.sku, u.imei1, u.imei2, u.serial_number
         FROM sale_lines sl
         LEFT JOIN product_variants v ON v.id = sl.variant_id
         LEFT JOIN product_units u ON u.id = sl.unit_id
         WHERE sl.sale_id = ? ORDER BY sl.sort_order`,
        [id]
    );
    const [payments] = await db.execute(
        `SELECT sp.id, sp.payment_method_id, pm.name AS method_name, pm.type AS method_type, sp.amount, sp.reference
         FROM sale_payments sp JOIN payment_methods pm ON pm.id = sp.payment_method_id WHERE sp.sale_id = ?`,
        [id]
    );
    const [returns] = await db.execute(
        `SELECT r.id, r.number, r.refund_total, r.reason, r.created_at, pm.name AS refund_method, us.name AS created_by_name
         FROM sale_returns r JOIN payment_methods pm ON pm.id = r.refund_method_id LEFT JOIN users us ON us.id = r.created_by
         WHERE r.sale_id = ? ORDER BY r.created_at`,
        [id]
    );
    return { ...sale, sync_flags: sale.sync_flags ? parseJson(sale.sync_flags) : null, lines, payments, returns };
};

// GET /api/sales?location_id=&from=&to=&status=&search=&cashier_id=&sync=
//   sync=offline: only sales uploaded from an offline device; sync=issues: offline sales with
//   differences nobody has checked yet.
router.get('/', async (req, res) => {
    try {
        const locationId = req.query.location_id ? Number(req.query.location_id) : null;
        let query = `
            SELECT s.id, s.number, s.location_id, l.code AS location_code, s.cashier_id, u.name AS cashier_name,
                   s.customer_id, c.name AS customer_name, s.grand_total, s.refunded_total, s.status, s.occurred_at,
                   s.sync_flags IS NOT NULL AS is_offline,
                   COALESCE(JSON_LENGTH(s.sync_flags, '$.issues'), 0) AS sync_issue_count,
                   JSON_EXTRACT(s.sync_flags, '$.reviewed') IS NOT NULL AS sync_reviewed,
                   (SELECT COUNT(*) FROM sale_lines sl WHERE sl.sale_id = s.id) AS line_count,
                   (SELECT GROUP_CONCAT(DISTINCT pm.name) FROM sale_payments sp JOIN payment_methods pm ON pm.id = sp.payment_method_id
                    WHERE sp.sale_id = s.id) AS payment_methods
            FROM sales s
            JOIN locations l ON l.id = s.location_id
            LEFT JOIN users u ON u.id = s.cashier_id
            LEFT JOIN customers c ON c.id = s.customer_id
            WHERE 1 = 1`;
        const params = [];
        if (locationId) {
            if (!canViewAt(req.access, locationId)) return res.status(403).json({ error: 'Akses tidak diizinkan' });
            query += ' AND s.location_id = ?';
            params.push(locationId);
        } else {
            // Every location where the user may see sales; null in any scope means all locations.
            const scopes = ['sales.create', 'reports.view_location', 'sales.void'].map((p) => req.access.locationsFor(p));
            if (!scopes.some((s) => s === null)) {
                const ids = [...new Set(scopes.flat())];
                if (ids.length === 0) return res.json({ sales: [] });
                query += ` AND s.location_id IN (${ids.map(() => '?').join(', ')})`;
                params.push(...ids);
            }
        }
        const from = parseDate(req.query.from);
        const to = parseDate(req.query.to);
        if (from) { query += ' AND s.occurred_at >= ?'; params.push(from); }
        if (to) { query += ' AND s.occurred_at < DATE_ADD(?, INTERVAL 1 DAY)'; params.push(to); }
        if (['completed', 'voided', 'partially_returned', 'returned'].includes(req.query.status)) { query += ' AND s.status = ?'; params.push(req.query.status); }
        if (req.query.cashier_id) { query += ' AND s.cashier_id = ?'; params.push(Number(req.query.cashier_id)); }
        if (req.query.sync === 'offline') query += ' AND s.sync_flags IS NOT NULL';
        if (req.query.sync === 'issues') {
            query += " AND JSON_LENGTH(s.sync_flags, '$.issues') > 0 AND JSON_EXTRACT(s.sync_flags, '$.reviewed') IS NULL";
        }
        if (req.query.search) {
            query += ' AND (s.number LIKE ? OR c.name LIKE ? OR c.phone LIKE ?)';
            params.push(`%${req.query.search}%`, `%${req.query.search}%`, `%${req.query.search}%`);
        }
        query += ' ORDER BY s.occurred_at DESC LIMIT 200';
        const [sales] = await pool.execute(query, params);
        res.json({
            sales: sales.map((s) => ({
                ...s,
                line_count: Number(s.line_count),
                is_offline: !!Number(s.is_offline),
                sync_issue_count: Number(s.sync_issue_count),
                sync_reviewed: !!Number(s.sync_reviewed),
            })),
        });
    } catch (error) {
        console.error('Get sales error:', error);
        res.status(500).json({ error: 'Gagal mengambil data penjualan' });
    }
});

router.get('/:id', async (req, res) => {
    try {
        const sale = await loadSale(pool, req.params.id);
        if (!sale) return res.status(404).json({ error: 'Penjualan tidak ditemukan' });
        if (!canViewAt(req.access, sale.location_id)) return res.status(403).json({ error: 'Akses tidak diizinkan' });
        res.json({ sale });
    } catch (error) {
        console.error('Get sale error:', error);
        res.status(500).json({ error: 'Gagal mengambil data penjualan' });
    }
});

// ── creating a sale ──────────────────────────────────────────────────────────

const findVoucher = async (conn, code) => {
    const [[voucher]] = await conn.execute(
        `SELECT * FROM vouchers WHERE UPPER(code) = ? AND is_active = 1
           AND (valid_from IS NULL OR valid_from <= CURDATE()) AND (valid_to IS NULL OR valid_to >= CURDATE())`,
        [String(code).trim().toUpperCase()]
    );
    if (!voucher) throw new AppError('Kode voucher tidak valid atau sudah kedaluwarsa');
    return voucher;
};

// Offline sales: the voucher as it was on the day of the sale. A code that is unknown, inactive or
// outside its dates then is noted in `issues` instead of refusing the sale.
const findVoucherForOfflineSale = async (conn, code, occurredAt, issues) => {
    const day = occurredAt.toISOString().slice(0, 10);
    const [[voucher]] = await conn.execute(
        `SELECT *, (is_active = 1 AND (valid_from IS NULL OR valid_from <= ?) AND (valid_to IS NULL OR valid_to >= ?)) AS valid_then
         FROM vouchers WHERE UPPER(code) = ?`,
        [day, day, String(code).trim().toUpperCase()]
    );
    if (!voucher) {
        issues.push({ code: 'voucher_unknown', voucher_code: String(code).trim().toUpperCase() });
        return null;
    }
    if (!Number(voucher.valid_then)) issues.push({ code: 'voucher_invalid', voucher_code: voucher.code });
    return voucher;
};

// Builds the priced lines (not yet stored). Throws AppError on anything the caller may not do.
// With { offline: true }, rules about what the cashier may do (price, discount, inactive items)
// are noted in `issues` instead, because the sale already happened.
const priceLines = async (conn, req, locationId, inputs, taxSettings, { offline = false, issues = [] } = {}) => {
    if (!Array.isArray(inputs) || inputs.length === 0) throw new AppError('Keranjang kosong');
    if (inputs.length > 200) throw new AppError('Maksimal 200 baris per transaksi');
    const lines = [];
    const usedUnits = new Set();

    for (const input of inputs) {
        const [[v]] = await conn.execute(
            `SELECT v.id, ${DISPLAY_NAME_SQL} AS name, v.base_price, v.min_price, v.cost_price, COALESCE(sl.sell_price, v.base_price) AS price,
                    p.kind, p.is_serialized, p.warranty_months, p.category_id, p.tax_rate_id, (${ACTIVE_VARIANT_SQL}) AS active
             FROM product_variants v JOIN products p ON p.id = v.product_id
             LEFT JOIN stock_levels sl ON sl.variant_id = v.id AND sl.location_id = ?
             WHERE v.id = ?`,
            [locationId, Number(input.variant_id)]
        );
        if (!v || (!offline && !Number(v.active))) throw new AppError(`Barang ${input.variant_id} tidak ditemukan atau tidak aktif`, 404);
        if (!Number(v.active)) issues.push({ code: 'inactive_product', variant_id: v.id, name: v.name });

        let taxRate = taxSettings.defaultRate;
        if (v.tax_rate_id) {
            const [[rate]] = await conn.execute('SELECT rate FROM tax_rates WHERE id = ? AND is_active = 1', [v.tax_rate_id]);
            taxRate = rate ? Number(rate.rate) : 0;
        }

        const lineDiscount = input.discount === undefined || input.discount === null || input.discount === '' ? 0 : parseMoney(input.discount);
        if (Number.isNaN(lineDiscount)) throw new AppError('Diskon tidak valid');
        if (lineDiscount > 0 && !req.access.can('sales.discount_override', locationId)) {
            if (!offline) throw new AppError('Anda tidak memiliki izin memberi diskon manual', 403);
            issues.push({ code: 'manual_discount', variant_id: v.id, name: v.name, amount: lineDiscount });
        }

        const base = {
            variantId: v.id, name: v.name, kind: v.kind, categoryId: v.category_id, taxRate,
            warrantyMonths: v.warranty_months, catalogPrice: Number(v.price), minPrice: v.min_price === null ? null : Number(v.min_price),
            // Cost of a pulsa / digital item, booked from the pulsa deposit (goods use their stock cost).
            costPrice: v.cost_price === null ? 0 : Number(v.cost_price),
        };

        // Price typed at the counter: free for services/digital (repairs, pulsa); goods need permission.
        const typed = input.unit_price === undefined || input.unit_price === null || input.unit_price === '' ? null : parseMoney(input.unit_price);
        if (Number.isNaN(typed)) throw new AppError('Harga tidak valid');
        const checkGoodsPrice = (price, catalogPrice) => {
            if (price === catalogPrice) return;
            // Offline: the price the customer paid stands; note that it isn't today's price.
            if (offline) {
                issues.push({ code: 'price_changed', variant_id: v.id, name: v.name, charged: price, catalog: catalogPrice });
                return;
            }
            if (!req.access.can('sales.price_override', locationId)) {
                throw new AppError(`Anda tidak memiliki izin mengubah harga "${v.name}"`, 403);
            }
        };
        if (typed !== null && base.minPrice !== null && typed < base.minPrice && v.kind === 'goods' && !req.access.can('sales.price_override', locationId)) {
            if (!offline) throw new AppError(`Harga "${v.name}" di bawah harga minimum`, 403);
            issues.push({ code: 'below_min_price', variant_id: v.id, name: v.name, charged: typed, min: base.minPrice });
        }

        if (v.kind !== 'goods') {
            const qty = Number(input.qty ?? 1);
            if (!Number.isInteger(qty) || qty <= 0) throw new AppError('Jumlah harus bilangan bulat > 0');
            const price = typed ?? base.catalogPrice;
            const description = input.description ? `${v.name} - ${String(input.description).trim()}`.slice(0, 200) : v.name;
            lines.push({ ...base, description, qty, unitPrice: price, discount: lineDiscount, unitIds: [] });
        } else if (v.is_serialized) {
            const unitIds = Array.isArray(input.unit_ids) ? input.unit_ids.map(String) : [];
            if (unitIds.length === 0) throw new AppError(`Pilih unit (IMEI) untuk "${v.name}"`);
            for (const unitId of unitIds) {
                if (usedUnits.has(unitId)) throw new AppError('Unit yang sama ada lebih dari sekali di keranjang');
                usedUnits.add(unitId);
                const [[unit]] = await conn.execute(
                    "SELECT id, imei1, serial_number, sell_price FROM product_units WHERE id = ? AND variant_id = ? AND location_id = ? AND status = 'in_stock'",
                    [unitId, v.id, locationId]
                );
                if (!unit) throw new AppError(`Unit untuk "${v.name}" tidak tersedia di lokasi ini`, 409);
                const unitCatalogPrice = unit.sell_price === null ? base.catalogPrice : Number(unit.sell_price);
                const price = typed ?? unitCatalogPrice;
                checkGoodsPrice(price, unitCatalogPrice);
                lines.push({
                    ...base, description: `${v.name} (${unit.imei1 || unit.serial_number || 'tanpa IMEI'})`.slice(0, 200),
                    qty: 1, unitPrice: price, discount: lineDiscount, unitIds: [unit.id], serialized: true,
                });
            }
        } else {
            const qty = Number(input.qty);
            if (!Number.isInteger(qty) || qty <= 0) throw new AppError('Jumlah harus bilangan bulat > 0');
            const price = typed ?? base.catalogPrice;
            checkGoodsPrice(price, base.catalogPrice);
            lines.push({ ...base, description: v.name.slice(0, 200), qty, unitPrice: price, discount: lineDiscount, unitIds: [] });
        }
    }

    for (const line of lines) {
        if (toCents(line.discount) > toCents(line.qty * line.unitPrice)) throw new AppError(`Diskon "${line.name}" melebihi harga`);
    }
    return lines;
};

const loadTaxSettings = async (conn) => {
    const taxSettings = {
        inclusive: (await getSetting(conn, 'tax.prices_include_tax', true)) !== false,
        defaultRate: 0,
    };
    const defaultRateId = await getSetting(conn, 'tax.default_rate_id', null);
    if (defaultRateId) {
        const [[rate]] = await conn.execute('SELECT rate FROM tax_rates WHERE id = ? AND is_active = 1', [defaultRateId]);
        taxSettings.defaultRate = rate ? Number(rate.rate) : 0;
    }
    return taxSettings;
};

// Prices a cart exactly like POST / would (same permission checks, voucher and PPN), without
// saving anything. Body: { location_id, lines, voucher_code?, discount? }
router.post('/quote', requirePermission('sales.create', { location: (req) => req.body.location_id }), async (req, res) => {
    if (!req.locationId) return res.status(400).json({ error: 'location_id wajib diisi' });
    const conn = await pool.getConnection();
    try {
        const taxSettings = await loadTaxSettings(conn);
        const lines = await priceLines(conn, req, req.locationId, req.body.lines, taxSettings);
        const voucher = req.body.voucher_code ? await findVoucher(conn, req.body.voucher_code) : null;
        const saleDiscount = req.body.discount ? parseMoney(req.body.discount) : 0;
        if (Number.isNaN(saleDiscount)) throw new AppError('Diskon tidak valid');
        if (saleDiscount > 0 && !req.access.can('sales.discount_override', req.locationId)) throw new AppError('Anda tidak memiliki izin memberi diskon manual', 403);
        const { voucherDiscount } = finalizeLines(lines, { voucher, saleDiscount, taxSettings });
        const sum = (pick) => fromCents(lines.reduce((s, l) => s + toCents(pick(l)), 0));
        res.json({
            subtotal: sum((l) => l.qty * l.unitPrice),
            discount_total: sum((l) => l.discount),
            voucher_discount: voucherDiscount,
            tax_total: sum((l) => l.taxAmount),
            grand_total: sum((l) => l.lineTotal),
            prices_include_tax: taxSettings.inclusive,
            requires_customer: lines.some((l) => l.serialized),
            lines: lines.map((l) => ({
                variant_id: l.variantId, description: l.description, qty: l.qty, unit_price: l.unitPrice,
                discount: l.discount, tax_amount: l.taxAmount, line_total: l.lineTotal,
            })),
        });
    } catch (error) {
        if (error instanceof AppError) return res.status(error.status).json({ error: error.message });
        console.error('Quote error:', error);
        res.status(500).json({ error: 'Gagal menghitung total' });
    } finally {
        conn.release();
    }
});

// Body: { id?, number?, location_id, cash_session_id?, customer_id? | customer: {name, phone, ...},
//         occurred_at?, note?, voucher_code?, discount?,
//         lines: [{ variant_id, qty?, unit_ids?, unit_price?, discount?, description? }],
//         payments: [{ payment_method_id, amount, reference? }],
//         offline?, priced_on_device?, cashier_id?, charged_total? }   (offline sales, see the top)
router.post('/', requirePermission('sales.create', { location: (req) => req.body.location_id }), async (req, res) => {
    if (!req.locationId) return res.status(400).json({ error: 'location_id wajib diisi' });
    const clientId = req.body.id && UUID.test(String(req.body.id)) ? String(req.body.id).toLowerCase() : null;

    if (clientId) {
        const existing = await loadSale(pool, clientId);
        if (existing) return res.status(200).json({ message: 'Penjualan sudah tercatat', replay: true, sale: existing });
    }

    const offline = req.body.offline === true;
    const pricedOnDevice = offline && req.body.priced_on_device === true;

    const touchedVariants = new Set();
    const result = await withTransaction(res, 'Gagal menyimpan penjualan', async (conn) => {
        const locationId = req.locationId;
        const ctx = ctxOf(req);
        // What an offline sale did that an online one may not (stored in sales.sync_flags).
        const issues = [];
        let taxSettings = await loadTaxSettings(conn);
        if (pricedOnDevice && !taxSettings.inclusive) {
            // The device charged its shelf prices as they are; read them as including PPN.
            taxSettings = { ...taxSettings, inclusive: true };
            issues.push({ code: 'tax_assumed_inclusive' });
        }

        // When it happened
        let occurredAt = req.body.occurred_at ? new Date(req.body.occurred_at) : new Date();
        if (Number.isNaN(occurredAt.getTime())) throw new AppError('occurred_at tidak valid');
        if (offline) {
            const now = Date.now();
            if (occurredAt.getTime() > now + 5 * 60 * 1000) {
                // The device clock is ahead; a sale can't be dated in the future.
                issues.push({ code: 'clock_ahead', reported: occurredAt.toISOString() });
                occurredAt = new Date(now);
            }
            const hours = Math.floor((now - occurredAt.getTime()) / 3600000);
            if (hours > OFFLINE_LATE_HOURS) issues.push({ code: 'late', hours });
        } else if (occurredAt.getTime() > Date.now() + 5 * 60 * 1000) {
            throw new AppError('Waktu penjualan tidak boleh di masa depan');
        }
        // The sale's stock movements carry its time; its number its date.
        ctx.occurredAt = occurredAt;

        // Who sold it: an offline sale may be uploaded after another cashier logged in on the device.
        let cashierId = req.user.id;
        const sellerId = Number(req.body.cashier_id);
        if (offline && req.body.cashier_id !== undefined && req.body.cashier_id !== null && sellerId !== req.user.id) {
            const [[seller]] = Number.isInteger(sellerId) ? await conn.execute('SELECT id FROM users WHERE id = ?', [sellerId]) : [[]];
            if (seller && (await loadAccess(conn, seller.id)).can('sales.create', locationId)) cashierId = seller.id;
            else issues.push({ code: 'cashier_unverified', cashier_id: req.body.cashier_id });
        }

        // Shift (optional). An offline sale still belongs to the shift it was made in, even if that
        // shift was closed before the sale arrived.
        let sessionId = null;
        if (req.body.cash_session_id) {
            const [[session]] = await conn.execute('SELECT * FROM cash_sessions WHERE id = ? FOR UPDATE', [req.body.cash_session_id]);
            const here = session && session.location_id === locationId;
            if (here && session.status === 'open') {
                sessionId = session.id;
            } else if (offline && here) {
                sessionId = session.id;
                issues.push({ code: 'shift_closed', cash_session_id: session.id });
            } else if (offline) {
                issues.push({ code: 'shift_missing', cash_session_id: String(req.body.cash_session_id) });
            } else {
                throw new AppError('Shift tidak ditemukan atau sudah ditutup', 409);
            }
        }

        const priced = await priceLines(conn, req, locationId, req.body.lines, taxSettings, { offline, issues });

        // Customer (required for serialized units)
        let customerId = null;
        if (req.body.customer_id) {
            const [[c]] = await conn.execute('SELECT id FROM customers WHERE id = ? AND deleted_at IS NULL', [req.body.customer_id]);
            if (!c) throw new AppError('Pelanggan tidak ditemukan', 404);
            customerId = c.id;
        } else if (req.body.customer && (req.body.customer.name || req.body.customer.phone)) {
            customerId = (await createCustomer(conn, req, req.body.customer)).customer.id;
        }
        if (!customerId && priced.some((l) => l.serialized)) throw new AppError('Data pelanggan wajib diisi untuk penjualan HP / barang ber-IMEI');

        // Payments: change can only come out of cash. Offline, a method switched off since is still
        // the one that was used.
        const methods = await loadPaymentMethods(conn, locationId, { all: offline });
        const payments = (Array.isArray(req.body.payments) ? req.body.payments : []).map((p) => {
            const method = methods.find((m) => m.id === Number(p.payment_method_id) && (m.location_id === null || m.location_id === locationId));
            if (!method) throw new AppError('Metode pembayaran tidak tersedia di lokasi ini');
            if (!method.is_active) issues.push({ code: 'payment_method_inactive', name: method.name });
            const amount = parseMoney(p.amount);
            if (Number.isNaN(amount) || amount <= 0) throw new AppError('Jumlah pembayaran tidak valid');
            if (method.requires_reference && !p.reference) throw new AppError(`Nomor referensi wajib diisi untuk ${method.name}`);
            return { method, amount, reference: p.reference ? String(p.reference).slice(0, 100) : null };
        });
        if (pricedOnDevice && payments.some((p) => p.method.type !== 'cash')) throw new AppError('Penjualan offline hanya bisa dibayar tunai');
        const paidCents = payments.reduce((s, p) => s + toCents(p.amount), 0);

        // Discounts
        const voucherCode = req.body.voucher_code ? String(req.body.voucher_code).trim() : '';
        let voucher = null; // linked to the sale
        if (voucherCode) {
            voucher = offline ? await findVoucherForOfflineSale(conn, voucherCode, occurredAt, issues) : await findVoucher(conn, voucherCode);
        }
        const bodyDiscount = req.body.discount === undefined || req.body.discount === null || req.body.discount === '' ? 0 : parseMoney(req.body.discount);
        if (Number.isNaN(bodyDiscount)) throw new AppError('Diskon tidak valid');
        let applyVoucher = null; // computed by the voucher's rules
        if (pricedOnDevice) {
            // The device already took the discount off (voucher included): keep what it gave and
            // note when the voucher's rules give something else.
            if (voucher) {
                const share = voucherShare(voucher, priced, grossCents(priced));
                const expectedCents = share ? share.cents : 0;
                if (!share) issues.push({ code: 'voucher_not_applicable', voucher_code: voucher.code });
                if (Math.abs(expectedCents - toCents(bodyDiscount)) > 100) {
                    issues.push({ code: 'discount_differs', charged: bodyDiscount, expected: fromCents(expectedCents) });
                }
            } else if (bodyDiscount > 0 && !voucherCode) {
                issues.push({ code: 'manual_discount', amount: bodyDiscount });
            }
        } else {
            if (bodyDiscount > 0 && !req.access.can('sales.discount_override', locationId)) {
                if (!offline) throw new AppError('Anda tidak memiliki izin memberi diskon manual', 403);
                issues.push({ code: 'manual_discount', amount: bodyDiscount });
            }
            if (voucher) {
                if (voucherShare(voucher, priced, grossCents(priced))) applyVoucher = voucher;
                else if (offline) issues.push({ code: 'voucher_not_applicable', voucher_code: voucher.code });
                else throw new AppError('Voucher tidak berlaku untuk barang di keranjang');
            }
        }
        const pricing = { voucher: applyVoucher, saleDiscount: bodyDiscount, taxSettings };
        let lines = priced;
        if (offline) {
            // Paid less than the cart now comes to: what was received stands, the rest is discount.
            const fitted = fitToPaid(priced, pricing, paidCents);
            lines = fitted.lines;
            if (fitted.extraCents > 0) issues.push({ code: 'underpaid_adjusted', amount: fromCents(fitted.extraCents) });
        } else {
            finalizeLines(lines, pricing);
        }

        const subtotalCents = lines.reduce((s, l) => s + toCents(l.qty * l.unitPrice), 0);
        const grandCents = lines.reduce((s, l) => s + toCents(l.lineTotal), 0);
        const taxCents = lines.reduce((s, l) => s + toCents(l.taxAmount), 0);
        const discountCents = lines.reduce((s, l) => s + toCents(l.discount), 0);

        if (paidCents < grandCents) throw new AppError(`Pembayaran kurang ${fromCents(grandCents - paidCents)}`);
        const changeCents = paidCents - grandCents;
        const cashCents = payments.filter((p) => p.method.type === 'cash').reduce((s, p) => s + toCents(p.amount), 0);
        if (changeCents > cashCents) throw new AppError('Kelebihan bayar hanya boleh dari pembayaran tunai (kembalian)');

        if (offline && req.body.charged_total !== undefined && req.body.charged_total !== null) {
            const charged = parseMoney(req.body.charged_total);
            if (!Number.isNaN(charged) && Math.abs(toCents(charged) - grandCents) > 100) {
                issues.push({ code: 'total_differs', charged, recorded: fromCents(grandCents) });
            }
        }

        // Store
        const id = clientId || uuidv7();
        let number = req.body.number ? String(req.body.number).trim().slice(0, 40) : null;
        if (!number) number = await nextDocumentNumber(conn, 'INV', locationId, occurredAt);

        try {
            await conn.execute(
                `INSERT INTO sales (id, number, location_id, device_id, cash_session_id, cashier_id, customer_id, voucher_id,
                                    subtotal, discount_total, tax_total, grand_total, paid_total, change_total, note, occurred_at)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
                [id, number, locationId, req.deviceId || null, sessionId, cashierId, customerId, voucher ? voucher.id : null,
                    fromCents(subtotalCents), fromCents(discountCents), fromCents(taxCents), fromCents(grandCents),
                    fromCents(paidCents), fromCents(changeCents), req.body.note || null, occurredAt]
            );
        } catch (error) {
            if (error.code === 'ER_DUP_ENTRY') throw new AppError('Nomor transaksi sudah dipakai', 409);
            throw error;
        }

        for (const [index, line] of lines.entries()) {
            const lineId = uuidv7();
            let unitCost = 0;
            let warrantyUntil = null;
            const common = { refType: 'sale', refId: id, note: number };
            if (line.kind === 'goods' && line.serialized) {
                const unit = await stock.removeUnit(conn, ctx, {
                    unitId: line.unitIds[0], status: 'sold', reason: 'sale', expectedLocationId: locationId, saleLineId: lineId, ...common,
                });
                unitCost = Number(unit.unit_cost);
                if (line.warrantyMonths > 0) {
                    const until = new Date(occurredAt);
                    until.setMonth(until.getMonth() + line.warrantyMonths);
                    warrantyUntil = until;
                    await conn.execute('UPDATE product_units SET warranty_until = ? WHERE id = ?', [until, unit.id]);
                }
            } else if (line.kind === 'goods') {
                // Offline: the goods are gone even if the system thinks there were none left; the
                // shelf count is off somewhere and the next opname or receipt corrects it.
                const moved = await stock.adjustQuantity(conn, ctx, {
                    locationId, variantId: line.variantId, qtyChange: -line.qty, reason: 'sale', allowNegative: offline, ...common,
                });
                unitCost = moved.unitCost;
                if (moved.qty < 0) {
                    const known = issues.find((i) => i.code === 'negative_stock' && i.variant_id === line.variantId);
                    if (known) known.qty_after = moved.qty;
                    else issues.push({ code: 'negative_stock', variant_id: line.variantId, name: line.name, qty_after: moved.qty });
                }
            }
            if (line.kind === 'digital') unitCost = line.costPrice;
            if (line.kind === 'goods') touchedVariants.add(line.variantId);

            await conn.execute(
                `INSERT INTO sale_lines (id, sale_id, line_type, variant_id, unit_id, description, qty, unit_price, discount,
                                         tax_rate, tax_amount, line_total, unit_cost, warranty_until, sort_order)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
                [lineId, id, line.kind, line.variantId, line.unitIds[0] || null, line.description, line.qty, line.unitPrice,
                    line.discount, line.taxRate, line.taxAmount, line.lineTotal, unitCost, warrantyUntil, index]
            );
        }
        for (const p of payments) {
            await conn.execute('INSERT INTO sale_payments (id, sale_id, payment_method_id, amount, reference) VALUES (?, ?, ?, ?, ?)',
                [uuidv7(), id, p.method.id, p.amount, p.reference]);
        }

        if (offline) {
            const syncFlags = {
                offline: true,
                priced_on_device: pricedOnDevice,
                ...(cashierId !== req.user.id ? { uploaded_by: req.user.id, uploaded_by_name: req.user.name } : {}),
                issues,
            };
            await conn.execute('UPDATE sales SET sync_flags = ? WHERE id = ?', [JSON.stringify(syncFlags), id]);
        }

        await posting.postSale(conn, ctx, id);
        await logAudit(conn, req, {
            action: 'create', entity: 'sale', entityId: id, locationId,
            after: { number, grand_total: fromCents(grandCents), ...(offline ? { offline: true, issues: issues.map((i) => i.code) } : {}) },
        });
        return loadSale(conn, id);
    });

    if (result) {
        const io = req.app.get('io');
        if (io) {
            io.to(`branch-${result.location_id}`).emit('sale-created', { id: result.id, number: result.number, grand_total: result.grand_total });
            io.to('branch-0').emit('sale-created', { id: result.id, number: result.number, grand_total: result.grand_total, location_id: result.location_id });
            if (touchedVariants.size > 0) {
                const change = { location_id: result.location_id, variant_ids: [...touchedVariants] };
                io.to(`branch-${result.location_id}`).to('branch-0').emit('stock-changed', change);
            }
        }
        res.status(201).json({ message: 'Penjualan tersimpan', sale: result });
    }
});

// ── voids & returns ──────────────────────────────────────────────────────────

const saleLocation = async (req) => {
    const [[row]] = await pool.execute('SELECT location_id FROM sales WHERE id = ?', [req.params.id]);
    return row ? row.location_id : -1;
};

// Puts a sold line back: quantity goods to stock at their sale cost, units to stock or 'defective'.
const restoreLine = async (conn, ctx, { line, qty, locationId, restock, refType, refId, note }) => {
    if (line.line_type !== 'goods') return;
    if (line.unit_id) {
        await stock.returnSoldUnit(conn, ctx, { unitId: line.unit_id, locationId, defective: !restock, refType, refId, note });
    } else if (restock) {
        await stock.adjustQuantity(conn, ctx, {
            locationId, variantId: line.variant_id, qtyChange: qty, unitCost: Number(line.unit_cost),
            reason: 'sale_return', refType, refId, note,
        });
    }
};

// Body: { reason }. Cancels a whole sale that has no returns: stock comes back and the journal is reversed.
router.post('/:id/void', requirePermission('sales.void', { location: saleLocation }), async (req, res) => {
    const reason = String(req.body.reason || '').trim();
    if (!reason) return res.status(400).json({ error: 'Alasan pembatalan wajib diisi' });

    const result = await withTransaction(res, 'Gagal membatalkan penjualan', async (conn) => {
        const [[sale]] = await conn.execute('SELECT * FROM sales WHERE id = ? FOR UPDATE', [req.params.id]);
        if (!sale) throw new AppError('Penjualan tidak ditemukan', 404);
        if (sale.status !== 'completed') throw new AppError('Hanya penjualan tanpa retur yang dapat dibatalkan');
        const ctx = ctxOf(req);
        const [lines] = await conn.execute('SELECT * FROM sale_lines WHERE sale_id = ?', [sale.id]);
        for (const line of lines) {
            await restoreLine(conn, ctx, { line, qty: line.qty, locationId: sale.location_id, restock: true, refType: 'sale_void', refId: sale.id, note: `Batal ${sale.number}` });
        }
        await posting.voidSaleJournal(conn, ctx, sale, reason);
        await conn.execute("UPDATE sales SET status = 'voided', void_reason = ?, voided_by = ?, voided_at = NOW(3) WHERE id = ?", [reason, req.user.id, sale.id]);
        await logAudit(conn, req, { action: 'void', entity: 'sale', entityId: sale.id, locationId: sale.location_id, after: { reason } });
        return loadSale(conn, sale.id);
    });
    if (result) res.json({ message: 'Penjualan dibatalkan', sale: result });
});

// Body: { note? }. Marks the differences on an offline sale (sync_flags.issues) as checked.
router.post('/:id/sync-review', requirePermission('sales.void', { location: saleLocation }), async (req, res) => {
    const result = await withTransaction(res, 'Gagal menandai penjualan', async (conn) => {
        const [[sale]] = await conn.execute('SELECT id, location_id, sync_flags FROM sales WHERE id = ? FOR UPDATE', [req.params.id]);
        if (!sale) throw new AppError('Penjualan tidak ditemukan', 404);
        if (!sale.sync_flags) throw new AppError('Penjualan ini bukan penjualan offline');
        const flags = parseJson(sale.sync_flags);
        if (flags.reviewed) throw new AppError('Penjualan ini sudah ditandai dicek', 409);
        const note = String(req.body.note || '').trim().slice(0, 500) || null;
        flags.reviewed = { by: req.user.id, by_name: req.user.name, at: new Date().toISOString(), note };
        await conn.execute('UPDATE sales SET sync_flags = ? WHERE id = ?', [JSON.stringify(flags), sale.id]);
        await logAudit(conn, req, { action: 'sync_review', entity: 'sale', entityId: sale.id, locationId: sale.location_id, after: { note } });
        return loadSale(conn, sale.id);
    });
    if (result) res.json({ message: 'Penjualan offline ditandai sudah dicek', sale: result });
});

// Body: { lines: [{ sale_line_id, qty, restock? }], refund_method_id, reason, cash_session_id?, date? }
// restock false = returned defective (not sellable). Refunds are proportional to what was paid per line.
// date (YYYY-MM-DD, default today): when the goods came back; not before the sale, not in a closed period.
router.post('/:id/returns', requirePermission('sales.void', { location: saleLocation }), async (req, res) => {
    const reason = String(req.body.reason || '').trim();
    if (!reason) return res.status(400).json({ error: 'Alasan retur wajib diisi' });
    if (!Array.isArray(req.body.lines) || req.body.lines.length === 0) return res.status(400).json({ error: 'Pilih barang yang diretur' });

    const result = await withTransaction(res, 'Gagal mencatat retur', async (conn) => {
        const [[sale]] = await conn.execute('SELECT * FROM sales WHERE id = ? FOR UPDATE', [req.params.id]);
        if (!sale) throw new AppError('Penjualan tidak ditemukan', 404);
        if (!['completed', 'partially_returned'].includes(sale.status)) throw new AppError('Penjualan ini tidak dapat diretur');

        const methods = await loadPaymentMethods(conn, sale.location_id);
        const method = methods.find((m) => m.id === Number(req.body.refund_method_id));
        if (!method) throw new AppError('Metode pengembalian dana tidak tersedia');

        let sessionId = null;
        if (req.body.cash_session_id) {
            const [[session]] = await conn.execute('SELECT * FROM cash_sessions WHERE id = ?', [req.body.cash_session_id]);
            if (!session || session.status !== 'open' || session.location_id !== sale.location_id) throw new AppError('Shift tidak ditemukan atau sudah ditutup', 409);
            sessionId = session.id;
        }

        const doc = await documentDate(conn, req.body.date, {
            label: 'Tanggal retur', notBefore: dateOnly(sale.occurred_at), notBeforeLabel: 'tanggal penjualan',
        });
        const [saleLines] = await conn.execute('SELECT * FROM sale_lines WHERE sale_id = ? FOR UPDATE', [sale.id]);
        const id = uuidv7();
        const number = await nextDocumentNumber(conn, 'RT', sale.location_id, doc.date);
        const ctx = { ...ctxOf(req), occurredAt: doc.at };
        const returned = [];
        const seen = new Set();
        for (const input of req.body.lines) {
            const line = saleLines.find((l) => l.id === String(input.sale_line_id));
            if (!line) throw new AppError('Baris penjualan tidak ditemukan');
            if (seen.has(line.id)) throw new AppError('Baris yang sama diretur lebih dari sekali');
            seen.add(line.id);
            const qty = Number(input.qty ?? line.qty - line.returned_qty);
            if (!Number.isInteger(qty) || qty <= 0 || qty > line.qty - line.returned_qty) {
                throw new AppError(`Jumlah retur "${line.description}" maksimal ${line.qty - line.returned_qty}`);
            }
            const amountCents = Math.round(toCents(line.line_total) * qty / line.qty);
            const taxCents = Math.round(toCents(line.tax_amount) * qty / line.qty);
            const restock = input.restock !== false;
            await restoreLine(conn, ctx, { line, qty, locationId: sale.location_id, restock, refType: 'sale_return', refId: id, note: `${number} atas ${sale.number}` });
            await conn.execute('UPDATE sale_lines SET returned_qty = returned_qty + ? WHERE id = ?', [qty, line.id]);
            returned.push({ line, qty, amountCents, taxCents, restock });
        }

        const refundCents = returned.reduce((s, r) => s + r.amountCents, 0);
        const taxCents = returned.reduce((s, r) => s + r.taxCents, 0);
        await conn.execute(
            `INSERT INTO sale_returns (id, number, sale_id, location_id, cash_session_id, refund_method_id, refund_total, tax_total, reason, created_by, created_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [id, number, sale.id, sale.location_id, sessionId, method.id, fromCents(refundCents), fromCents(taxCents), reason, req.user.id, doc.at]
        );
        for (const r of returned) {
            await conn.execute(
                'INSERT INTO sale_return_lines (id, return_id, sale_line_id, qty, amount, tax_amount, unit_cost, restock) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
                [uuidv7(), id, r.line.id, r.qty, fromCents(r.amountCents), fromCents(r.taxCents), r.line.unit_cost, r.restock ? 1 : 0]
            );
        }

        const [[left]] = await conn.execute('SELECT COALESCE(SUM(qty - returned_qty), 0) AS remaining FROM sale_lines WHERE sale_id = ?', [sale.id]);
        await conn.execute(
            'UPDATE sales SET refunded_total = refunded_total + ?, status = ? WHERE id = ?',
            [fromCents(refundCents), Number(left.remaining) === 0 ? 'returned' : 'partially_returned', sale.id]
        );
        await posting.postSaleReturn(conn, ctx, id);
        await logAudit(conn, req, { action: 'return', entity: 'sale', entityId: sale.id, locationId: sale.location_id, after: { return_id: id, number, refund: fromCents(refundCents) } });
        return { returnId: id, number, refund: fromCents(refundCents), sale: await loadSale(conn, sale.id) };
    });
    if (result) res.status(201).json({ message: `Retur ${result.number} dicatat`, ...result });
});

module.exports = router;
