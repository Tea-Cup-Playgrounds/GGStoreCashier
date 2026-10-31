const express = require('express');
const pool = require('../db');
const { authenticateToken, requireRole } = require('../middleware/auth');
const { assignDefaultLocationCode } = require('../services/locations');

const router = express.Router();

// Apply authentication to all routes
router.use(authenticateToken);

// Get all branches
router.get('/', async (req, res) => {
    try {
        const [branches] = await pool.execute(
            'SELECT * FROM branches ORDER BY name ASC'
        );
        res.json({ branches });

    } catch (error) {
        console.error('Get branches error:', error);
        res.status(500).json({ error: 'Gagal mengambil data cabang' });
    }
});

// Get branch by ID
router.get('/:id', async (req, res) => {
    try {
        const [branches] = await pool.execute(
            'SELECT * FROM branches WHERE id = ?',
            [req.params.id]
        );

        if (branches.length === 0) {
            return res.status(404).json({ error: 'Cabang tidak ditemukan' });
        }

        res.json({ branch: branches[0] });

    } catch (error) {
        console.error('Get branch error:', error);
        res.status(500).json({ error: 'Gagal mengambil data cabang' });
    }
});

// Create new branch (superadmin only)
router.post('/', requireRole(['superadmin']), async (req, res) => {
    try {
        const { name, address, phone } = req.body;

        if (!name) {
            return res.status(400).json({ 
                error: 'Nama cabang wajib diisi' 
            });
        }

        const [result] = await pool.execute(
            'INSERT INTO branches (name, address, phone) VALUES (?, ?, ?)',
            [name, address || null, phone || null]
        );
        await assignDefaultLocationCode(pool, result.insertId);

        res.status(201).json({ 
            message: 'Cabang berhasil dibuat',
            branchId: result.insertId 
        });

    } catch (error) {
        console.error('Create branch error:', error);
        res.status(500).json({ error: 'Gagal membuat cabang' });
    }
});

// Update branch
// - superadmin: can update any branch
// - admin: can only update their own assigned branch
router.put('/:id', async (req, res) => {
    try {
        const { role, branch_id } = req.user;
        const targetId = parseInt(req.params.id, 10);

        // Role check
        if (role === 'karyawan') {
            return res.status(403).json({ error: 'Akses tidak diizinkan' });
        }

        // Admin can only edit their own branch
        if (role === 'admin' && branch_id !== targetId) {
            return res.status(403).json({ error: 'Anda hanya dapat mengedit cabang Anda sendiri' });
        }

        // Prevent editing the global "Semua Branch" (id = 0) by admins
        if (role === 'admin' && targetId === 0) {
            return res.status(403).json({ error: 'Tidak dapat mengedit cabang global' });
        }

        const { name, address, phone } = req.body;

        if (!name) {
            return res.status(400).json({ error: 'Nama cabang wajib diisi' });
        }

        const [result] = await pool.execute(
            'UPDATE branches SET name = ?, address = ?, phone = ?, updated_at = NOW() WHERE id = ?',
            [name, address || null, phone || null, targetId]
        );

        if (result.affectedRows === 0) {
            return res.status(404).json({ error: 'Cabang tidak ditemukan' });
        }

        res.json({ message: 'Cabang berhasil diperbarui' });

    } catch (error) {
        console.error('Update branch error:', error);
        res.status(500).json({ error: 'Gagal memperbarui cabang' });
    }
});

// Delete branch (superadmin only)
router.delete('/:id', requireRole(['superadmin']), async (req, res) => {
    try {
        // Prevent deletion of "Semua Branch" (id = 0)
        if (req.params.id === '0') {
            return res.status(400).json({ 
                error: 'Tidak dapat menghapus cabang utama' 
            });
        }

        // Check if branch has users or products
        const [users] = await pool.execute(
            `SELECT COUNT(*) as count FROM users
             WHERE branch_id = ? OR id IN (SELECT user_id FROM user_locations WHERE location_id = ?)`,
            [req.params.id, req.params.id]
        );

        // Any stock row or stock history ties the branch to the ledger.
        const [products] = await pool.execute(
            `SELECT (SELECT COUNT(*) FROM stock_levels WHERE location_id = ?)
                  + (SELECT COUNT(*) FROM stock_movements WHERE location_id = ?) as count`,
            [req.params.id, req.params.id]
        );

        if (users[0].count > 0 || products[0].count > 0) {
            return res.status(400).json({ 
                error: 'Tidak dapat menghapus cabang yang masih memiliki pengguna atau produk' 
            });
        }

        const [result] = await pool.execute(
            'DELETE FROM branches WHERE id = ?',
            [req.params.id]
        );

        if (result.affectedRows === 0) {
            return res.status(404).json({ error: 'Cabang tidak ditemukan' });
        }

        res.json({ message: 'Cabang berhasil dihapus' });

    } catch (error) {
        console.error('Delete branch error:', error);
        res.status(500).json({ error: 'Gagal menghapus cabang' });
    }
});

module.exports = router;
