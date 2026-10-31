const express = require('express');
const pool = require('../db');
const { authenticateToken, requirePermission } = require('../middleware/auth');
const { uploadProduct, deleteFile, validateUploadedImage } = require('../utils/upload');
const { logAudit } = require('../services/audit');
const { ON_HAND_SQL, AVG_COST_SQL, canSeeCost, assignGeneratedSku } = require('../services/catalog');

const router = express.Router();

router.use(authenticateToken);

const KINDS = ['goods', 'service', 'digital'];
const SERIAL_TYPES = ['imei', 'imei_dual', 'serial'];
const SKU = /^[A-Za-z0-9\-_.]{2,50}$/;

const badRequest = (res, error) => res.status(400).json({ error });

const parseMoney = (value) => {
    if (value === undefined || value === null || value === '') return null;
    const n = Number(value);
    return Number.isFinite(n) && n >= 0 ? Math.round(n * 100) / 100 : NaN;
};

const toBool = (value) => value === true || value === 1 || value === '1' || value === 'true';

// ── brands ───────────────────────────────────────────────────────────────────

router.get('/brands', requirePermission('catalog.view'), async (req, res) => {
    try {
        const [brands] = await pool.execute('SELECT id, name, created_at, updated_at FROM brands WHERE deleted_at IS NULL ORDER BY name');
        res.json({ brands });
    } catch (error) {
        console.error('Get brands error:', error);
        res.status(500).json({ error: 'Gagal mengambil data merek' });
    }
});

router.post('/brands', requirePermission('catalog.manage'), async (req, res) => {
    const name = typeof req.body.name === 'string' ? req.body.name.trim() : '';
    if (name.length < 1 || name.length > 100) return badRequest(res, 'Nama merek wajib diisi (maks. 100 karakter)');
    try {
        const [result] = await pool.execute('INSERT INTO brands (name) VALUES (?)', [name]);
        await logAudit(pool, req, { action: 'create', entity: 'brand', entityId: result.insertId, after: { name } });
        res.status(201).json({ message: 'Merek berhasil dibuat', brand: { id: result.insertId, name } });
    } catch (error) {
        if (error.code === 'ER_DUP_ENTRY') return badRequest(res, 'Nama merek sudah digunakan');
        console.error('Create brand error:', error);
        res.status(500).json({ error: 'Gagal membuat merek' });
    }
});

router.put('/brands/:id', requirePermission('catalog.manage'), async (req, res) => {
    const name = typeof req.body.name === 'string' ? req.body.name.trim() : '';
    if (name.length < 1 || name.length > 100) return badRequest(res, 'Nama merek wajib diisi (maks. 100 karakter)');
    try {
        const [result] = await pool.execute('UPDATE brands SET name = ? WHERE id = ? AND deleted_at IS NULL', [name, req.params.id]);
        if (result.affectedRows === 0) return res.status(404).json({ error: 'Merek tidak ditemukan' });
        await logAudit(pool, req, { action: 'update', entity: 'brand', entityId: req.params.id, after: { name } });
        res.json({ message: 'Merek berhasil diperbarui', brand: { id: Number(req.params.id), name } });
    } catch (error) {
        if (error.code === 'ER_DUP_ENTRY') return badRequest(res, 'Nama merek sudah digunakan');
        console.error('Update brand error:', error);
        res.status(500).json({ error: 'Gagal memperbarui merek' });
    }
});

// ── tax rates ────────────────────────────────────────────────────────────────

router.get('/tax-rates', requirePermission('catalog.view'), async (req, res) => {
    try {
        const [taxRates] = await pool.execute('SELECT id, name, rate, is_active FROM tax_rates ORDER BY name');
        res.json({ taxRates: taxRates.map((t) => ({ ...t, is_active: !!t.is_active })) });
    } catch (error) {
        console.error('Get tax rates error:', error);
        res.status(500).json({ error: 'Gagal mengambil data tarif pajak' });
    }
});

