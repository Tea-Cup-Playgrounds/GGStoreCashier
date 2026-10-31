const express = require('express');
const bcrypt = require('bcrypt');
const pool = require('../db');
const { authenticateToken, requirePermission } = require('../middleware/auth');
const { OWNER_ROLE_CODE } = require('../auth/permissions');
const { loadAssignments, assertCanManageUser, normalizeAssignments, replaceAssignments } = require('../services/access');
const { logAudit } = require('../services/audit');
const { AppError, withTransaction } = require('../utils/transaction');

const router = express.Router();

// Security RegEx patterns for input validation
const SECURITY_PATTERNS = {
    // Prevent script injection and malicious code
    SCRIPT_INJECTION: /<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi,
    HTML_TAGS: /<[^>]*>/g,
    SQL_INJECTION: /(union|select|insert|update|delete|drop|create|alter|exec|execute|script|javascript|vbscript|onload|onerror|onclick)/i,
    XSS_PATTERNS: /(javascript:|data:|vbscript:|onload=|onerror=|onclick=|onmouseover=|onfocus=|onblur=)/i,

    // Valid input patterns
    NAME: /^[a-zA-Z\s\-'\.]{2,50}$/,
    USERNAME: /^[a-zA-Z0-9_\-\.]{3,30}$/,
};

// Password strength validation
const validatePasswordStrength = (password) => {
    const minLength = 8;
    const hasUpperCase = /[A-Z]/.test(password);
    const hasLowerCase = /[a-z]/.test(password);
    const hasNumbers = /\d/.test(password);
    const hasSpecialChar = /[!@#$%^&*(),.?":{}|<>]/.test(password);

    const score = [
        password.length >= minLength,
        hasUpperCase,
        hasLowerCase,
        hasNumbers,
        hasSpecialChar
    ].filter(Boolean).length;

    return {
        isValid: score >= 3 && password.length >= minLength,
        score,
        requirements: {
            minLength: password.length >= minLength,
            hasUpperCase,
            hasLowerCase,
            hasNumbers,
            hasSpecialChar
        }
    };
};

// Input sanitization function
const sanitizeInput = (input) => {
    if (typeof input !== 'string') return input;

    return input
        .replace(SECURITY_PATTERNS.SCRIPT_INJECTION, '')
        .replace(SECURITY_PATTERNS.HTML_TAGS, '')
        .trim();
};

// Validate input against malicious patterns
const validateInput = (input) => {
    if (typeof input !== 'string') return true;

    return !SECURITY_PATTERNS.SQL_INJECTION.test(input) &&
           !SECURITY_PATTERNS.XSS_PATTERNS.test(input) &&
           !SECURITY_PATTERNS.SCRIPT_INJECTION.test(input);
};

const checkName = (name) => {
    const value = sanitizeInput(name);
    if (!validateInput(value) || !SECURITY_PATTERNS.NAME.test(value)) {
        throw new AppError('Nama harus 2–50 karakter dan hanya boleh mengandung huruf, spasi, tanda hubung, apostrof, dan titik');
    }
    return value;
};

const checkUsername = (username) => {
    const value = sanitizeInput(username);
    if (!validateInput(value) || !SECURITY_PATTERNS.USERNAME.test(value)) {
        throw new AppError('Username harus 3–30 karakter dan hanya boleh mengandung huruf, angka, garis bawah, tanda hubung, dan titik');
    }
    return value;
};

const hashPassword = async (password) => {
    const validation = validatePasswordStrength(String(password));
    if (!validation.isValid) {
        const error = new AppError('Password tidak memenuhi persyaratan keamanan');
        error.passwordRequirements = validation.requirements;
        throw error;
    }
    return bcrypt.hash(String(password), 12);
};

// Sends AppErrors raised outside a transaction (password requirements included).
const sendError = (res, error, fallback) => {
    if (error instanceof AppError) {
        return res.status(error.status).json({
            error: error.message,
            ...(error.passwordRequirements ? { passwordRequirements: error.passwordRequirements } : {}),
        });
    }
    console.error(`${fallback}:`, error);
    return res.status(500).json({ error: fallback });
};

const USER_COLUMNS = 'u.id, u.name, u.username, u.is_active, u.last_active_at, u.created_at, u.updated_at';

const toUser = (row, assignments) => ({
    ...row,
    is_active: !!row.is_active,
    assignments: assignments.map((a) => ({
        location_id: a.locationId,
        location_code: a.locationCode,
        location_name: a.locationName,
        location_type: a.locationType,
        role_id: a.roleId,
        role_code: a.roleCode,
        role_name: a.roleName,
    })),
});

// Assignments for many users at once, keyed by user id.
const assignmentsByUser = async (db, userIds) => {
    const byUser = new Map(userIds.map((id) => [id, []]));
    if (userIds.length === 0) return byUser;
    const [rows] = await db.query(
        `SELECT ul.user_id, ul.location_id, l.code AS location_code, l.name AS location_name, l.type AS location_type,
                r.id AS role_id, r.code AS role_code, r.name AS role_name
         FROM user_locations ul
         JOIN roles r ON r.id = ul.role_id
         LEFT JOIN locations l ON l.id = ul.location_id
         WHERE ul.user_id IN (?)
         ORDER BY ul.location_id IS NOT NULL, ul.location_id`,
        [userIds]
    );
    for (const r of rows) {
        byUser.get(r.user_id).push({
            locationId: r.location_id, locationCode: r.location_code, locationName: r.location_name,
            locationType: r.location_type, roleId: r.role_id, roleCode: r.role_code, roleName: r.role_name,
        });
    }
    return byUser;
};

// users.username has no unique index (legacy schema), so uniqueness is checked here.
const assertUsernameFree = async (db, username, exceptId = 0) => {
    const [rows] = await db.execute('SELECT id FROM users WHERE username = ? AND id <> ?', [username, exceptId]);
    if (rows.length > 0) throw new AppError('Username sudah digunakan');
};

// Loads a user the acting user may manage, or throws (404 / 403).
const loadManagedUser = async (db, access, userId, { lock = false } = {}) => {
    const [rows] = await db.execute(`SELECT ${USER_COLUMNS} FROM users u WHERE u.id = ?${lock ? ' FOR UPDATE' : ''}`, [userId]);
    if (rows.length === 0) throw new AppError('Pengguna tidak ditemukan', 404);
    const assignments = await loadAssignments(db, userId);
    assertCanManageUser(access, assignments);
    return { user: rows[0], assignments };
};

// Apply authentication to all routes
router.use(authenticateToken);

// Password strength check endpoint
router.post('/check-password-strength', requirePermission('users.manage'), (req, res) => {
    const { password } = req.body;
    if (!password) {
        return res.status(400).json({ error: 'Password wajib diisi' });
    }
    res.json(validatePasswordStrength(String(password)));
});

// GET /api/users?search=&location_id=&role_id=&include_inactive=true&page=1&limit=10
// Owners see everyone. Others see non-owner users assigned to a location where they hold users.manage.
router.get('/', requirePermission('users.manage'), async (req, res) => {
    try {
        const pageNum = Math.max(parseInt(req.query.page, 10) || 1, 1);
        const limitNum = Math.min(Math.max(parseInt(req.query.limit, 10) || 10, 1), 100);
        const offsetNum = (pageNum - 1) * limitNum;

        const where = ['1=1'];
        const params = [];

        const scope = req.access.locationsFor('users.manage');
        if (scope !== null) {
            if (scope.length === 0) return res.json({ users: [], pagination: { page: pageNum, limit: limitNum, total: 0, totalPages: 0 } });
            where.push(`EXISTS (SELECT 1 FROM user_locations s WHERE s.user_id = u.id AND s.location_id IN (${scope.map(() => '?').join(', ')}))`);
            params.push(...scope);
        }
        if (!req.access.isOwner) {
            where.push(`NOT EXISTS (SELECT 1 FROM user_locations o JOIN roles r ON r.id = o.role_id WHERE o.user_id = u.id AND r.code = ?)`);
            params.push(OWNER_ROLE_CODE);
        }

        const locationId = parseInt(req.query.location_id, 10);
        if (locationId > 0) {
            where.push('EXISTS (SELECT 1 FROM user_locations f WHERE f.user_id = u.id AND (f.location_id = ? OR f.location_id IS NULL))');
            params.push(locationId);
        }
        const roleId = parseInt(req.query.role_id, 10);
        if (roleId > 0) {
            where.push('EXISTS (SELECT 1 FROM user_locations f WHERE f.user_id = u.id AND f.role_id = ?)');
            params.push(roleId);
        }
        if (req.query.include_inactive !== 'true') where.push('u.is_active = 1');

        if (req.query.search) {
            const search = sanitizeInput(String(req.query.search));
            if (validateInput(search)) {
                where.push('(u.name LIKE ? OR u.username LIKE ?)');
                params.push(`%${search}%`, `%${search}%`);
            }
        }

        const [rows] = await pool.execute(
            `SELECT ${USER_COLUMNS} FROM users u WHERE ${where.join(' AND ')}
             ORDER BY u.is_active DESC, u.name LIMIT ${limitNum} OFFSET ${offsetNum}`,
            params
        );
        const [[{ total }]] = await pool.execute(`SELECT COUNT(*) AS total FROM users u WHERE ${where.join(' AND ')}`, params);
        const assignments = await assignmentsByUser(pool, rows.map((r) => r.id));

        res.json({
            users: rows.map((r) => toUser(r, assignments.get(r.id))),
            pagination: { page: pageNum, limit: limitNum, total, totalPages: Math.ceil(total / limitNum) },
        });
    } catch (error) {
        sendError(res, error, 'Gagal mengambil data pengguna');
    }
});

router.get('/:id', requirePermission('users.manage'), async (req, res) => {
    try {
        const { user, assignments } = await loadManagedUser(pool, req.access, parseInt(req.params.id, 10));
        res.json({ user: toUser(user, assignments) });
    } catch (error) {
        sendError(res, error, 'Gagal mengambil data pengguna');
    }
});

// Body: { name, username, password, assignments: [{ location_id, role_id }] }
// At least one assignment is required so the new user is visible to whoever manages that location.
router.post('/', requirePermission('users.manage'), async (req, res) => {
    let prepared;
    try {
        const { name, username, password, assignments } = req.body;
        if (!name || !username || !password) {
            throw new AppError('Nama, username, dan password wajib diisi');
        }
        if (!Array.isArray(assignments) || assignments.length === 0) {
            throw new AppError('Pengguna harus memiliki minimal satu penugasan lokasi dan role');
        }
        prepared = {
            name: checkName(name),
            username: checkUsername(username),
            passwordHash: await hashPassword(password),
            assignments,
        };
    } catch (error) {
        return sendError(res, error, 'Gagal membuat pengguna');
    }

    const result = await withTransaction(res, 'Gagal membuat pengguna', async (conn) => {
        const normalized = await normalizeAssignments(conn, req.access, prepared.assignments);
        await assertUsernameFree(conn, prepared.username);
        const [insert] = await conn.execute(
            'INSERT INTO users (name, username, password) VALUES (?, ?, ?)',
            [prepared.name, prepared.username, prepared.passwordHash]
        );
        await replaceAssignments(conn, req.access, insert.insertId, normalized);
        const { user, assignments } = await loadManagedUser(conn, req.access, insert.insertId);
        await logAudit(conn, req, {
            action: 'create', entity: 'user', entityId: insert.insertId,
            after: { name: user.name, username: user.username, assignments: normalized },
        });
        return toUser(user, assignments);
    });
    if (result) res.status(201).json({ message: 'Pengguna berhasil dibuat', userId: result.id, user: result });
});

// Body: any of { name, username, password, is_active, assignments }.
// assignments replaces the user's assignments at the locations the acting user manages.
router.put('/:id', requirePermission('users.manage'), async (req, res) => {
    const userId = parseInt(req.params.id, 10);
    if (!userId) return res.status(400).json({ error: 'ID pengguna tidak valid' });

    const { name, username, password, is_active, assignments } = req.body;
    const updates = [];
    const params = [];
    try {
        if (name !== undefined) {
            updates.push('name = ?');
            params.push(checkName(name));
        }
        if (username !== undefined) {
            updates.push('username = ?');
            params.push(checkUsername(username));
        }
        if (password !== undefined && password !== null && password !== '') {
            updates.push('password = ?');
            params.push(await hashPassword(password));
        }
        if (is_active !== undefined) {
            if (userId === req.user.id) throw new AppError('Anda tidak dapat menonaktifkan akun Anda sendiri');
            updates.push('is_active = ?');
            params.push(is_active ? 1 : 0);
        }
        if (assignments !== undefined && userId === req.user.id) {
            throw new AppError('Anda tidak dapat mengubah penugasan Anda sendiri');
        }
        if (updates.length === 0 && assignments === undefined) {
            throw new AppError('Tidak ada field yang valid untuk diperbarui');
        }
    } catch (error) {
        return sendError(res, error, 'Gagal memperbarui pengguna');
    }

    const result = await withTransaction(res, 'Gagal memperbarui pengguna', async (conn) => {
        const before = await loadManagedUser(conn, req.access, userId, { lock: true });

        if (username !== undefined) await assertUsernameFree(conn, params[updates.indexOf('username = ?')], userId);
        if (updates.length > 0) {
            await conn.execute(`UPDATE users SET ${updates.join(', ')} WHERE id = ?`, [...params, userId]);
        }
        if (assignments !== undefined) {
            const normalized = await normalizeAssignments(conn, req.access, assignments);
            await replaceAssignments(conn, req.access, userId, normalized);
        }

        const after = await loadManagedUser(conn, req.access, userId);
        const summary = ({ user, assignments: a }) => ({
            name: user.name, username: user.username, is_active: !!user.is_active,
            assignments: a.map(({ locationId, roleId }) => ({ locationId, roleId })),
        });
        await logAudit(conn, req, {
            action: 'update', entity: 'user', entityId: userId,
            before: summary(before),
            after: { ...summary(after), ...(updates.some((u) => u.startsWith('password')) ? { password_changed: true } : {}) },
        });
        return toUser(after.user, after.assignments);
    });
    if (result) res.json({ message: 'Pengguna berhasil diperbarui', user: result });
});

// Users with history (sales, stock movements, journals, ...) can't be removed without breaking
// those records, so they are deactivated instead; users without history are deleted.
router.delete('/:id', requirePermission('users.manage'), async (req, res) => {
    const userId = parseInt(req.params.id, 10);
    if (!userId) return res.status(400).json({ error: 'ID pengguna tidak valid' });
    if (userId === req.user.id) return res.status(400).json({ error: 'Anda tidak dapat menghapus akun Anda sendiri' });

    const result = await withTransaction(res, 'Gagal menghapus pengguna', async (conn) => {
        const { user, assignments } = await loadManagedUser(conn, req.access, userId, { lock: true });
        // A non-owner who manages only some of the user's locations removes just those assignments.
        const scope = req.access.locationsFor('users.manage');
        if (scope !== null && assignments.some((a) => a.locationId === null || !scope.includes(a.locationId))) {
            await replaceAssignments(conn, req.access, userId, []);
            await logAudit(conn, req, { action: 'unassign', entity: 'user', entityId: userId, before: { assignments } });
            return { message: 'Penugasan pengguna di lokasi Anda telah dihapus (pengguna masih aktif di lokasi lain)', deleted: false };
        }

        // Deactivated users keep their assignments, so whoever manages them can still find and reactivate them.
        await conn.query('SAVEPOINT before_delete');
        try {
            await conn.execute('DELETE FROM user_locations WHERE user_id = ?', [userId]);
            await conn.execute('DELETE FROM users WHERE id = ?', [userId]);
        } catch (error) {
            if (error.code !== 'ER_ROW_IS_REFERENCED_2' && error.code !== 'ER_ROW_IS_REFERENCED') throw error;
            await conn.query('ROLLBACK TO SAVEPOINT before_delete');
            await conn.execute('UPDATE users SET is_active = 0 WHERE id = ?', [userId]);
            await logAudit(conn, req, { action: 'deactivate', entity: 'user', entityId: userId, before: { name: user.name, username: user.username, assignments } });
            return { message: 'Pengguna memiliki riwayat transaksi sehingga dinonaktifkan, bukan dihapus', deleted: false, deactivated: true };
        }
        await logAudit(conn, req, { action: 'delete', entity: 'user', entityId: userId, before: { name: user.name, username: user.username, assignments } });
        return { message: 'Pengguna berhasil dihapus', deleted: true };
    });
    if (result) res.json(result);
});

module.exports = router;
