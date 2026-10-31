/**
 * Step 2 of the foundation plan (docs/foundation-design.md §6): locations, roles,
 * per-location role assignments, devices and audit logs.
 *
 * `branches` is renamed to `locations` (existing foreign keys follow the rename) and a
 * `branches` view is created over the branch rows, so routes that still query `branches`
 * keep working until the cleanup step.
 *
 * Legacy users.role / users.branch_id are kept and mapped into user_locations:
 *   superadmin -> owner (all locations), admin -> branch_manager@branch, karyawan -> cashier@branch
 */

// Frozen copy of the default permissions at the time of this migration. Later permission
// changes for system roles belong in new migrations, not here.
const SYSTEM_ROLES = [
    {
        code: 'owner',
        name: 'Owner',
        description: 'Akses penuh ke semua lokasi dan pengaturan.',
        permissions: [], // owner is granted every permission in code
    },
    {
        code: 'branch_manager',
        name: 'Branch Manager',
        description: 'Mengelola cabang: stok, staf, persetujuan, laporan cabang.',
        permissions: [
            'sales.create', 'sales.void', 'sales.discount_override', 'sales.price_override',
            'cash_session.open', 'cash_session.close', 'cash_session.view_all',
            'catalog.view', 'prices.manage_location',
            'stock.view', 'stock.adjust', 'stock.opname', 'units.register', 'units.register_at_pos',
            'transfers.create', 'transfers.send', 'transfers.receive',
            'customers.manage',
            'reports.view_location',
            'users.manage',
            'data.export',
        ],
    },
    {
        code: 'cashier',
        name: 'Cashier',
        description: 'Penjualan dan shift kasir.',
        permissions: [
            'sales.create',
            'cash_session.open', 'cash_session.close',
            'catalog.view', 'stock.view',
            'customers.manage',
        ],
    },
    {
        code: 'warehouse',
        name: 'Warehouse',
        description: 'Penerimaan barang, IMEI, transfer, dan stok opname.',
        permissions: [
            'catalog.view', 'catalog.manage',
            'stock.view', 'stock.adjust', 'stock.opname', 'units.register',
            'transfers.create', 'transfers.send', 'transfers.receive',
            'purchases.manage', 'suppliers.manage',
            'data.import', 'data.export',
        ],
    },
    {
        code: 'accountant',
        name: 'Accountant',
        description: 'Jurnal, biaya, tutup buku, dan laporan keuangan.',
        permissions: [
            'catalog.view', 'stock.view',
            'purchases.manage', 'suppliers.manage',
            'accounting.view', 'accounting.post_manual', 'accounting.close_period',
            'reports.view_location', 'reports.view_all',
            'data.import', 'data.export',
        ],
    },
];