const validateTaxRate = ({ name, rate }) => {
    if (typeof name !== 'string' || !name.trim() || name.trim().length > 50) return 'Nama tarif pajak wajib diisi (maks. 50 karakter)';
    const n = Number(rate);
    if (!Number.isFinite(n) || n < 0 || n > 100) return 'Tarif pajak harus antara 0 dan 100';
    return null;
};

router.post('/tax-rates', requirePermission('settings.manage'), async (req, res) => {
    const error = validateTaxRate(req.body);
    if (error) return badRequest(res, error);
    try {
        const [result] = await pool.execute('INSERT INTO tax_rates (name, rate) VALUES (?, ?)', [req.body.name.trim(), Number(req.body.rate)]);
        await logAudit(pool, req, { action: 'create', entity: 'tax_rate', entityId: result.insertId, after: req.body });
        res.status(201).json({ message: 'Tarif pajak berhasil dibuat', taxRate: { id: result.insertId, name: req.body.name.trim(), rate: Number(req.body.rate), is_active: true } });
    } catch (err) {
        if (err.code === 'ER_DUP_ENTRY') return badRequest(res, 'Nama tarif pajak sudah digunakan');
        console.error('Create tax rate error:', err);
        res.status(500).json({ error: 'Gagal membuat tarif pajak' });
    }
});

router.put('/tax-rates/:id', requirePermission('settings.manage'), async (req, res) => {
    const error = validateTaxRate(req.body);
    if (error) return badRequest(res, error);
    try {
        const [[before]] = await pool.execute('SELECT name, rate, is_active FROM tax_rates WHERE id = ?', [req.params.id]);
        if (!before) return res.status(404).json({ error: 'Tarif pajak tidak ditemukan' });
        const isActive = req.body.is_active === undefined ? before.is_active : (toBool(req.body.is_active) ? 1 : 0);
        await pool.execute('UPDATE tax_rates SET name = ?, rate = ?, is_active = ? WHERE id = ?',
            [req.body.name.trim(), Number(req.body.rate), isActive, req.params.id]);
        await logAudit(pool, req, { action: 'update', entity: 'tax_rate', entityId: req.params.id, before, after: { ...req.body, is_active: !!isActive } });
        res.json({ message: 'Tarif pajak berhasil diperbarui' });
    } catch (err) {
        if (err.code === 'ER_DUP_ENTRY') return badRequest(res, 'Nama tarif pajak sudah digunakan');
        console.error('Update tax rate error:', err);
        res.status(500).json({ error: 'Gagal memperbarui tarif pajak' });
    }
});

// ── products ─────────────────────────────────────────────────────────────────

// Loads variants for the given products. With locationId, adds on-hand stock, the effective
// sell price there and (for permitted users) the average cost.
const loadVariants = async (db, productIds, { locationId, includeInactive, showCost }) => {
    if (productIds.length === 0) return [];
    const marks = productIds.map(() => '?').join(', ');
    const locationColumns = locationId
        ? `, ${ON_HAND_SQL} AS on_hand, COALESCE(sl.sell_price, v.base_price) AS sell_price,
           sl.sell_price AS location_price, sl.reorder_level${showCost ? `, ${AVG_COST_SQL} AS avg_cost` : ''}`
        : '';
    const [rows] = await db.execute(
        `SELECT v.id, v.product_id, v.sku, v.barcode, v.name, v.attributes, v.base_price, v.min_price,
                v.is_active, v.created_at, v.updated_at ${locationColumns}
         FROM product_variants v
         JOIN products p ON p.id = v.product_id
         ${locationId ? 'LEFT JOIN stock_levels sl ON sl.variant_id = v.id AND sl.location_id = ?' : ''}
         WHERE v.product_id IN (${marks}) AND v.deleted_at IS NULL
           ${includeInactive ? '' : 'AND v.is_active = 1'}
         ORDER BY v.product_id, v.id`,
        locationId ? [locationId, ...productIds] : productIds
    );
    return rows.map((r) => ({ ...r, is_active: !!r.is_active, ...(locationId ? { on_hand: Number(r.on_hand) } : {}) }));
};

