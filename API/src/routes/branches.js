const express = require('express');
const bcrypt = require('bcrypt');
const pool = require('../db');
const { authenticateToken, requireRole } = require('../middleware/auth');

const router = express.Router();
router.use(authenticateToken);

// GET /api/branches
router.get('/', async (_req, res) => {
    try {
        const [branches] = await pool.execute(
            'SELECT id, name, address, phone, target_pendapatan, created_at, updated_at FROM branches ORDER BY name ASC'
        );
        res.json({ branches });
    } catch (err) {
        console.error('Get branches error:', err);
        res.status(500).json({ error: 'Gagal mengambil data cabang' });
    }
});

// GET /api/branches/:id
router.get('/:id', async (req, res) => {
    try {
        const [rows] = await pool.execute(
            'SELECT id, name, address, phone, target_pendapatan, created_at, updated_at FROM branches WHERE id = ?',
            [req.params.id]
        );
        if (rows.length === 0) return res.status(404).json({ error: 'Cabang tidak ditemukan' });
        res.json({ branch: rows[0] });
    } catch (err) {
        console.error('Get branch error:', err);
        res.status(500).json({ error: 'Gagal mengambil data cabang' });
    }
});

// POST /api/branches/with-admin  — create branch + first admin in one transaction
// Must be registered BEFORE POST '/' so Express doesn't treat 'with-admin' as an :id param
router.post('/with-admin', requireRole(['superadmin']), async (req, res) => {
    const { name, address, phone, target_pendapatan, admin } = req.body;
    if (!name) return res.status(400).json({ error: 'Nama cabang wajib diisi' });
    if (!admin?.name || !admin?.username || !admin?.password) {
        return res.status(400).json({ error: 'Data admin (name, username, password) wajib diisi' });
    }

    const connection = await pool.getConnection();
    try {
        await connection.beginTransaction();

        const [existing] = await connection.execute('SELECT id FROM users WHERE username = ?', [admin.username]);
        if (existing.length > 0) {
            await connection.rollback();
            return res.status(400).json({ error: 'Username admin sudah digunakan' });
        }

        const [branchRes] = await connection.execute(
            'INSERT INTO branches (name, address, phone, target_pendapatan) VALUES (?, ?, ?, ?)',
            [name, address || null, phone || null, target_pendapatan || null]
        );
        const branchId = branchRes.insertId;

        const hashed = await bcrypt.hash(admin.password, 12);
        const [userRes] = await connection.execute(
            'INSERT INTO users (name, username, password, role, branch_id) VALUES (?, ?, ?, ?, ?)',
            [admin.name, admin.username, hashed, 'admin', branchId]
        );

        await connection.commit();
        res.status(201).json({
            message: 'Cabang dan admin berhasil dibuat',
            branchId,
            userId: userRes.insertId,
        });
    } catch (err) {
        await connection.rollback();
        console.error('Create branch with-admin error:', err);
        res.status(500).json({ error: 'Gagal membuat cabang dan admin' });
    } finally {
        connection.release();
    }
});

// POST /api/branches
router.post('/', requireRole(['superadmin']), async (req, res) => {
    try {
        const { name, address, phone, target_pendapatan } = req.body;
        if (!name) return res.status(400).json({ error: 'Nama cabang wajib diisi' });

        const [result] = await pool.execute(
            'INSERT INTO branches (name, address, phone, target_pendapatan) VALUES (?, ?, ?, ?)',
            [name, address || null, phone || null, target_pendapatan || null]
        );
        res.status(201).json({ message: 'Cabang berhasil dibuat', branchId: result.insertId });
    } catch (err) {
        console.error('Create branch error:', err);
        res.status(500).json({ error: 'Gagal membuat cabang' });
    }
});

// PUT /api/branches/:id  — superadmin: any; admin: own branch only
router.put('/:id', async (req, res) => {
    try {
        const { role, branch_id } = req.user;
        const targetId = parseInt(req.params.id, 10);

        if (role === 'karyawan') return res.status(403).json({ error: 'Akses tidak diizinkan' });
        if (role === 'admin' && branch_id !== targetId) {
            return res.status(403).json({ error: 'Anda hanya dapat mengedit cabang Anda sendiri' });
        }
        if (role === 'admin' && targetId === 0) {
            return res.status(403).json({ error: 'Tidak dapat mengedit cabang global' });
        }

        const { name, address, phone, target_pendapatan } = req.body;
        if (!name) return res.status(400).json({ error: 'Nama cabang wajib diisi' });

        const [result] = await pool.execute(
            'UPDATE branches SET name = ?, address = ?, phone = ?, target_pendapatan = ?, updated_at = NOW() WHERE id = ?',
            [name, address || null, phone || null, target_pendapatan ?? null, targetId]
        );
        if (result.affectedRows === 0) return res.status(404).json({ error: 'Cabang tidak ditemukan' });

        res.json({ message: 'Cabang berhasil diperbarui' });
    } catch (err) {
        console.error('Update branch error:', err);
        res.status(500).json({ error: 'Gagal memperbarui cabang' });
    }
});

// DELETE /api/branches/:id  — superadmin only
router.delete('/:id', requireRole(['superadmin']), async (req, res) => {
    try {
        if (req.params.id === '0') {
            return res.status(400).json({ error: 'Tidak dapat menghapus cabang utama' });
        }

        const [[{ count: userCount }]] = await pool.execute(
            'SELECT COUNT(*) as count FROM users WHERE branch_id = ?', [req.params.id]
        );
        const [[{ count: productCount }]] = await pool.execute(
            'SELECT COUNT(*) as count FROM products WHERE branch_id = ?', [req.params.id]
        );

        if (userCount > 0 || productCount > 0) {
            return res.status(400).json({
                error: 'Tidak dapat menghapus cabang yang masih memiliki pengguna atau produk'
            });
        }

        const [result] = await pool.execute('DELETE FROM branches WHERE id = ?', [req.params.id]);
        if (result.affectedRows === 0) return res.status(404).json({ error: 'Cabang tidak ditemukan' });

        res.json({ message: 'Cabang berhasil dihapus' });
    } catch (err) {
        console.error('Delete branch error:', err);
        res.status(500).json({ error: 'Gagal menghapus cabang' });
    }
});

module.exports = router;