exports.up = async function (knex) {
    // ── locations (renamed from branches) ────────────────────────────────────
    await knex.raw('RENAME TABLE `branches` TO `locations`');
    await knex.raw(`
        ALTER TABLE \`locations\`
            ADD COLUMN \`code\` varchar(10) NULL AFTER \`id\`,
            ADD COLUMN \`type\` enum('branch','warehouse') NOT NULL DEFAULT 'branch' AFTER \`phone\`,
            ADD COLUMN \`is_active\` tinyint(1) NOT NULL DEFAULT 1 AFTER \`type\`,
            ADD COLUMN \`settings\` json NULL AFTER \`is_active\`,
            ADD COLUMN \`deleted_at\` datetime(3) NULL AFTER \`updated_at\`,
            MODIFY \`updated_at\` datetime(3) DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
            ADD UNIQUE KEY \`uq_locations_code\` (\`code\`)
    `);
    // code stays nullable until the cleanup step: legacy inserts through the branches view don't set it.
    await knex.raw("UPDATE `locations` SET `code` = CONCAT('BR', LPAD(`id`, 2, '0')), `updated_at` = `updated_at` WHERE `code` IS NULL");
    await knex.raw("INSERT INTO `locations` (`code`, `name`, `type`) VALUES ('WH', 'Gudang Utama', 'warehouse')");

    await knex.raw(`
        CREATE VIEW \`branches\` AS
        SELECT \`id\`, \`name\`, \`address\`, \`phone\`, \`created_at\`, \`updated_at\`
        FROM \`locations\`
        WHERE \`type\` = 'branch'
    `);

    // ── users ─────────────────────────────────────────────────────────────────
    await knex.raw(`
        ALTER TABLE \`users\`
            ADD COLUMN \`pin_hash\` varchar(255) NULL AFTER \`password\`,
            ADD COLUMN \`is_active\` tinyint(1) NOT NULL DEFAULT 1 AFTER \`branch_id\`
    `);

    // ── roles & permissions ──────────────────────────────────────────────────
    await knex.raw(`
        CREATE TABLE \`roles\` (
            \`id\` int NOT NULL AUTO_INCREMENT,
            \`code\` varchar(30) NULL,
            \`name\` varchar(50) NOT NULL,
            \`description\` varchar(255) NULL,
            \`is_system\` tinyint(1) NOT NULL DEFAULT 0,
            \`created_at\` datetime DEFAULT CURRENT_TIMESTAMP,
            \`updated_at\` datetime(3) DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
            PRIMARY KEY (\`id\`),
            UNIQUE KEY \`uq_roles_code\` (\`code\`),
            UNIQUE KEY \`uq_roles_name\` (\`name\`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
    `);

    await knex.raw(`
        CREATE TABLE \`role_permissions\` (
            \`role_id\` int NOT NULL,
            \`permission\` varchar(64) NOT NULL,
            PRIMARY KEY (\`role_id\`, \`permission\`),
            CONSTRAINT \`fk_role_permissions_role\` FOREIGN KEY (\`role_id\`) REFERENCES \`roles\` (\`id\`) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
    `);

    // location_id NULL = the role applies at every location. MySQL treats NULLs as distinct in
    // unique keys, so "one global assignment per user" is enforced in services/access.js.
    await knex.raw(`
        CREATE TABLE \`user_locations\` (
            \`id\` int NOT NULL AUTO_INCREMENT,
            \`user_id\` int NOT NULL,
            \`location_id\` int NULL,
            \`role_id\` int NOT NULL,
            \`created_at\` datetime DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (\`id\`),
            UNIQUE KEY \`uq_user_locations\` (\`user_id\`, \`location_id\`),
            KEY \`idx_user_locations_location\` (\`location_id\`),
            KEY \`idx_user_locations_role\` (\`role_id\`),
            CONSTRAINT \`fk_user_locations_user\` FOREIGN KEY (\`user_id\`) REFERENCES \`users\` (\`id\`) ON DELETE CASCADE,
            CONSTRAINT \`fk_user_locations_location\` FOREIGN KEY (\`location_id\`) REFERENCES \`locations\` (\`id\`) ON DELETE CASCADE,
            CONSTRAINT \`fk_user_locations_role\` FOREIGN KEY (\`role_id\`) REFERENCES \`roles\` (\`id\`) ON DELETE RESTRICT
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
    `);

    // ── devices & audit log ──────────────────────────────────────────────────
    await knex.raw(`
        CREATE TABLE \`devices\` (
            \`id\` char(36) NOT NULL,
            \`location_id\` int NOT NULL,
            \`name\` varchar(100) NOT NULL,
            \`platform\` enum('android','ios','windows') NOT NULL,
            \`receipt_prefix\` char(3) NOT NULL,
            \`registered_by\` int NULL,
            \`last_sync_at\` datetime(3) NULL,
            \`revoked_at\` datetime(3) NULL,
            \`created_at\` datetime DEFAULT CURRENT_TIMESTAMP,
            \`updated_at\` datetime(3) DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
            PRIMARY KEY (\`id\`),
            UNIQUE KEY \`uq_devices_prefix\` (\`location_id\`, \`receipt_prefix\`),
            CONSTRAINT \`fk_devices_location\` FOREIGN KEY (\`location_id\`) REFERENCES \`locations\` (\`id\`) ON DELETE RESTRICT,
            CONSTRAINT \`fk_devices_user\` FOREIGN KEY (\`registered_by\`) REFERENCES \`users\` (\`id\`) ON DELETE SET NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
    `);

    await knex.raw(`
        CREATE TABLE \`audit_logs\` (
            \`id\` char(36) NOT NULL,
            \`user_id\` int NULL,
            \`device_id\` char(36) NULL,
            \`location_id\` int NULL,
            \`action\` varchar(50) NOT NULL,
            \`entity\` varchar(50) NOT NULL,
            \`entity_id\` varchar(36) NULL,
            \`before\` json NULL,
            \`after\` json NULL,
            \`ip\` varchar(45) NULL,
            \`created_at\` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
            PRIMARY KEY (\`id\`),
            KEY \`idx_audit_entity\` (\`entity\`, \`entity_id\`),
            KEY \`idx_audit_user\` (\`user_id\`, \`created_at\`),
            KEY \`idx_audit_location\` (\`location_id\`, \`created_at\`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
    `);

    // ── seed system roles ────────────────────────────────────────────────────
    const roleIds = {};
    for (const role of SYSTEM_ROLES) {
        const [result] = await knex.raw(
            'INSERT INTO `roles` (`code`, `name`, `description`, `is_system`) VALUES (?, ?, ?, 1)',
            [role.code, role.name, role.description]
        );
        roleIds[role.code] = result.insertId;
        for (const permission of role.permissions) {
            await knex.raw('INSERT INTO `role_permissions` (`role_id`, `permission`) VALUES (?, ?)', [result.insertId, permission]);
        }
    }

    // ── map legacy roles ─────────────────────────────────────────────────────
    await knex.raw(
        "INSERT INTO `user_locations` (`user_id`, `location_id`, `role_id`) SELECT `id`, NULL, ? FROM `users` WHERE `role` = 'superadmin'",
        [roleIds.owner]
    );
    await knex.raw(
        "INSERT INTO `user_locations` (`user_id`, `location_id`, `role_id`) SELECT `id`, `branch_id`, ? FROM `users` WHERE `role` = 'admin' AND `branch_id` IS NOT NULL",
        [roleIds.branch_manager]
    );
    await knex.raw(
        "INSERT INTO `user_locations` (`user_id`, `location_id`, `role_id`) SELECT `id`, `branch_id`, ? FROM `users` WHERE `role` = 'karyawan' AND `branch_id` IS NOT NULL",
        [roleIds.cashier]
    );
};