const PRODUCT_COLUMNS = `
    p.id, p.name, p.description, p.category_id, c.name AS category_name, p.brand_id, b.name AS brand_name,
    p.kind, p.is_serialized, p.serial_type, p.warranty_months, p.tax_rate_id, p.image, p.is_active,
    p.created_at, p.updated_at`;

const shapeProduct = (row, variants) => ({
    ...row,
    is_serialized: !!row.is_serialized,
    is_active: !!row.is_active,
    variants: variants.filter((v) => v.product_id === row.id),
});

// GET /api/catalog/products?search=&category_id=&brand_id=&kind=&location_id=&include_inactive=&page=&limit=
router.get('/products', requirePermission('catalog.view'), async (req, res) => {
    try {
        const { search, category_id, brand_id, kind } = req.query;
        const includeInactive = req.query.include_inactive === 'true';
        const page = Math.max(parseInt(req.query.page, 10) || 1, 1);
        const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 50, 1), 200);

        let where = 'WHERE p.deleted_at IS NULL';
        const params = [];
        if (!includeInactive) where += ' AND p.is_active = 1';
        if (category_id) { where += ' AND p.category_id = ?'; params.push(Number(category_id)); }
        if (brand_id) { where += ' AND p.brand_id = ?'; params.push(Number(brand_id)); }
        if (kind && KINDS.includes(kind)) { where += ' AND p.kind = ?'; params.push(kind); }
        if (search) {
            where += ` AND (p.name LIKE ? OR EXISTS (SELECT 1 FROM product_variants sv WHERE sv.product_id = p.id
                        AND sv.deleted_at IS NULL AND (sv.sku LIKE ? OR sv.barcode = ? OR sv.name LIKE ?)))`;
            params.push(`%${search}%`, `%${search}%`, search, `%${search}%`);
        }

        const [[{ total }]] = await pool.execute(`SELECT COUNT(*) AS total FROM products p ${where}`, params);
        const [rows] = await pool.execute(
            `SELECT ${PRODUCT_COLUMNS}
             FROM products p
             LEFT JOIN categories c ON c.id = p.category_id
             LEFT JOIN brands b ON b.id = p.brand_id
             ${where}
             ORDER BY p.name
             LIMIT ${limit} OFFSET ${(page - 1) * limit}`,
            params
        );

        const variants = await loadVariants(pool, rows.map((r) => r.id), {
            locationId: req.locationId,
            includeInactive,
            showCost: req.locationId && canSeeCost(req.access, req.locationId),
        });

        res.json({
            products: rows.map((r) => shapeProduct(r, variants)),
            pagination: { page, limit, total: Number(total), totalPages: Math.ceil(Number(total) / limit) },
        });
    } catch (error) {
        console.error('Get catalog products error:', error);
        res.status(500).json({ error: 'Gagal mengambil data produk' });
    }
});

// Product with variants and stock at every location the user may view stock for.
router.get('/products/:id', requirePermission('catalog.view'), async (req, res) => {
    try {
        const [[row]] = await pool.execute(
            `SELECT ${PRODUCT_COLUMNS}
             FROM products p
             LEFT JOIN categories c ON c.id = p.category_id
             LEFT JOIN brands b ON b.id = p.brand_id
             WHERE p.id = ? AND p.deleted_at IS NULL`,
            [req.params.id]
        );
        if (!row) return res.status(404).json({ error: 'Produk tidak ditemukan' });

        const variants = await loadVariants(pool, [row.id], { includeInactive: true });
        const product = shapeProduct(row, variants);

        const visible = req.access.locationsFor('stock.view');
        const [stockRows] = await pool.execute(
            `SELECT sl.location_id, l.code AS location_code, l.name AS location_name, l.type AS location_type,
                    v.id AS variant_id, ${ON_HAND_SQL} AS on_hand, sl.sell_price AS location_price,
                    COALESCE(sl.sell_price, v.base_price) AS sell_price, ${AVG_COST_SQL} AS avg_cost, sl.reorder_level
             FROM stock_levels sl
             JOIN product_variants v ON v.id = sl.variant_id
             JOIN products p ON p.id = v.product_id
             JOIN locations l ON l.id = sl.location_id
             WHERE v.product_id = ? AND l.deleted_at IS NULL
             ORDER BY l.type = 'warehouse' DESC, l.code`,
            [row.id]
        );
        product.stock = stockRows
            .filter((s) => visible === null || visible.includes(s.location_id))
            .map(({ avg_cost, ...s }) => ({
                ...s,
                on_hand: Number(s.on_hand),
                ...(canSeeCost(req.access, s.location_id) ? { avg_cost } : {}),
            }));

        res.json({ product });
    } catch (error) {
        console.error('Get catalog product error:', error);
        res.status(500).json({ error: 'Gagal mengambil data produk' });
    }
});

