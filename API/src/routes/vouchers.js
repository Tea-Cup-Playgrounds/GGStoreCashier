const express = require('express');
const pool = require('../db');
const { authenticateToken, requirePermission } = require('../middleware/auth');

const router = express.Router();
router.use(authenticateToken);

// What a voucher applies to: everything (null), one category ('categories', target_id = category
// id) or one variant ('product', target_id = variant id). 'category' is accepted for 'categories'.
// Returns { error } or { targetType, targetId }.
const readTarget = async (body) => {
    const raw = body.target_type === undefined || body.target_type === null ? '' : String(body.target_type).trim();
    if (raw === '') return { targetType: null, targetId: null };
    const targetType = raw === 'category' ? 'categories' : raw;
    if (!['categories', 'product'].includes(targetType)) {
        return { error: 'Target voucher harus kosong (semua barang), categories, atau product' };
    }
    const targetId = Number(body.target_id);
    if (!Number.isInteger(targetId) || targetId <= 0) {
        return { error: targetType === 'categories' ? 'Pilih kategori voucher' : 'Pilih varian produk voucher' };
    }
    const [rows] = targetType === 'categories'
        ? await pool.execute('SELECT id FROM categories WHERE id = ?', [targetId])
        : await pool.execute('SELECT id FROM product_variants WHERE id = ? AND deleted_at IS NULL', [targetId]);
    if (rows.length === 0) return { error: targetType === 'categories' ? 'Kategori tidak ditemukan' : 'Varian produk tidak ditemukan' };
    return { targetType, targetId };
};

// Shared checks for create and update. Returns an error message or null.
const checkDiscount = ({ code, discount_type, discount_value }) => {
    if (!code || !discount_type || discount_value == null) return 'Kode, tipe diskon, dan nilai diskon wajib diisi';
    if (!['percent', 'fixed'].includes(discount_type)) return 'Tipe diskon harus percent atau fixed';
    const value = Number(discount_value);
    if (!Number.isFinite(value) || value <= 0) return 'Nilai diskon harus lebih dari 0';
    if (discount_type === 'percent' && value > 100) return 'Diskon persen harus antara 1 dan 100';
    return null;
};

// ── GET /api/vouchers — list all (vouchers.manage) ─────────────────────────
router.get('/', requirePermission('vouchers.manage'), async (req, res) => {
    try {
        const [rows] = await pool.execute(
            'SELECT * FROM vouchers ORDER BY created_at DESC'
        );
        res.json({ vouchers: rows });
    } catch (err) {
        console.error('List vouchers error:', err);
        res.status(500).json({ error: 'Gagal mengambil data voucher' });
    }
});

// ── GET /api/vouchers/validate/:code — validate a code (any authenticated user) ─
router.get('/validate/:code', async (req, res) => {
    try {
        const code = req.params.code.trim().toUpperCase();
        const today = new Date().toISOString().slice(0, 10);

        const [rows] = await pool.execute(
            `SELECT * FROM vouchers
             WHERE UPPER(code) = ?
               AND is_active = 1
               AND (valid_from IS NULL OR valid_from <= ?)
               AND (valid_to   IS NULL OR valid_to   >= ?)
             LIMIT 1`,
            [code, today, today]
        );

        if (rows.length === 0) {
            return res.status(404).json({ error: 'Kode voucher tidak valid atau sudah kadaluarsa' });
        }

        res.json({ voucher: rows[0] });
    } catch (err) {
        console.error('Validate voucher error:', err);
        res.status(500).json({ error: 'Gagal memvalidasi voucher' });
    }
});

// ── POST /api/vouchers — create (vouchers.manage) ─────────────────────────
router.post('/', requirePermission('vouchers.manage'), async (req, res) => {
    try {
        const {
            code, description,
            discount_type, discount_value,
            valid_from, valid_to,
            is_active = 1,
        } = req.body;

        const invalid = checkDiscount(req.body);
        if (invalid) return res.status(400).json({ error: invalid });
        const target = await readTarget(req.body);
        if (target.error) return res.status(400).json({ error: target.error });

        const [result] = await pool.execute(
            `INSERT INTO vouchers
             (code, description, target_type, target_id, discount_type, discount_value, valid_from, valid_to, is_active)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [
                code.trim().toUpperCase(),
                description || null,
                target.targetType,
                target.targetId,
                discount_type,
                discount_value,
                valid_from || null,
                valid_to || null,
                is_active ? 1 : 0,
            ]
        );

        res.status(201).json({ message: 'Voucher berhasil dibuat', voucherId: result.insertId });
    } catch (err) {
        if (err.code === 'ER_DUP_ENTRY') {
            return res.status(409).json({ error: 'Kode voucher sudah digunakan' });
        }
        console.error('Create voucher error:', err);
        res.status(500).json({ error: 'Gagal membuat voucher' });
    }
});

// ── PUT /api/vouchers/:id — update (vouchers.manage) ───────────────────────────
router.put('/:id', requirePermission('vouchers.manage'), async (req, res) => {
    try {
        const {
            code, description,
            discount_type, discount_value,
            valid_from, valid_to, is_active,
        } = req.body;

        const invalid = checkDiscount(req.body);
        if (invalid) return res.status(400).json({ error: invalid });
        const target = await readTarget(req.body);
        if (target.error) return res.status(400).json({ error: target.error });

        const [result] = await pool.execute(
            `UPDATE vouchers SET
               code = ?, description = ?, target_type = ?, target_id = ?,
               discount_type = ?, discount_value = ?,
               valid_from = ?, valid_to = ?, is_active = ?
             WHERE id = ?`,
            [
                code.trim().toUpperCase(),
                description || null,
                target.targetType,
                target.targetId,
                discount_type,
                discount_value,
                valid_from || null,
                valid_to || null,
                is_active ? 1 : 0,
                req.params.id,
            ]
        );

        if (result.affectedRows === 0) {
            return res.status(404).json({ error: 'Voucher tidak ditemukan' });
        }
        res.json({ message: 'Voucher berhasil diperbarui' });
    } catch (err) {
        if (err.code === 'ER_DUP_ENTRY') {
            return res.status(409).json({ error: 'Kode voucher sudah digunakan' });
        }
        console.error('Update voucher error:', err);
        res.status(500).json({ error: 'Gagal memperbarui voucher' });
    }
});

// ── DELETE /api/vouchers/:id — delete (vouchers.manage) ────────────────────
router.delete('/:id', requirePermission('vouchers.manage'), async (req, res) => {
    try {
        const [result] = await pool.execute(
            'DELETE FROM vouchers WHERE id = ?',
            [req.params.id]
        );
        if (result.affectedRows === 0) {
            return res.status(404).json({ error: 'Voucher tidak ditemukan' });
        }
        res.json({ message: 'Voucher berhasil dihapus' });
    } catch (err) {
        console.error('Delete voucher error:', err);
        res.status(500).json({ error: 'Gagal menghapus voucher' });
    }
});

module.exports = router;
