const express = require('express');
const pool = require('../db');
const { authenticateToken, requirePermission } = require('../middleware/auth');
const { PERMISSIONS, OWNER_ROLE_CODE, isValidPermission } = require('../auth/permissions');
const { syncLegacyFromAssignments } = require('../services/access');
const { logAudit } = require('../services/audit');

const router = express.Router();

router.use(authenticateToken);

// Listing roles/permissions is needed both to manage roles and to assign them to users.
const requireRoleOrUserManager = (req, res, next) => {
    if (req.access.can('roles.manage') || req.access.can('users.manage')) return next();
    return res.status(403).json({ error: 'Akses tidak diizinkan' });
};

const ROLE_NAME = /^[\p{L}\p{N} .\-]{2,50}$/u;

const loadRoles = async (db, where = '', params = []) => {
    const [rows] = await db.execute(
        `SELECT r.id, r.code, r.name, r.description, r.is_system,
                (SELECT COUNT(*) FROM user_locations ul WHERE ul.role_id = r.id) AS user_count,
                GROUP_CONCAT(rp.permission ORDER BY rp.permission) AS permissions
         FROM roles r
         LEFT JOIN role_permissions rp ON rp.role_id = r.id
         ${where}
         GROUP BY r.id
         ORDER BY r.is_system DESC, r.name`,
        params
    );
    return rows.map((r) => ({
        id: r.id,
        code: r.code,
        name: r.name,
        description: r.description,
        isSystem: !!r.is_system,
        userCount: Number(r.user_count),
        permissions: r.code === OWNER_ROLE_CODE ? Object.keys(PERMISSIONS) : (r.permissions ? r.permissions.split(',') : []),
    }));
};

// Checks a requested permission list. A non-owner may only hand out permissions they hold
// themselves, so roles.manage can't be used to escalate.
const validatePermissionList = (req, permissions) => {
    if (!Array.isArray(permissions)) return 'permissions harus berupa array';
    const invalid = permissions.filter((p) => !isValidPermission(p));
    if (invalid.length > 0) return `Izin tidak dikenal: ${invalid.join(', ')}`;
    if (!req.access.isOwner) {
        const notHeld = permissions.filter((p) => !req.access.can(p));
        if (notHeld.length > 0) return `Anda tidak dapat memberikan izin yang tidak Anda miliki: ${notHeld.join(', ')}`;
    }
    return null;
};

const replaceRolePermissions = async (conn, roleId, permissions) => {
    await conn.execute('DELETE FROM role_permissions WHERE role_id = ?', [roleId]);
    for (const permission of new Set(permissions)) {
        await conn.execute('INSERT INTO role_permissions (role_id, permission) VALUES (?, ?)', [roleId, permission]);
    }
};

// ── Permissions & roles ──────────────────────────────────────────────────────

router.get('/permissions', requireRoleOrUserManager, (req, res) => {
    const permissions = Object.entries(PERMISSIONS).map(([key, meta]) => ({ key, ...meta }));
    res.json({ permissions });
});

router.get('/roles', requireRoleOrUserManager, async (req, res) => {
    try {
        res.json({ roles: await loadRoles(pool) });
    } catch (error) {
        console.error('Get roles error:', error);
        res.status(500).json({ error: 'Gagal mengambil data role' });
    }
});

router.post('/roles', requirePermission('roles.manage'), async (req, res) => {
    const { name, description, permissions = [] } = req.body;

    if (!name || !ROLE_NAME.test(name.trim())) {
        return res.status(400).json({ error: 'Nama role harus 2–50 karakter (huruf, angka, spasi, titik, tanda hubung)' });
    }
    const permissionError = validatePermissionList(req, permissions);
    if (permissionError) return res.status(400).json({ error: permissionError });

    const conn = await pool.getConnection();
    try {
        await conn.beginTransaction();
        const [result] = await conn.execute(
            'INSERT INTO roles (name, description, is_system) VALUES (?, ?, 0)',
            [name.trim(), description || null]
        );
        await replaceRolePermissions(conn, result.insertId, permissions);
        await logAudit(conn, req, {
            action: 'create', entity: 'role', entityId: result.insertId,
            after: { name: name.trim(), description: description || null, permissions },
        });
        await conn.commit();

        const [role] = await loadRoles(pool, 'WHERE r.id = ?', [result.insertId]);
        res.status(201).json({ message: 'Role berhasil dibuat', role });
    } catch (error) {
        await conn.rollback();
        if (error.code === 'ER_DUP_ENTRY') {
            return res.status(400).json({ error: 'Nama role sudah digunakan' });
        }
        console.error('Create role error:', error);
        res.status(500).json({ error: 'Gagal membuat role' });
    } finally {
        conn.release();
    }
});