// Validates product-level fields. `partial` allows omitted fields (PUT); `current` is the
// existing row, used when only some of the related fields are sent.
const readProductFields = async (db, body, { partial, current = {} }) => {
    const fields = {};
    if (!partial || body.name !== undefined) {
        const name = typeof body.name === 'string' ? body.name.trim() : '';
        if (!name || name.length > 150) return { error: 'Nama produk wajib diisi (maks. 150 karakter)' };
        fields.name = name;
    }
    if (body.description !== undefined) fields.description = body.description || null;
    for (const [key, table, label] of [['category_id', 'categories', 'Kategori'], ['brand_id', 'brands', 'Merek'], ['tax_rate_id', 'tax_rates', 'Tarif pajak']]) {
        if (body[key] === undefined) continue;
        if (body[key] === null || body[key] === '') { fields[key] = null; continue; }
        const [rows] = await db.execute(`SELECT id FROM ${table} WHERE id = ?`, [Number(body[key])]);
        if (rows.length === 0) return { error: `${label} tidak ditemukan` };
        fields[key] = Number(body[key]);
    }
    if (!partial || body.kind !== undefined) {
        const kind = body.kind || 'goods';
        if (!KINDS.includes(kind)) return { error: 'Jenis produk harus goods, service, atau digital' };
        fields.kind = kind;
    }
    if (!partial || body.is_serialized !== undefined || body.serial_type !== undefined) {
        const isSerialized = body.is_serialized !== undefined ? toBool(body.is_serialized) : !!current.is_serialized;
        const serialType = isSerialized ? (body.serial_type || current.serial_type || 'imei') : null;
        if (isSerialized && !SERIAL_TYPES.includes(serialType)) return { error: 'serial_type harus imei, imei_dual, atau serial' };
        if (isSerialized && (fields.kind || current.kind || 'goods') !== 'goods') return { error: 'Hanya produk barang yang dapat memakai IMEI/serial' };
        fields.is_serialized = isSerialized ? 1 : 0;
        fields.serial_type = serialType;
    }
    if (fields.kind && fields.kind !== 'goods' && (fields.is_serialized ?? current.is_serialized)) {
        return { error: 'Hanya produk barang yang dapat memakai IMEI/serial' };
    }
    if (body.warranty_months !== undefined) {
        const months = Number(body.warranty_months);
        if (!Number.isInteger(months) || months < 0 || months > 120) return { error: 'Garansi harus 0–120 bulan' };
        fields.warranty_months = months;
    }
    if (body.is_active !== undefined) fields.is_active = toBool(body.is_active) ? 1 : 0;
    return { fields };
};

