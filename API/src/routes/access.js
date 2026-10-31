const express = require('express');
const pool = require('../db');
const { authenticateToken, requirePermission } = require('../middleware/auth');
const { PERMISSIONS, OWNER_ROLE_CODE, isValidPermission } = require('../auth/permissions');
const { loadAssignments, inScope, normalizeAssignments, replaceAssignments } = require('../services/access');
const { AppError, withTransaction } = require('../utils/transaction');
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
    if (userId === req.user.id) {
        return res.status(400).json({ error: 'Anda tidak dapat mengubah penugasan Anda sendiri' });
    }

    const result = await withTransaction(res, 'Gagal memperbarui penugasan pengguna', async (conn) => {
        const [users] = await conn.execute('SELECT id FROM users WHERE id = ? FOR UPDATE', [userId]);
        if (users.length === 0) throw new AppError('Pengguna tidak ditemukan', 404);

        const before = await loadAssignments(conn, userId);
        if (!req.access.isOwner && before.some((a) => a.roleCode === OWNER_ROLE_CODE)) {
            throw new AppError('Anda tidak dapat mengubah penugasan owner', 403);
        }
        const normalized = await normalizeAssignments(conn, req.access, req.body.assignments);
        await replaceAssignments(conn, req.access, userId, normalized);

        const after = await loadAssignments(conn, userId);
        await logAudit(conn, req, {
            action: 'update', entity: 'user_assignments', entityId: userId,
            before: before.map(({ locationId, roleId }) => ({ locationId, roleId })),
            after: after.map(({ locationId, roleId }) => ({ locationId, roleId })),
        });
        return after;
    });
    if (result) res.json({ message: 'Penugasan pengguna berhasil diperbarui', assignments: result });
});

module.exports = router;
