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
        res.status(500).json({ error: 'Failed to fetch vouchers' });
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
            return res.status(404).json({ error: 'Invalid or expired voucher code' });
        }

        res.json({ voucher: rows[0] });
    } catch (err) {
        console.error('Validate voucher error:', err);
        res.status(500).json({ error: 'Failed to validate voucher' });
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
                error: 'code, discount_type, and discount_value are required'
            });
        }
        if (!['percent', 'fixed'].includes(discount_type)) {
            return res.status(400).json({ error: 'discount_type must be percent or fixed' });
        }
        if (discount_type === 'percent' && (discount_value <= 0 || discount_value > 100)) {
            return res.status(400).json({ error: 'Percent discount must be between 1 and 100' });
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

        res.status(201).json({ message: 'Voucher created', voucherId: result.insertId });
    } catch (err) {
        if (err.code === 'ER_DUP_ENTRY') {
            return res.status(409).json({ error: 'Voucher code already exists' });
        }
        console.error('Create voucher error:', err);
        res.status(500).json({ error: 'Failed to create voucher' });
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
                error: 'code, discount_type, and discount_value are required'
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
            return res.status(404).json({ error: 'Voucher not found' });
        }
        res.json({ message: 'Voucher updated' });
    } catch (err) {
        if (err.code === 'ER_DUP_ENTRY') {
            return res.status(409).json({ error: 'Voucher code already exists' });
        }
        console.error('Update voucher error:', err);
        res.status(500).json({ error: 'Failed to update voucher' });
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
            return res.status(404).json({ error: 'Voucher not found' });
        }
        res.json({ message: 'Voucher deleted' });
    } catch (err) {
        console.error('Delete voucher error:', err);
        res.status(500).json({ error: 'Failed to delete voucher' });
    }
});

module.exports = router;