const readVariantFields = (body, { partial }) => {
    const fields = {};
    if (body.sku !== undefined && body.sku !== null && body.sku !== '') {
        const sku = String(body.sku).trim();
        if (!SKU.test(sku)) return { error: `SKU "${sku}" tidak valid (2–50 karakter: huruf, angka, - _ .)` };
        fields.sku = sku;
    }
    if (body.barcode !== undefined) {
        const barcode = body.barcode === null ? '' : String(body.barcode).trim();
        if (barcode.length > 100) return { error: 'Barcode maks. 100 karakter' };
        fields.barcode = barcode || null;
    }
    if (body.name !== undefined) {
        const name = body.name === null ? '' : String(body.name).trim();
        if (name.length > 100) return { error: 'Nama varian maks. 100 karakter' };
        fields.name = name || null;
    }
    if (body.attributes !== undefined) {
        if (body.attributes !== null && (typeof body.attributes !== 'object' || Array.isArray(body.attributes))) {
            return { error: 'attributes harus berupa object, contoh {"ram":"8GB"}' };
        }
        fields.attributes = body.attributes === null ? null : JSON.stringify(body.attributes);
    }
    if (!partial || body.base_price !== undefined) {
        const price = parseMoney(body.base_price);
        if (price === null || Number.isNaN(price)) return { error: 'Harga jual varian wajib diisi dan tidak boleh negatif' };
        fields.base_price = price;
    }
    if (body.min_price !== undefined) {
        const price = parseMoney(body.min_price);
        if (Number.isNaN(price)) return { error: 'Harga minimum tidak valid' };
        fields.min_price = price;
    }
    if (body.is_active !== undefined) fields.is_active = toBool(body.is_active) ? 1 : 0;
    return { fields };
};

const insertVariant = async (conn, productId, fields) => {
    const columns = ['product_id', 'sku', ...Object.keys(fields).filter((k) => k !== 'sku')];
    const values = [productId, fields.sku || `TMP-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`,
        ...Object.keys(fields).filter((k) => k !== 'sku').map((k) => fields[k])];
    const [result] = await conn.execute(
        `INSERT INTO product_variants (${columns.join(', ')}) VALUES (${columns.map(() => '?').join(', ')})`,
        values
    );
    if (!fields.sku) await assignGeneratedSku(conn, result.insertId);
    return result.insertId;
};

const duplicateMessage = (error) => {
    if (error.message.includes('uq_variants_sku')) return 'SKU sudah digunakan';
    if (error.message.includes('uq_variants_barcode')) return 'Barcode sudah digunakan';
    return 'Data duplikat';
};

const hasStockHistory = async (db, productId) => {
    const [[row]] = await db.execute(
        `SELECT EXISTS (SELECT 1 FROM stock_movements m JOIN product_variants v ON v.id = m.variant_id WHERE v.product_id = ?) AS used`,
        [productId]
    );
    return !!row.used;
};

// Body: { name, description, category_id, brand_id, kind, is_serialized, serial_type, warranty_months,
//         tax_rate_id, variants: [{ sku?, barcode?, name?, attributes?, base_price, min_price? }] }
// SKUs are generated when omitted. Stock is added separately through /api/stock.
router.post('/products', requirePermission('catalog.manage'), async (req, res) => {
    const conn = await pool.getConnection();
    try {
        const { fields, error } = await readProductFields(conn, req.body, { partial: false });
        if (error) return badRequest(res, error);

        const variantInputs = req.body.variants;
        if (!Array.isArray(variantInputs) || variantInputs.length === 0) return badRequest(res, 'Minimal satu varian wajib diisi');
        if (variantInputs.length > 100) return badRequest(res, 'Maksimal 100 varian per produk');
        const variants = [];
        for (const input of variantInputs) {
            const parsed = readVariantFields(input, { partial: false });
            if (parsed.error) return badRequest(res, parsed.error);
            variants.push(parsed.fields);
        }

        await conn.beginTransaction();
        const columns = Object.keys(fields);
        const [result] = await conn.execute(
            `INSERT INTO products (${columns.join(', ')}) VALUES (${columns.map(() => '?').join(', ')})`,
            columns.map((k) => fields[k])
        );
        for (const variant of variants) await insertVariant(conn, result.insertId, variant);
        await logAudit(conn, req, { action: 'create', entity: 'product', entityId: result.insertId, after: { ...fields, variants } });
        await conn.commit();

        const [[product]] = await pool.execute(`SELECT ${PRODUCT_COLUMNS} FROM products p LEFT JOIN categories c ON c.id = p.category_id LEFT JOIN brands b ON b.id = p.brand_id WHERE p.id = ?`, [result.insertId]);
        res.status(201).json({
            message: 'Produk berhasil dibuat',
            product: shapeProduct(product, await loadVariants(pool, [result.insertId], { includeInactive: true })),
        });
    } catch (error) {
        await conn.rollback();
        if (error.code === 'ER_DUP_ENTRY') return badRequest(res, duplicateMessage(error));
        console.error('Create catalog product error:', error);
        res.status(500).json({ error: 'Gagal membuat produk' });
    } finally {
        conn.release();
    }
});

