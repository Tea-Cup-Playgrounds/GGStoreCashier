// Legacy /api/products, kept for the current Flutter app. Backed by the catalog tables through
// services/legacy-products.js: a product here is one variant at one branch (id = variant id).
// New features should use /api/catalog and /api/stock.
const express = require('express');
const pool = require('../db');
const { authenticateToken, requireRole, filterByBranch } = require('../middleware/auth');
const { uploadProduct, deleteFile, validateUploadedImage } = require('../utils/upload');
const { listLegacyProducts, getLegacyProduct, emitLegacyProduct } = require('../services/legacy-products');
const { assignGeneratedSku } = require('../services/catalog');
const stock = require('../services/stock');
const { logAudit } = require('../services/audit');

const router = express.Router();

// Apply authentication to all routes
router.use(authenticateToken);

const discardUpload = (req) => {
    if (req.file) deleteFile(`API/uploads/products/${req.file.filename}`);
};

// The branch a legacy request acts on: the user's own branch, or (superadmin) the one supplied.
const legacyLocation = (req) => {
    if (req.user.role !== 'superadmin') return req.user.branch_id || null;
    const id = Number(req.body?.branch_id ?? req.query.branch_id);
    return Number.isInteger(id) && id > 0 ? id : null;
};

// Multipart forms send missing values as '' or the string 'null'.
const formValue = (value) => (value === undefined || value === null || value === '' || value === 'null' ? null : value);

// Get all products (with branch filtering)
router.get('/', filterByBranch, async (req, res) => {
    try {
        const { branch_id, category_id, search } = req.query;
        const locationId = Number(branch_id);
        const hasLocation = Number.isInteger(locationId) && locationId > 0;
        // Without a branch, only superadmin gets the all-branches view.
        if (!hasLocation && req.user.role !== 'superadmin') {
            return res.json({ products: [] });
        }
        const products = await listLegacyProducts(pool, {
            locationId: hasLocation ? locationId : null,
            categoryId: category_id,
            search,
        });
        res.json({ products });

    } catch (error) {
        console.error('Get products error:', error);
        res.status(500).json({ error: 'Gagal mengambil data produk' });
    }
});

// Get product by ID
router.get('/:id', async (req, res) => {
    try {
        const product = await getLegacyProduct(pool, req.params.id, legacyLocation(req));

        if (!product) {
            return res.status(404).json({ error: 'Produk tidak ditemukan' });
        }

        res.json({ product });

    } catch (error) {
        console.error('Get product error:', error);
        res.status(500).json({ error: 'Gagal mengambil data produk' });
    }
});

// Create new product: a catalog product with one variant, plus opening stock at the branch.
router.post('/', requireRole(['admin', 'superadmin']), filterByBranch, uploadProduct.single('product_image'), async (req, res) => {
    const { name, barcode, category_id, sell_price, stock: openingStock, description } = req.body;
    const locationId = req.user.role === 'superadmin' ? legacyLocation(req) : req.userBranchId || req.user.branch_id;

    if (!req.access.can('catalog.manage')) {
        discardUpload(req);
        return res.status(403).json({ error: 'Anda tidak memiliki izin untuk menambah produk ke katalog' });
    }
    if (!formValue(name) || formValue(sell_price) === null) {
        discardUpload(req);
        return res.status(400).json({ error: 'Nama produk dan harga jual wajib diisi' });
    }
    const price = Number(sell_price);
    const qty = formValue(openingStock) === null ? 0 : Number(openingStock);
    if (!Number.isFinite(price) || price < 0 || !Number.isInteger(qty) || qty < 0) {
        discardUpload(req);
        return res.status(400).json({ error: 'Harga jual dan stok harus berupa angka yang valid' });
    }
    if (qty > 0 && !locationId) {
        discardUpload(req);
        return res.status(400).json({ error: 'branch_id wajib diisi untuk menambahkan stok awal' });
    }
    if (qty > 0 && !req.access.can('stock.adjust', locationId)) {
        discardUpload(req);
        return res.status(403).json({ error: 'Anda tidak memiliki izin menambah stok di cabang ini' });
    }

    if (req.file) {
        try {
            validateUploadedImage(req.file.path, req.file.mimetype);
        } catch (error) {
            return res.status(400).json({ error: error.message || 'File gambar tidak valid' });
        }
    }

    const productBarcode = formValue(barcode) && barcode.trim() !== ''
        ? barcode.trim()
        : 'GG' + Date.now() + Math.floor(Math.random() * 1000);

    const conn = await pool.getConnection();
    let variantId;
    try {
        await conn.beginTransaction();
        const [productResult] = await conn.execute(
            'INSERT INTO products (name, description, category_id, kind, image) VALUES (?, ?, ?, \'goods\', ?)',
            [name, formValue(description), formValue(category_id), req.file ? req.file.filename : null]
        );
        const [variantResult] = await conn.execute(
            'INSERT INTO product_variants (product_id, sku, barcode, base_price) VALUES (?, ?, ?, ?)',
            [productResult.insertId, `TMP-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`, productBarcode, price]
        );
        variantId = variantResult.insertId;
        await assignGeneratedSku(conn, variantId);

        if (qty > 0) {
            await stock.adjustQuantity(conn, { userId: req.user.id }, {
                locationId, variantId, qtyChange: qty, reason: 'adjustment', note: 'Stok awal',
            });
        }
        await logAudit(conn, req, {
            action: 'create', entity: 'product', entityId: productResult.insertId, locationId,
            after: { name, barcode: productBarcode, category_id: category_id || null, sell_price: price, opening_stock: qty },
        });
        await conn.commit();
    } catch (error) {
        await conn.rollback();
        discardUpload(req);
        if (error instanceof stock.StockError) return res.status(error.status).json({ error: error.message });
        console.error('Create product error:', error);
        if (error.code === 'ER_DUP_ENTRY') return res.status(400).json({ error: 'Barcode sudah digunakan' });
        return res.status(500).json({ error: 'Gagal menambahkan produk' });
    } finally {
        conn.release();
    }

    const product = await getLegacyProduct(pool, variantId, locationId);
    await emitLegacyProduct(req, 'product-created', variantId, locationId ? [locationId] : []);

    res.status(201).json({
        message: 'Produk berhasil ditambahkan',
        productId: variantId,
        product
    });
});

