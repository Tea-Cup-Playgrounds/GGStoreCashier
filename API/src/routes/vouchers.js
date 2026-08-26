const express = require('express');
const pool = require('../db');
const { authenticateToken, requireRole } = require('../middleware/auth');
const { broadcastToEntity } = require('../utils/socket_broadcast');

const router = express.Router();
router.use(authenticateToken);

// ── GET /api/vouchers — list all with status (admin + superadmin) ─────────────
router.get('/', requireRole(['admin', 'superadmin']), async (req, res) => {
    try {
        const [rows] = await pool.execute(
            'SELECT * FROM vouchers ORDER BY created_at DESC'
        );
        const today = new Date().toISOString().slice(0, 10);
        const vouchers = rows.map(v => _enrichVoucher(v, today));
        res.json({ vouchers });
    } catch (err) {
        console.error('List vouchers error:', err);
        res.status(500).json({ error: 'Gagal mengambil data voucher' });
    }
});

// ── GET /api/vouchers/validate/:code — validate (any authenticated user) ───────
router.get('/validate/:code', async (req, res) => {
    try {
        const code = req.params.code.trim().toUpperCase();
        const today = new Date().toISOString().slice(0, 10);

        const [rows] = await pool.execute(
            'SELECT * FROM vouchers WHERE UPPER(code) = ? LIMIT 1',
            [code]
        );

        if (rows.length === 0) {
            return res.status(404).json({ error: 'Kode voucher tidak ditemukan' });
        }

        const voucher = rows[0];
        const reason = _getUnavailableReason(voucher, today);

        if (reason) {
            return res.status(400).json({ error: reason });
        }

        res.json({ voucher: _enrichVoucher(voucher, today) });
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
            max_uses = null,
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
        if (max_uses !== null && max_uses !== undefined && max_uses <= 0) {
            return res.status(400).json({ error: 'Batas penggunaan harus lebih dari 0' });
        }

        const [result] = await pool.execute(
            `INSERT INTO vouchers
             (code, description, target_type, target_id, discount_type, discount_value,
              valid_from, valid_to, is_active, max_uses, used_count)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)`,
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
                max_uses != null ? parseInt(max_uses) : null,
            ]
        );

        const [created] = await pool.execute('SELECT * FROM vouchers WHERE id = ?', [result.insertId]);
        const today = new Date().toISOString().slice(0, 10);

        const io = req.app.get('io');
        broadcastToEntity(io, 'vouchers', 'voucher-created', _enrichVoucher(created[0], today));

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
            max_uses,
        } = req.body;

        if (!code || !discount_type || discount_value == null) {
            return res.status(400).json({
                error: 'Kode, tipe diskon, dan nilai diskon wajib diisi'
            });
        }
        if (max_uses !== null && max_uses !== undefined && max_uses <= 0) {
            return res.status(400).json({ error: 'Batas penggunaan harus lebih dari 0' });
        }

        const [result] = await pool.execute(
            `UPDATE vouchers SET
               code = ?, description = ?, target_type = ?, target_id = ?,
               discount_type = ?, discount_value = ?,
               valid_from = ?, valid_to = ?, is_active = ?,
               max_uses = ?
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
                max_uses != null ? parseInt(max_uses) : null,
                req.params.id,
            ]
        );

        if (result.affectedRows === 0) {
            return res.status(404).json({ error: 'Voucher tidak ditemukan' });
        }

        const [updated] = await pool.execute('SELECT * FROM vouchers WHERE id = ?', [req.params.id]);
        const today = new Date().toISOString().slice(0, 10);

        const io = req.app.get('io');
        broadcastToEntity(io, 'vouchers', 'voucher-updated', _enrichVoucher(updated[0], today));

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
        const [voucher] = await pool.execute('SELECT * FROM vouchers WHERE id = ?', [req.params.id]);

        const [result] = await pool.execute(
            'DELETE FROM vouchers WHERE id = ?',
            [req.params.id]
        );

        if (result.affectedRows === 0) {
            return res.status(404).json({ error: 'Voucher tidak ditemukan' });
        }

        const io = req.app.get('io');
        if (voucher.length > 0) {
            broadcastToEntity(io, 'vouchers', 'voucher-deleted', { id: voucher[0].id });
        }

        res.json({ message: 'Voucher berhasil dihapus' });
    } catch (err) {
        console.error('Delete voucher error:', err);
        res.status(500).json({ error: 'Gagal menghapus voucher' });
    }
});

// ── Helpers ───────────────────────────────────────────────────────────────────

/**
 * Returns the human-readable reason a voucher cannot be used, or null if it can.
 */
function _getUnavailableReason(v, today) {
    if (!v.is_active) return 'Voucher tidak aktif';
    if (v.valid_from && v.valid_from > today) return `Voucher belum berlaku (mulai ${v.valid_from})`;
    if (v.valid_to && v.valid_to < today) return 'Voucher sudah kadaluarsa';
    if (v.max_uses !== null && v.max_uses !== undefined && v.used_count >= v.max_uses) {
        return 'Batas penggunaan voucher sudah habis';
    }
    return null;
}

/**
 * Attach computed fields so the Flutter client can determine status without re-deriving.
 */
function _enrichVoucher(v, today) {
    const reason = _getUnavailableReason(v, today);
    return {
        ...v,
        is_available: reason === null,
        unavailable_reason: reason,
    };
}

module.exports = router;
module.exports.incrementUsedCount = async function(voucherId, connection) {
    await (connection || pool).execute(
        'UPDATE vouchers SET used_count = used_count + 1 WHERE id = ?',
        [voucherId]
    );
};
