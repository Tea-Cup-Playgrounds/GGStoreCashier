const express = require('express');
const pool = require('../db');
const { authenticateToken, requireRole } = require('../middleware/auth');

const router = express.Router();
router.use(authenticateToken);

// ── GET /api/vouchers — list all (admin + superadmin) ─────────────────────────
router.get('/', requireRole(['admin', 'superadmin']), async (req, res) => {
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

// ── POST /api/vouchers — create (admin + superadmin) ─────────────────────────
router.post('/', requireRole(['admin', 'superadmin']), async (req, res) => {
    try {
        const {
            code, description,
            target_type, target_id,
            discount_type, discount_value,
            valid_from, valid_to,
            is_active = 1,
        } = req.body;

        if (!code || !discount_type || discount_value == null) {
            return res.status(400).json({
                error: 'Kode, tipe diskon, dan nilai diskon wajib diisi'
            });
        }
        if (!['percent', 'fixed'].includes(discount_type)) {
            return res.status(400).json({ error: 'Tipe diskon harus percent atau fixed' });
        }
        if (discount_type === 'percent' && (discount_value <= 0 || discount_value > 100)) {
            return res.status(400).json({ error: 'Diskon persen harus antara 1 dan 100' });
        }

        const [result] = await pool.execute(
            `INSERT INTO vouchers
             (code, description, target_type, target_id, discount_type, discount_value, valid_from, valid_to, is_active)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [
                code.trim().toUpperCase(),
                description || null,
                target_type || null,
                target_id || null,
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

// ── PUT /api/vouchers/:id — update (admin + superadmin) ──────────────────────
router.put('/:id', requireRole(['admin', 'superadmin']), async (req, res) => {
    try {
        const {
            code, description,
            target_type, target_id,
            discount_type, discount_value,
            valid_from, valid_to, is_active,
        } = req.body;

        if (!code || !discount_type || discount_value == null) {
            return res.status(400).json({
                error: 'Kode, tipe diskon, dan nilai diskon wajib diisi'
            });
        }

        const [result] = await pool.execute(
            `UPDATE vouchers SET
               code = ?, description = ?, target_type = ?, target_id = ?,
               discount_type = ?, discount_value = ?,
               valid_from = ?, valid_to = ?, is_active = ?
             WHERE id = ?`,
            [
                code.trim().toUpperCase(),
                description || null,
                target_type || null,
                target_id || null,
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

// ── DELETE /api/vouchers/:id — delete (admin + superadmin) ───────────────────
router.delete('/:id', requireRole(['admin', 'superadmin']), async (req, res) => {
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