// Update product.
// - name / barcode / category / description / image change the shared catalog (catalog.manage).
// - sell_price changes the branch price override when the branch has one or the user can't edit
//   the catalog (prices.manage_location); otherwise the base price.
// - stock is a target quantity at the branch, applied as an adjustment movement (stock.adjust).
router.put('/:id', requireRole(['admin', 'superadmin']), filterByBranch, uploadProduct.single('product_image'), async (req, res) => {
    const { name, barcode, category_id, sell_price, stock: targetStock, description } = req.body;
    const locationId = req.user.role === 'superadmin' ? legacyLocation(req) : req.userBranchId || req.user.branch_id;

    const [[current]] = await pool.execute(
        `SELECT v.id, v.product_id, v.barcode, v.base_price, p.name, p.category_id, p.description, p.image, p.is_serialized
         FROM product_variants v JOIN products p ON p.id = v.product_id
         WHERE v.id = ? AND v.deleted_at IS NULL AND p.deleted_at IS NULL`,
        [req.params.id]
    );
    if (!current) {
        discardUpload(req);
        return res.status(404).json({ error: 'Produk tidak ditemukan' });
    }
    const before = await getLegacyProduct(pool, current.id, locationId);
    if (!before) {
        discardUpload(req);
        return res.status(404).json({ error: 'Produk tidak ditemukan' });
    }

    if (req.file) {
        try {
            validateUploadedImage(req.file.path, req.file.mimetype);
        } catch (error) {
            return res.status(400).json({ error: error.message || 'File gambar tidak valid' });
        }
    }

    // Only compare fields the client actually sent.
    const catalogChanges = {};
    if (formValue(name) !== null && name !== before.name) catalogChanges.name = name;
    if (formValue(barcode) !== null && barcode !== current.barcode) catalogChanges.barcode = barcode;
    if (category_id !== undefined && String(formValue(category_id) ?? '') !== String(current.category_id ?? '')) {
        catalogChanges.category_id = formValue(category_id);
    }
    if (description !== undefined && formValue(description) !== current.description) catalogChanges.description = formValue(description);
    if (req.file) catalogChanges.image = req.file.filename;

    if (Object.keys(catalogChanges).length > 0 && !req.access.can('catalog.manage')) {
        discardUpload(req);
        return res.status(403).json({ error: 'Anda tidak memiliki izin mengubah data katalog (nama, barcode, kategori, gambar)' });
    }

    const price = formValue(sell_price) !== null ? Number(sell_price) : null;
    if (price !== null && (!Number.isFinite(price) || price < 0)) {
        discardUpload(req);
        return res.status(400).json({ error: 'Harga jual tidak valid' });
    }
    const target = formValue(targetStock) !== null ? Number(targetStock) : null;
    if (target !== null && (!Number.isInteger(target) || target < 0)) {
        discardUpload(req);
        return res.status(400).json({ error: 'Stok tidak valid' });
    }
    const stockDelta = target !== null ? target - before.stock : 0;

    const conn = await pool.getConnection();
    try {
        await conn.beginTransaction();

        if (['name', 'category_id', 'description', 'image'].some((c) => catalogChanges[c] !== undefined)) {
            const cols = ['name', 'category_id', 'description', 'image'].filter((c) => catalogChanges[c] !== undefined);
            await conn.execute(`UPDATE products SET ${cols.map((c) => `${c} = ?`).join(', ')} WHERE id = ?`,
                [...cols.map((c) => catalogChanges[c]), current.product_id]);
        }
        if (catalogChanges.barcode) {
            await conn.execute('UPDATE product_variants SET barcode = ? WHERE id = ?', [catalogChanges.barcode, current.id]);
        }

        if (price !== null && price !== Number(before.sell_price)) {
            const [[level]] = locationId
                ? await conn.execute('SELECT sell_price FROM stock_levels WHERE location_id = ? AND variant_id = ?', [locationId, current.id])
                : [[null]];
            const useOverride = locationId && ((level && level.sell_price !== null) || !req.access.can('catalog.manage'));
            if (useOverride) {
                if (!req.access.can('prices.manage_location', locationId)) {
                    throw new stock.StockError('Anda tidak memiliki izin mengubah harga di cabang ini', 403);
                }
                await stock.setLocationPrice(conn, { locationId, variantId: current.id, sellPrice: price });
            } else {
                if (!req.access.can('catalog.manage')) throw new stock.StockError('Anda tidak memiliki izin mengubah harga katalog', 403);
                await conn.execute('UPDATE product_variants SET base_price = ? WHERE id = ?', [price, current.id]);
            }
        }

        if (stockDelta !== 0) {
            if (!locationId) throw new stock.StockError('Pilih cabang untuk mengubah stok');
            if (!req.access.can('stock.adjust', locationId)) throw new stock.StockError('Anda tidak memiliki izin mengubah stok di cabang ini', 403);
            if (current.is_serialized) throw new stock.StockError('Stok produk ber-IMEI diubah melalui pendaftaran unit');
            await stock.adjustQuantity(conn, { userId: req.user.id }, {
                locationId, variantId: current.id, qtyChange: stockDelta, reason: 'adjustment',
                note: 'Penyesuaian stok dari edit produk',
            });
        }

        await logAudit(conn, req, {
            action: 'update', entity: 'product', entityId: current.product_id, locationId,
            before, after: { ...catalogChanges, sell_price: price, stock: target },
        });
        await conn.commit();
    } catch (error) {
        await conn.rollback();
        discardUpload(req);
        if (error instanceof stock.StockError) return res.status(error.status).json({ error: error.message });
        console.error('Update product error:', error);
        if (error.code === 'ER_DUP_ENTRY') return res.status(400).json({ error: 'Barcode sudah digunakan' });
        return res.status(500).json({ error: 'Gagal memperbarui produk' });
    } finally {
        conn.release();
    }

    if (req.file && current.image) deleteFile(`API/uploads/products/${current.image}`);

    const product = await getLegacyProduct(pool, current.id, locationId);
    await emitLegacyProduct(req, 'product-updated', current.id, locationId ? [locationId] : []);

    res.json({
        message: 'Produk berhasil diperbarui',
        product
    });
});

