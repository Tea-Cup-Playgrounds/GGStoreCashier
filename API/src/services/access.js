const { PERMISSIONS, OWNER_ROLE_CODE } = require('../auth/permissions');
const { AppError } = require('../utils/transaction');

const ALL_PERMISSIONS = Object.keys(PERMISSIONS);

// What a user may do, built from their user_locations rows. An assignment with
// locationId === null applies at every location.
class Access {
    constructor(assignments) {
        this.assignments = assignments;
        this.isOwner = assignments.some((a) => a.roleCode === OWNER_ROLE_CODE);
    }

    // With a locationId: may the user do this at that location?
    // Without one: may the user do this anywhere?
    can(permission, locationId) {
        if (this.isOwner) return true;
        return this.assignments.some((a) =>
            a.permissions.has(permission) &&
            (locationId === undefined || a.locationId === null || a.locationId === Number(locationId))
        );
    }

    // Location ids where the user holds the permission, or null for "every location".
    locationsFor(permission) {
        if (this.isOwner) return null;
        const matching = this.assignments.filter((a) => a.permissions.has(permission));
        if (matching.some((a) => a.locationId === null)) return null;
        return [...new Set(matching.map((a) => a.locationId))];
    }

    // Union of locationsFor() over several permissions: null if any of them covers every location.
    locationsForAny(...permissions) {
        const ids = new Set();
        for (const permission of permissions) {
            const scope = this.locationsFor(permission);
            if (scope === null) return null;
            scope.forEach((id) => ids.add(id));
        }
        return [...ids];
    }

    toJSON() {
        return {
            isOwner: this.isOwner,
            assignments: this.assignments.map((a) => ({
                locationId: a.locationId,
                locationName: a.locationName,
                locationType: a.locationType,
                roleId: a.roleId,
                roleCode: a.roleCode,
                roleName: a.roleName,
                permissions: a.roleCode === OWNER_ROLE_CODE ? ALL_PERMISSIONS : [...a.permissions].sort(),
            })),
        };
    }
}

const loadAccess = async (db, userId) => {
    // Assignments at inactive or deleted locations grant nothing.
    const [rows] = await db.execute(
        `SELECT ul.location_id, l.name AS location_name, l.type AS location_type,
                r.id AS role_id, r.code AS role_code, r.name AS role_name, rp.permission
         FROM user_locations ul
         JOIN roles r ON r.id = ul.role_id
         LEFT JOIN locations l ON l.id = ul.location_id
         LEFT JOIN role_permissions rp ON rp.role_id = r.id
         WHERE ul.user_id = ?
           AND (ul.location_id IS NULL OR (l.is_active = 1 AND l.deleted_at IS NULL))
         ORDER BY ul.location_id IS NOT NULL, ul.location_id`,
        [userId]
    );

    const byLocation = new Map();
    for (const row of rows) {
        const key = row.location_id === null ? 'all' : row.location_id;
        if (!byLocation.has(key)) {
            byLocation.set(key, {
                locationId: row.location_id,
                locationName: row.location_name,
                locationType: row.location_type,
                roleId: row.role_id,
                roleCode: row.role_code,
                roleName: row.role_name,
                permissions: new Set(),
            });
        }
        if (row.permission) byLocation.get(key).permissions.add(row.permission);
    }

    return new Access([...byLocation.values()]);
};

// ── Assignment management (used by /api/users and /api/access) ───────────────

// A user's assignments with location and role names, including inactive locations.
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

// Throws unless the acting user may manage a user with these assignments: owners manage everyone;
// others only non-owners who have at least one assignment at a location they manage.
const assertCanManageUser = (access, assignments) => {
    if (access.isOwner) return;
    if (assignments.some((a) => a.roleCode === OWNER_ROLE_CODE)) {
        throw new AppError('Anda tidak dapat mengelola pengguna owner', 403);
    }
    const scope = access.locationsFor('users.manage');
    if (scope !== null && !assignments.some((a) => inScope(scope, a.locationId))) {
        throw new AppError('Pengguna ini tidak berada di lokasi Anda', 403);
    }
};