router.put('/products/:id', requirePermission('catalog.manage'), async (req, res) => {
    const conn = await pool.getConnection();
    try {
        const [[before]] = await conn.execute('SELECT * FROM products WHERE id = ? AND deleted_at IS NULL', [req.params.id]);
        if (!before) return res.status(404).json({ error: 'Produk tidak ditemukan' });

        const { fields, error } = await readProductFields(conn, req.body, { partial: true, current: before });
        if (error) return badRequest(res, error);
        if (Object.keys(fields).length === 0) return badRequest(res, 'Tidak ada field yang valid untuk diperbarui');

        // Switching between quantity and per-unit tracking would orphan existing stock.
        const trackingChanged = (fields.kind !== undefined && fields.kind !== before.kind) ||
            (fields.is_serialized !== undefined && fields.is_serialized !== before.is_serialized);
        if (trackingChanged && await hasStockHistory(conn, before.id)) {
            return badRequest(res, 'Jenis produk / pelacakan IMEI tidak dapat diubah setelah produk memiliki riwayat stok');
        }
        if (fields.serial_type !== undefined && fields.serial_type !== before.serial_type && before.is_serialized && await hasStockHistory(conn, before.id)) {
            return badRequest(res, 'Tipe IMEI/serial tidak dapat diubah setelah produk memiliki unit');
        }

        await conn.beginTransaction();
        const columns = Object.keys(fields);
        await conn.execute(`UPDATE products SET ${columns.map((c) => `${c} = ?`).join(', ')} WHERE id = ?`, [...columns.map((c) => fields[c]), before.id]);
        await logAudit(conn, req, { action: 'update', entity: 'product', entityId: before.id, before, after: fields });
        await conn.commit();

        res.json({ message: 'Produk berhasil diperbarui' });
    } catch (error) {
        await conn.rollback();
        console.error('Update catalog product error:', error);
        res.status(500).json({ error: 'Gagal memperbarui produk' });
    } finally {
        conn.release();
    }
});

// Soft delete: the product disappears from the catalog but old sales and movements still resolve.
router.delete('/products/:id', requirePermission('catalog.manage'), async (req, res) => {
    const conn = await pool.getConnection();
    try {
        const [[before]] = await conn.execute('SELECT * FROM products WHERE id = ? AND deleted_at IS NULL', [req.params.id]);
        if (!before) return res.status(404).json({ error: 'Produk tidak ditemukan' });

        await conn.beginTransaction();
        await conn.execute('UPDATE product_variants SET deleted_at = NOW(3) WHERE product_id = ? AND deleted_at IS NULL', [before.id]);
        await conn.execute('UPDATE products SET deleted_at = NOW(3) WHERE id = ?', [before.id]);
        await logAudit(conn, req, { action: 'delete', entity: 'product', entityId: before.id, before });
        await conn.commit();

        res.json({ message: 'Produk berhasil dihapus' });
    } catch (error) {
        await conn.rollback();
        console.error('Delete catalog product error:', error);
        res.status(500).json({ error: 'Gagal menghapus produk' });
    } finally {
        conn.release();
    }
});

// Multipart field: image
router.post('/products/:id/image', requirePermission('catalog.manage'), uploadProduct.single('image'), async (req, res) => {
    if (!req.file) return badRequest(res, 'File gambar wajib diunggah (field: image)');
    try {
        validateUploadedImage(req.file.path, req.file.mimetype);
    } catch (error) {
        return badRequest(res, error.message || 'File gambar tidak valid');
    }
    try {
        const [[before]] = await pool.execute('SELECT image FROM products WHERE id = ? AND deleted_at IS NULL', [req.params.id]);
        if (!before) {
            deleteFile(`API/uploads/products/${req.file.filename}`);
            return res.status(404).json({ error: 'Produk tidak ditemukan' });
        }
        await pool.execute('UPDATE products SET image = ? WHERE id = ?', [req.file.filename, req.params.id]);
        if (before.image) deleteFile(`API/uploads/products/${before.image}`);
        res.json({ message: 'Gambar produk berhasil diperbarui', image: req.file.filename });
    } catch (error) {
        deleteFile(`API/uploads/products/${req.file.filename}`);
        console.error('Upload product image error:', error);
        res.status(500).json({ error: 'Gagal mengunggah gambar produk' });
    }
});

