/**
 * Step 6 of the foundation plan (docs/foundation-design.md §6): removes the transition shims.
 *
 * - users.role / users.branch_id are dropped; access comes only from user_locations.
 * - The `branches` view is dropped; everything reads `locations`.
 * - locations.code becomes required (legacy inserts through the view were the only writers without one).
 * - Branch managers keep what the legacy `admin` role could do: the new vouchers.manage permission
 *   (replaces the admin/superadmin check on /api/vouchers) and locations.manage, which at one location
 *   only edits that location's name/address/phone/settings (creating locations, codes and status stay
 *   with owners).
 *
 * Rollback re-creates the legacy columns from user_locations with the same rules the step 2-5 code
 * used to keep them in sync (owner -> superadmin, branch manager at a branch -> admin, else karyawan).
 */

const usersBranchForeignKeys = async (knex) => {
    const [rows] = await knex.raw(
        `SELECT CONSTRAINT_NAME AS name FROM information_schema.KEY_COLUMN_USAGE
         WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND COLUMN_NAME = 'branch_id'
           AND REFERENCED_TABLE_NAME IS NOT NULL`
    );
    return rows.map((r) => r.name);
};

const usersBranchIndexes = async (knex) => {
    const [rows] = await knex.raw(
        `SELECT DISTINCT INDEX_NAME AS name FROM information_schema.STATISTICS
         WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND COLUMN_NAME = 'branch_id'`
    );
    return rows.map((r) => r.name);
};

exports.up = async function (knex) {
    // ── locations ────────────────────────────────────────────────────────────
    await knex.raw("UPDATE `locations` SET `code` = CONCAT('BR', LPAD(`id`, 2, '0')), `updated_at` = `updated_at` WHERE `code` IS NULL");
    await knex.raw('DROP VIEW IF EXISTS `branches`');
    await knex.raw('ALTER TABLE `locations` MODIFY `code` varchar(10) NOT NULL');

    // ── users ────────────────────────────────────────────────────────────────
    for (const fk of await usersBranchForeignKeys(knex)) {
        await knex.raw('ALTER TABLE `users` DROP FOREIGN KEY ??', [fk]);
    }
    for (const index of await usersBranchIndexes(knex)) {
        await knex.raw('ALTER TABLE `users` DROP INDEX ??', [index]);
    }
    await knex.raw('ALTER TABLE `users` DROP COLUMN `role`, DROP COLUMN `branch_id`');

    // ── permissions ──────────────────────────────────────────────────────────
    await knex.raw(
        "INSERT IGNORE INTO `role_permissions` (`role_id`, `permission`) SELECT `id`, 'vouchers.manage' FROM `roles` WHERE `code` = 'branch_manager'"
    );
    await knex.raw(
        "INSERT IGNORE INTO `role_permissions` (`role_id`, `permission`) SELECT `id`, 'locations.manage' FROM `roles` WHERE `code` = 'branch_manager'"
    );
};

exports.down = async function (knex) {
    await knex.raw("DELETE FROM `role_permissions` WHERE `permission` = 'vouchers.manage'");
    await knex.raw(
        "DELETE rp FROM `role_permissions` rp JOIN `roles` r ON r.id = rp.role_id WHERE r.code = 'branch_manager' AND rp.permission = 'locations.manage'"
    );

    await knex.raw(`
        ALTER TABLE \`users\`
            ADD COLUMN \`role\` enum('karyawan','admin','superadmin') NOT NULL DEFAULT 'karyawan' AFTER \`pin_hash\`,
            ADD COLUMN \`branch_id\` int DEFAULT NULL AFTER \`role\`,
            ADD KEY \`fk_users_branch\` (\`branch_id\`),
            ADD CONSTRAINT \`fk_users_branch\` FOREIGN KEY (\`branch_id\`) REFERENCES \`locations\` (\`id\`) ON DELETE SET NULL ON UPDATE CASCADE
    `);

    // Owners -> superadmin (no branch).
    await knex.raw(`
        UPDATE users u SET u.role = 'superadmin', u.updated_at = u.updated_at
        WHERE EXISTS (SELECT 1 FROM user_locations ul JOIN roles r ON r.id = ul.role_id WHERE ul.user_id = u.id AND r.code = 'owner')
    `);
    // Branch managers at a branch -> admin of the lowest such branch.
    await knex.raw(`
        UPDATE users u
        JOIN (SELECT ul.user_id, MIN(ul.location_id) AS location_id
              FROM user_locations ul
              JOIN roles r ON r.id = ul.role_id
              JOIN locations l ON l.id = ul.location_id
              WHERE r.code = 'branch_manager' AND l.type = 'branch'
              GROUP BY ul.user_id) m ON m.user_id = u.id
        SET u.role = 'admin', u.branch_id = m.location_id, u.updated_at = u.updated_at
        WHERE u.role <> 'superadmin'
    `);
    // Everyone else stays karyawan at their lowest branch, else their lowest location of any type.
    await knex.raw(`
        UPDATE users u
        JOIN (SELECT ul.user_id,
                     COALESCE(MIN(CASE WHEN l.type = 'branch' THEN ul.location_id END), MIN(ul.location_id)) AS location_id
              FROM user_locations ul
              JOIN locations l ON l.id = ul.location_id
              GROUP BY ul.user_id) a ON a.user_id = u.id
        SET u.branch_id = a.location_id, u.updated_at = u.updated_at
        WHERE u.role = 'karyawan'
    `);

    await knex.raw('ALTER TABLE `locations` MODIFY `code` varchar(10) NULL');
    await knex.raw(`
        CREATE VIEW \`branches\` AS
        SELECT \`id\`, \`name\`, \`address\`, \`phone\`, \`created_at\`, \`updated_at\`
        FROM \`locations\`
        WHERE \`type\` = 'branch'
    `);
};
