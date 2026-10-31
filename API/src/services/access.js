const { PERMISSIONS, OWNER_ROLE_CODE } = require('../auth/permissions');

const ALL_PERMISSIONS = Object.keys(PERMISSIONS);

// Legacy users.role <-> system role codes. Kept until the cleanup step removes users.role.
const LEGACY_ROLE_TO_CODE = {
    superadmin: OWNER_ROLE_CODE,
    admin: 'branch_manager',
    karyawan: 'cashier',
};

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

const getRoleIdByCode = async (db, code) => {
    const [rows] = await db.execute('SELECT id FROM roles WHERE code = ?', [code]);
    if (rows.length === 0) throw new Error(`System role "${code}" is missing; run npm run migrate`);
    return rows[0].id;
};

// Called after the legacy /api/users endpoints change a user's role or branch: replaces the
// user's assignments with the single assignment that role/branch implies.
const syncAssignmentsFromLegacy = async (db, userId, legacyRole, branchId) => {
    const roleId = await getRoleIdByCode(db, LEGACY_ROLE_TO_CODE[legacyRole] || 'cashier');

    await db.execute('DELETE FROM user_locations WHERE user_id = ?', [userId]);
    if (legacyRole === 'superadmin') {
        await db.execute('INSERT INTO user_locations (user_id, location_id, role_id) VALUES (?, NULL, ?)', [userId, roleId]);
    } else if (branchId) {
        await db.execute('INSERT INTO user_locations (user_id, location_id, role_id) VALUES (?, ?, ?)', [userId, branchId, roleId]);
    }
};

// Called after assignments change through /api/access: recomputes users.role / users.branch_id
// so routes that still use requireRole() and filterByBranch see a consistent picture.
const syncLegacyFromAssignments = async (db, userId) => {
    const [rows] = await db.execute(
        `SELECT ul.location_id, l.type AS location_type, r.code AS role_code
         FROM user_locations ul
         JOIN roles r ON r.id = ul.role_id
         LEFT JOIN locations l ON l.id = ul.location_id
         WHERE ul.user_id = ?
         ORDER BY ul.location_id`,
        [userId]
    );

    let role = 'karyawan';
    let branchId = null;

    if (rows.some((r) => r.role_code === OWNER_ROLE_CODE)) {
        role = 'superadmin';
    } else {
        const located = rows.filter((r) => r.location_id !== null);
        const manager = located.find((r) => r.role_code === 'branch_manager' && r.location_type === 'branch');
        const firstBranch = located.find((r) => r.location_type === 'branch');
        if (manager) {
            role = 'admin';
            branchId = manager.location_id;
        } else {
            branchId = (firstBranch || located[0] || {}).location_id ?? null;
        }
    }

    await db.execute('UPDATE users SET role = ?, branch_id = ? WHERE id = ?', [role, branchId, userId]);
};

module.exports = {
    Access,
    ALL_PERMISSIONS,
    loadAccess,
    syncAssignmentsFromLegacy,
    syncLegacyFromAssignments,
};