// Delete product (superadmin only): soft-deletes the variant, and the product once it has no
// variants left.
router.delete('/:id', requireRole(['superadmin']), async (req, res) => {
    const conn = await pool.getConnection();
    try {
        const [[variant]] = await conn.execute(
            'SELECT id, product_id FROM product_variants WHERE id = ? AND deleted_at IS NULL',
            [req.params.id]
        );
        if (!variant) {
            return res.status(404).json({ error: 'Produk tidak ditemukan' });
        }

        await conn.beginTransaction();
        await conn.execute('UPDATE product_variants SET deleted_at = NOW(3) WHERE id = ?', [variant.id]);
        const [[{ remaining }]] = await conn.execute(
            'SELECT COUNT(*) AS remaining FROM product_variants WHERE product_id = ? AND deleted_at IS NULL',
            [variant.product_id]
        );
        if (Number(remaining) === 0) {
            await conn.execute('UPDATE products SET deleted_at = NOW(3) WHERE id = ?', [variant.product_id]);
        }
        await logAudit(conn, req, { action: 'delete', entity: 'variant', entityId: variant.id });
        await conn.commit();

        const [levels] = await pool.execute('SELECT location_id FROM stock_levels WHERE variant_id = ?', [variant.id]);
        const io = req.app.get('io');
        if (io) {
            levels.forEach(({ location_id }) => io.to(`branch-${location_id}`).emit('product-deleted', { id: req.params.id }));
            io.to('branch-0').emit('product-deleted', { id: req.params.id });
        }

        res.json({ message: 'Produk berhasil dihapus' });

    } catch (error) {
        await conn.rollback();
        console.error('Delete product error:', error);
        res.status(500).json({ error: 'Gagal menghapus produk' });
    } finally {
        conn.release();
    }
});

module.exports = router;