// Checks requested assignments ([{ location_id: number|null, role_id }]) against what the acting
// user may grant and returns them as [{ locationId, roleId }]. location_id null = every location.
const normalizeAssignments = async (db, access, requested) => {
    if (!Array.isArray(requested)) throw new AppError('assignments harus berupa array');

    const [roleRows] = await db.execute(
        `SELECT r.id, r.code, GROUP_CONCAT(rp.permission) AS permissions
         FROM roles r LEFT JOIN role_permissions rp ON rp.role_id = r.id
         GROUP BY r.id`
    );
    const roles = new Map(roleRows.map((r) => [r.id, { code: r.code, permissions: r.permissions ? r.permissions.split(',') : [] }]));

    const [locationRows] = await db.execute('SELECT id FROM locations WHERE is_active = 1 AND deleted_at IS NULL');
    const activeLocations = new Set(locationRows.map((l) => l.id));
    const scope = access.locationsFor('users.manage');

    const seenLocations = new Set();
    const normalized = [];
    for (const item of requested) {
        const locationId = item.location_id === null || item.location_id === undefined ? null : Number(item.location_id);
        const roleId = Number(item.role_id);
        const role = roles.get(roleId);

        if (!role) throw new AppError(`Role ${item.role_id} tidak ditemukan`);
        if (locationId !== null && !activeLocations.has(locationId)) {
            throw new AppError(`Lokasi ${item.location_id} tidak ditemukan atau tidak aktif`);
        }
        const key = locationId === null ? 'all' : locationId;
        if (seenLocations.has(key)) throw new AppError('Satu lokasi hanya boleh memiliki satu role per pengguna');
        seenLocations.add(key);

        if (role.code === OWNER_ROLE_CODE && locationId !== null) {
            throw new AppError('Role owner berlaku untuk semua lokasi (location_id harus null)');
        }
        if (!access.isOwner) {
            if (role.code === OWNER_ROLE_CODE || locationId === null) {
                throw new AppError('Hanya owner yang dapat memberikan akses ke semua lokasi', 403);
            }
            if (!inScope(scope, locationId)) {
                throw new AppError(`Anda tidak mengelola pengguna di lokasi ${locationId}`, 403);
            }
            const notHeld = role.permissions.filter((p) => !access.can(p, locationId));
            if (notHeld.length > 0) {
                throw new AppError(`Role ini memiliki izin yang tidak Anda miliki di lokasi tersebut: ${notHeld.join(', ')}`, 403);
            }
        }
        normalized.push({ locationId, roleId });
    }
    return normalized;
};

// Replaces the assignments the acting user controls with `normalized`. A non-owner's change
// leaves assignments outside their locations (and global ones) untouched.
const replaceAssignments = async (db, access, userId, normalized) => {
    if (access.isOwner) {
        await db.execute('DELETE FROM user_locations WHERE user_id = ?', [userId]);
    } else {
        const scope = access.locationsFor('users.manage');
        if (scope === null) {
            await db.execute('DELETE FROM user_locations WHERE user_id = ? AND location_id IS NOT NULL', [userId]);
        } else {
            for (const locationId of scope) {
                await db.execute('DELETE FROM user_locations WHERE user_id = ? AND location_id = ?', [userId, locationId]);
            }
        }
    }
    for (const a of normalized) {
        await db.execute('INSERT INTO user_locations (user_id, location_id, role_id) VALUES (?, ?, ?)', [userId, a.locationId, a.roleId]);
    }
};

module.exports = {
    Access,
    ALL_PERMISSIONS,
    loadAccess,
    loadAssignments,
    inScope,
    assertCanManageUser,
    normalizeAssignments,
    replaceAssignments,
};