// ── variants ─────────────────────────────────────────────────────────────────

router.post('/products/:id/variants', requirePermission('catalog.manage'), async (req, res) => {
    const conn = await pool.getConnection();
    try {
        const [[product]] = await conn.execute('SELECT id FROM products WHERE id = ? AND deleted_at IS NULL', [req.params.id]);
        if (!product) return res.status(404).json({ error: 'Produk tidak ditemukan' });
        const { fields, error } = readVariantFields(req.body, { partial: false });
        if (error) return badRequest(res, error);

        await conn.beginTransaction();
        const variantId = await insertVariant(conn, product.id, fields);
        await logAudit(conn, req, { action: 'create', entity: 'variant', entityId: variantId, after: { product_id: product.id, ...fields } });
        await conn.commit();

        const [variant] = (await loadVariants(pool, [product.id], { includeInactive: true })).filter((v) => v.id === variantId);
        res.status(201).json({ message: 'Varian berhasil dibuat', variant });
    } catch (error) {
        await conn.rollback();
        if (error.code === 'ER_DUP_ENTRY') return badRequest(res, duplicateMessage(error));
        console.error('Create variant error:', error);
        res.status(500).json({ error: 'Gagal membuat varian' });
    } finally {
        conn.release();
    }
});

router.put('/variants/:id', requirePermission('catalog.manage'), async (req, res) => {
    try {
        const [[before]] = await pool.execute('SELECT * FROM product_variants WHERE id = ? AND deleted_at IS NULL', [req.params.id]);
        if (!before) return res.status(404).json({ error: 'Varian tidak ditemukan' });
        const { fields, error } = readVariantFields(req.body, { partial: true });
        if (error) return badRequest(res, error);
        const columns = Object.keys(fields);
        if (columns.length === 0) return badRequest(res, 'Tidak ada field yang valid untuk diperbarui');

        await pool.execute(`UPDATE product_variants SET ${columns.map((c) => `${c} = ?`).join(', ')} WHERE id = ?`, [...columns.map((c) => fields[c]), before.id]);
        await logAudit(pool, req, { action: 'update', entity: 'variant', entityId: before.id, before, after: fields });
        res.json({ message: 'Varian berhasil diperbarui' });
    } catch (error) {
        if (error.code === 'ER_DUP_ENTRY') return badRequest(res, duplicateMessage(error));
        console.error('Update variant error:', error);
        res.status(500).json({ error: 'Gagal memperbarui varian' });
    }
});

router.delete('/variants/:id', requirePermission('catalog.manage'), async (req, res) => {
    try {
        const [[before]] = await pool.execute('SELECT * FROM product_variants WHERE id = ? AND deleted_at IS NULL', [req.params.id]);
        if (!before) return res.status(404).json({ error: 'Varian tidak ditemukan' });
        const [[{ remaining }]] = await pool.execute(
            'SELECT COUNT(*) AS remaining FROM product_variants WHERE product_id = ? AND deleted_at IS NULL AND id <> ?',
            [before.product_id, before.id]
        );
        if (Number(remaining) === 0) return badRequest(res, 'Varian terakhir tidak dapat dihapus; hapus produknya');

        await pool.execute('UPDATE product_variants SET deleted_at = NOW(3) WHERE id = ?', [before.id]);
        await logAudit(pool, req, { action: 'delete', entity: 'variant', entityId: before.id, before });
        res.json({ message: 'Varian berhasil dihapus' });
    } catch (error) {
        console.error('Delete variant error:', error);
        res.status(500).json({ error: 'Gagal menghapus varian' });
    }
});

module.exports = router;
