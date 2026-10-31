const express = require('express');
const pool = require('../db');
const { authenticateToken, requirePermission } = require('../middleware/auth');
const { logAudit } = require('../services/audit');

const router = express.Router();

router.use(authenticateToken);

const CODE = /^[A-Z0-9-]{2,10}$/;
const TYPES = ['branch', 'warehouse'];
const COLUMNS = 'id, code, name, address, phone, type, is_active, settings, created_at, updated_at';

const toLocation = (row) => ({ ...row, is_active: !!row.is_active });

// Locations the user is assigned to (owners and global assignments see all).
// ?scope=destinations lists every location for users who may create transfers, so they can pick
// a destination they aren't assigned to (id, code, name and type only).
router.get('/', async (req, res) => {
    try {
        const { type, include_inactive } = req.query;
        const destinations = req.query.scope === 'destinations';
        if (destinations && !req.access.can('transfers.create')) {
            return res.status(403).json({ error: 'Akses tidak diizinkan' });
        }
        let query = `SELECT ${destinations ? 'id, code, name, type, is_active' : COLUMNS} FROM locations WHERE deleted_at IS NULL`;
        const params = [];

        const global = req.access.isOwner || req.access.assignments.some((a) => a.locationId === null);
        if (!global && !destinations) {
            const ids = req.access.assignments.map((a) => a.locationId);
            if (ids.length === 0) return res.json({ locations: [] });
            query += ` AND id IN (${ids.map(() => '?').join(', ')})`;
            params.push(...ids);
        }
        if (type && TYPES.includes(type)) {
            query += ' AND type = ?';
            params.push(type);
        }
        if (include_inactive !== 'true') {
            query += ' AND is_active = 1';
        }
        query += " ORDER BY type = 'warehouse' DESC, code";

        const [rows] = await pool.execute(query, params);
        res.json({ locations: rows.map(toLocation) });
    } catch (error) {
        console.error('Get locations error:', error);
        res.status(500).json({ error: 'Gagal mengambil data lokasi' });
    }
});

// A single location the user is assigned to (any role), or any location for global assignments.
router.get('/:locationId', async (req, res) => {
    try {
        const id = parseInt(req.params.locationId, 10);
        const global = req.access.isOwner || req.access.assignments.some((a) => a.locationId === null);
        if (!global && !req.access.assignments.some((a) => a.locationId === id)) {
            return res.status(403).json({ error: 'Akses tidak diizinkan' });
        }
        const [[location]] = await pool.execute(`SELECT ${COLUMNS} FROM locations WHERE id = ? AND deleted_at IS NULL`, [id]);
        if (!location) return res.status(404).json({ error: 'Lokasi tidak ditemukan' });
        res.json({ location: toLocation(location) });
    } catch (error) {
        console.error('Get location error:', error);
        res.status(500).json({ error: 'Gagal mengambil data lokasi' });
    }
});

// locations.manage at one location lets a user edit that location's details; creating locations and
// changing codes or active status need it at every location (owners).
const managesAll = (req) => req.access.locationsFor('locations.manage') === null;