// System roles keep their name; their permissions can be changed (except the owner role).
router.put('/roles/:id', requirePermission('roles.manage'), async (req, res) => {
    const roleId = parseInt(req.params.id, 10);
    const { name, description, permissions } = req.body;

    const conn = await pool.getConnection();
    try {
        const [before] = await loadRoles(conn, 'WHERE r.id = ?', [roleId]);
        if (!before) return res.status(404).json({ error: 'Role tidak ditemukan' });
        if (before.code === OWNER_ROLE_CODE) {
            return res.status(403).json({ error: 'Role owner tidak dapat diubah' });
        }

        const updates = [];
        const params = [];
        if (name !== undefined && name.trim() !== before.name) {
            if (before.isSystem) return res.status(400).json({ error: 'Nama role sistem tidak dapat diubah' });
            if (!ROLE_NAME.test(name.trim())) {
                return res.status(400).json({ error: 'Nama role harus 2–50 karakter (huruf, angka, spasi, titik, tanda hubung)' });
            }
            updates.push('name = ?');
            params.push(name.trim());
        }
        if (description !== undefined) {
            updates.push('description = ?');
            params.push(description || null);
        }
        if (permissions !== undefined) {
            const permissionError = validatePermissionList(req, permissions);
            if (permissionError) return res.status(400).json({ error: permissionError });
        }

        await conn.beginTransaction();
        if (updates.length > 0) {
            await conn.execute(`UPDATE roles SET ${updates.join(', ')} WHERE id = ?`, [...params, roleId]);
        }
        if (permissions !== undefined) {
            await replaceRolePermissions(conn, roleId, permissions);
        }
        const [after] = await loadRoles(conn, 'WHERE r.id = ?', [roleId]);
        await logAudit(conn, req, {
            action: 'update', entity: 'role', entityId: roleId,
            before: { name: before.name, description: before.description, permissions: before.permissions },
            after: { name: after.name, description: after.description, permissions: after.permissions },
        });
        await conn.commit();

        res.json({ message: 'Role berhasil diperbarui', role: after });
    } catch (error) {
        await conn.rollback();
        if (error.code === 'ER_DUP_ENTRY') {
            return res.status(400).json({ error: 'Nama role sudah digunakan' });
        }
        console.error('Update role error:', error);
        res.status(500).json({ error: 'Gagal memperbarui role' });
    } finally {
        conn.release();
    }
});

router.delete('/roles/:id', requirePermission('roles.manage'), async (req, res) => {
    const roleId = parseInt(req.params.id, 10);

    const conn = await pool.getConnection();
    try {
        const [role] = await loadRoles(conn, 'WHERE r.id = ?', [roleId]);
        if (!role) return res.status(404).json({ error: 'Role tidak ditemukan' });
        if (role.isSystem) return res.status(400).json({ error: 'Role sistem tidak dapat dihapus' });
        if (role.userCount > 0) {
            return res.status(400).json({ error: 'Role masih digunakan oleh pengguna' });
        }

        await conn.beginTransaction();
        await conn.execute('DELETE FROM roles WHERE id = ?', [roleId]);
        await logAudit(conn, req, {
            action: 'delete', entity: 'role', entityId: roleId,
            before: { name: role.name, description: role.description, permissions: role.permissions },
        });
        await conn.commit();

        res.json({ message: 'Role berhasil dihapus' });
    } catch (error) {
        await conn.rollback();
        console.error('Delete role error:', error);
        res.status(500).json({ error: 'Gagal menghapus role' });
    } finally {
        conn.release();
    }
});

// ── User assignments ─────────────────────────────────────────────────────────

const loadAssignments = async (db, userId) => {
    const [rows] = await db.execute(
        `SELECT ul.location_id, l.code AS location_code, l.name AS location_name, l.type AS location_type,
                r.id AS role_id, r.code AS role_code, r.name AS role_name
         FROM user_locations ul
         JOIN roles r ON r.id = ul.role_id
         LEFT JOIN locations l ON l.id = ul.location_id
         WHERE ul.user_id = ?
         ORDER BY ul.location_id IS NOT NULL, ul.location_id`,
        [userId]
    );
    return rows.map((r) => ({
        locationId: r.location_id,
        locationCode: r.location_code,
        locationName: r.location_name,
        locationType: r.location_type,
        roleId: r.role_id,
        roleCode: r.role_code,
        roleName: r.role_name,
    }));
};

// Non-owners only see and change assignments at locations where they hold users.manage.
const inScope = (scope, locationId) => scope === null || (locationId !== null && scope.includes(locationId));

router.get('/users/:id/assignments', requirePermission('users.manage'), async (req, res) => {
    try {
        const userId = parseInt(req.params.id, 10);
        const [users] = await pool.execute('SELECT id FROM users WHERE id = ?', [userId]);
        if (users.length === 0) return res.status(404).json({ error: 'Pengguna tidak ditemukan' });

        const scope = req.access.locationsFor('users.manage');
        const assignments = await loadAssignments(pool, userId);
        if (scope !== null && !assignments.some((a) => inScope(scope, a.locationId))) {
            return res.status(403).json({ error: 'Pengguna ini tidak berada di lokasi Anda' });
        }

        res.json({ assignments });
    } catch (error) {
        console.error('Get assignments error:', error);
        res.status(500).json({ error: 'Gagal mengambil penugasan pengguna' });
    }
});