exports.down = async function (knex) {
    await knex.raw('DROP TABLE IF EXISTS `audit_logs`');
    await knex.raw('DROP TABLE IF EXISTS `devices`');
    await knex.raw('DROP TABLE IF EXISTS `user_locations`');
    await knex.raw('DROP TABLE IF EXISTS `role_permissions`');
    await knex.raw('DROP TABLE IF EXISTS `roles`');

    await knex.raw('ALTER TABLE `users` DROP COLUMN `pin_hash`, DROP COLUMN `is_active`');

    await knex.raw('DROP VIEW IF EXISTS `branches`');
    // Non-branch locations (the warehouse) have no place in the old schema. Clear any legacy
    // references first so the delete isn't blocked by foreign keys.
    await knex.raw("UPDATE `users` SET `branch_id` = NULL WHERE `branch_id` IN (SELECT `id` FROM (SELECT `id` FROM `locations` WHERE `type` <> 'branch') AS l)");
    await knex.raw("UPDATE `products` SET `branch_id` = NULL WHERE `branch_id` IN (SELECT `id` FROM (SELECT `id` FROM `locations` WHERE `type` <> 'branch') AS l)");
    await knex.raw("DELETE FROM `locations` WHERE `type` <> 'branch'");
    await knex.raw(`
        ALTER TABLE \`locations\`
            DROP INDEX \`uq_locations_code\`,
            DROP COLUMN \`code\`,
            DROP COLUMN \`type\`,
            DROP COLUMN \`is_active\`,
            DROP COLUMN \`settings\`,
            DROP COLUMN \`deleted_at\`,
            MODIFY \`updated_at\` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    `);
    await knex.raw('RENAME TABLE `locations` TO `branches`');
};