router.post('/', requirePermission('locations.manage'), async (req, res) => {
    if (!managesAll(req)) return res.status(403).json({ error: 'Hanya owner yang dapat menambah lokasi' });
    const { code, name, type = 'branch', address, phone, settings } = req.body;
    const normalizedCode = typeof code === 'string' ? code.trim().toUpperCase() : '';

    if (!CODE.test(normalizedCode)) {
        return res.status(400).json({ error: 'Kode lokasi harus 2–10 karakter (A–Z, 0–9, -)' });
    }
    if (!name || !name.trim()) return res.status(400).json({ error: 'Nama lokasi wajib diisi' });
    if (!TYPES.includes(type)) return res.status(400).json({ error: 'Tipe lokasi harus branch atau warehouse' });
    if (settings !== undefined && (settings === null || typeof settings !== 'object' || Array.isArray(settings))) {
        return res.status(400).json({ error: 'settings harus berupa object' });
    }

    const conn = await pool.getConnection();
    try {
        await conn.beginTransaction();
        const [result] = await conn.execute(
            'INSERT INTO locations (code, name, type, address, phone, settings) VALUES (?, ?, ?, ?, ?, ?)',
            [normalizedCode, name.trim(), type, address || null, phone || null, settings ? JSON.stringify(settings) : null]
        );
        const [[location]] = await conn.execute(`SELECT ${COLUMNS} FROM locations WHERE id = ?`, [result.insertId]);
        await logAudit(conn, req, { action: 'create', entity: 'location', entityId: result.insertId, locationId: result.insertId, after: location });
        await conn.commit();

        res.status(201).json({ message: 'Lokasi berhasil dibuat', location: toLocation(location) });
    } catch (error) {
        await conn.rollback();
        if (error.code === 'ER_DUP_ENTRY') return res.status(400).json({ error: 'Kode lokasi sudah digunakan' });
        console.error('Create location error:', error);
        res.status(500).json({ error: 'Gagal membuat lokasi' });
    } finally {
        conn.release();
    }
});

// Locations are deactivated (is_active = false) rather than deleted, so history keeps resolving.
router.put('/:locationId', requirePermission('locations.manage'), async (req, res) => {
    const { code, name, address, phone, is_active, settings } = req.body;
    const updates = [];
    const params = [];

    if ((code !== undefined || is_active !== undefined) && !managesAll(req)) {
        return res.status(403).json({ error: 'Hanya owner yang dapat mengubah kode atau status lokasi' });
    }

    if (code !== undefined) {
        const normalizedCode = String(code).trim().toUpperCase();
        if (!CODE.test(normalizedCode)) {
            return res.status(400).json({ error: 'Kode lokasi harus 2–10 karakter (A–Z, 0–9, -)' });
        }
        updates.push('code = ?');
        params.push(normalizedCode);
    }
    if (name !== undefined) {
        if (!name || !String(name).trim()) return res.status(400).json({ error: 'Nama lokasi wajib diisi' });
        updates.push('name = ?');
        params.push(String(name).trim());
    }
    if (address !== undefined) {
        updates.push('address = ?');
        params.push(address || null);
    }
    if (phone !== undefined) {
        updates.push('phone = ?');
        params.push(phone || null);
    }
    if (is_active !== undefined) {
        updates.push('is_active = ?');
        params.push(is_active ? 1 : 0);
    }
    if (settings !== undefined) {
        if (settings !== null && (typeof settings !== 'object' || Array.isArray(settings))) {
            return res.status(400).json({ error: 'settings harus berupa object' });
        }
        updates.push('settings = ?');
        params.push(settings === null ? null : JSON.stringify(settings));
    }
    if (updates.length === 0) {
        return res.status(400).json({ error: 'Tidak ada field yang valid untuk diperbarui' });
    }

    const conn = await pool.getConnection();
    try {
        const [[before]] = await conn.execute(`SELECT ${COLUMNS} FROM locations WHERE id = ? AND deleted_at IS NULL`, [req.locationId]);
        if (!before) return res.status(404).json({ error: 'Lokasi tidak ditemukan' });

        await conn.beginTransaction();
        await conn.execute(`UPDATE locations SET ${updates.join(', ')} WHERE id = ?`, [...params, req.locationId]);
        const [[after]] = await conn.execute(`SELECT ${COLUMNS} FROM locations WHERE id = ?`, [req.locationId]);
        await logAudit(conn, req, { action: 'update', entity: 'location', entityId: req.locationId, locationId: req.locationId, before, after });
        await conn.commit();

        res.json({ message: 'Lokasi berhasil diperbarui', location: toLocation(after) });
    } catch (error) {
        await conn.rollback();
        if (error.code === 'ER_DUP_ENTRY') return res.status(400).json({ error: 'Kode lokasi sudah digunakan' });
        console.error('Update location error:', error);
        res.status(500).json({ error: 'Gagal memperbarui lokasi' });
    } finally {
        conn.release();
    }
});

module.exports = router;