// Body: { assignments: [{ location_id: number|null, role_id: number }] }
// location_id null = the role applies at every location (owner only).
// For a non-owner, assignments outside their own locations are left untouched.
router.put('/users/:id/assignments', requirePermission('users.manage'), async (req, res) => {
    const userId = parseInt(req.params.id, 10);
    const requested = req.body.assignments;

    if (!Array.isArray(requested)) {
        return res.status(400).json({ error: 'assignments harus berupa array' });
    }
    if (userId === req.user.id) {
        return res.status(400).json({ error: 'Anda tidak dapat mengubah penugasan Anda sendiri' });
    }

    const conn = await pool.getConnection();
    try {
        const [users] = await conn.execute('SELECT id FROM users WHERE id = ?', [userId]);
        if (users.length === 0) return res.status(404).json({ error: 'Pengguna tidak ditemukan' });

        const before = await loadAssignments(conn, userId);
        const isOwner = req.access.isOwner;
        const scope = req.access.locationsFor('users.manage');

        if (!isOwner && before.some((a) => a.roleCode === OWNER_ROLE_CODE)) {
            return res.status(403).json({ error: 'Anda tidak dapat mengubah penugasan owner' });
        }

        const [roleRows] = await conn.execute(
            `SELECT r.id, r.code, GROUP_CONCAT(rp.permission) AS permissions
             FROM roles r LEFT JOIN role_permissions rp ON rp.role_id = r.id
             GROUP BY r.id`
        );
        const roles = new Map(roleRows.map((r) => [r.id, { code: r.code, permissions: r.permissions ? r.permissions.split(',') : [] }]));

        const [locationRows] = await conn.execute('SELECT id FROM locations WHERE is_active = 1 AND deleted_at IS NULL');
        const activeLocations = new Set(locationRows.map((l) => l.id));

        const seenLocations = new Set();
        const normalized = [];
        for (const item of requested) {
            const locationId = item.location_id === null || item.location_id === undefined ? null : Number(item.location_id);
            const roleId = Number(item.role_id);
            const role = roles.get(roleId);

            if (!role) return res.status(400).json({ error: `Role ${item.role_id} tidak ditemukan` });
            if (locationId !== null && !activeLocations.has(locationId)) {
                return res.status(400).json({ error: `Lokasi ${item.location_id} tidak ditemukan atau tidak aktif` });
            }
            const key = locationId === null ? 'all' : locationId;
            if (seenLocations.has(key)) {
                return res.status(400).json({ error: 'Satu lokasi hanya boleh memiliki satu role per pengguna' });
            }
            seenLocations.add(key);

            if (role.code === OWNER_ROLE_CODE && locationId !== null) {
                return res.status(400).json({ error: 'Role owner berlaku untuk semua lokasi (location_id harus null)' });
            }
            if (!isOwner) {
                if (role.code === OWNER_ROLE_CODE || locationId === null) {
                    return res.status(403).json({ error: 'Hanya owner yang dapat memberikan akses ke semua lokasi' });
                }
                if (!inScope(scope, locationId)) {
                    return res.status(403).json({ error: `Anda tidak mengelola pengguna di lokasi ${locationId}` });
                }
                const notHeld = role.permissions.filter((p) => !req.access.can(p, locationId));
                if (notHeld.length > 0) {
                    return res.status(403).json({ error: `Role ini memiliki izin yang tidak Anda miliki di lokasi tersebut: ${notHeld.join(', ')}` });
                }
            }
            normalized.push({ locationId, roleId });
        }

        await conn.beginTransaction();
        if (isOwner) {
            await conn.execute('DELETE FROM user_locations WHERE user_id = ?', [userId]);
        } else if (scope === null) {
            // Non-owner with users.manage at every location: global assignments stay owner-only.
            await conn.execute('DELETE FROM user_locations WHERE user_id = ? AND location_id IS NOT NULL', [userId]);
        } else {
            for (const locationId of scope) {
                await conn.execute('DELETE FROM user_locations WHERE user_id = ? AND location_id = ?', [userId, locationId]);
            }
        }
        for (const a of normalized) {
            await conn.execute(
                'INSERT INTO user_locations (user_id, location_id, role_id) VALUES (?, ?, ?)',
                [userId, a.locationId, a.roleId]
            );
        }
        await syncLegacyFromAssignments(conn, userId);

        const after = await loadAssignments(conn, userId);
        await logAudit(conn, req, {
            action: 'update', entity: 'user_assignments', entityId: userId,
            before: before.map(({ locationId, roleId }) => ({ locationId, roleId })),
            after: after.map(({ locationId, roleId }) => ({ locationId, roleId })),
        });
        await conn.commit();

        res.json({ message: 'Penugasan pengguna berhasil diperbarui', assignments: after });
    } catch (error) {
        await conn.rollback();
        console.error('Update assignments error:', error);
        res.status(500).json({ error: 'Gagal memperbarui penugasan pengguna' });
    } finally {
        conn.release();
    }
});

module.exports = router;
