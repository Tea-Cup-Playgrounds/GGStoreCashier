/**
 * Baseline: the schema as it was in gg_kasirinventory_db.sql before migrations existed.
 *
 * Every statement is CREATE TABLE IF NOT EXISTS, so on an existing database this migration
 * only records itself as applied and leaves the tables untouched. On an empty database it
 * builds the full schema. Tables are listed in foreign-key order.
 */

const TABLES = [
    `CREATE TABLE IF NOT EXISTS \`branches\` (
        \`id\` int NOT NULL AUTO_INCREMENT,
        \`name\` varchar(100) NOT NULL,
        \`address\` text,
        \`phone\` varchar(20) DEFAULT NULL,
        \`created_at\` datetime DEFAULT CURRENT_TIMESTAMP,
        \`updated_at\` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (\`id\`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci`,

    `CREATE TABLE IF NOT EXISTS \`categories\` (
        \`id\` int NOT NULL AUTO_INCREMENT,
        \`name\` varchar(100) NOT NULL,
        \`description\` text,
        \`category_image\` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL,
        \`created_at\` datetime DEFAULT CURRENT_TIMESTAMP,
        \`updated_at\` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (\`id\`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci`,

    `CREATE TABLE IF NOT EXISTS \`users\` (
        \`id\` int NOT NULL AUTO_INCREMENT,
        \`name\` varchar(100) NOT NULL,
        \`username\` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
        \`password\` varchar(255) NOT NULL,
        \`role\` enum('karyawan','admin','superadmin') NOT NULL DEFAULT 'karyawan',
        \`branch_id\` int DEFAULT NULL,
        \`last_active_at\` datetime DEFAULT NULL,
        \`created_at\` datetime DEFAULT CURRENT_TIMESTAMP,
        \`updated_at\` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (\`id\`),
        KEY \`fk_users_branch\` (\`branch_id\`),
        CONSTRAINT \`fk_users_branch\` FOREIGN KEY (\`branch_id\`) REFERENCES \`branches\` (\`id\`) ON DELETE SET NULL ON UPDATE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci`,

    `CREATE TABLE IF NOT EXISTS \`products\` (
        \`id\` int NOT NULL AUTO_INCREMENT,
        \`name\` varchar(150) NOT NULL,
        \`barcode\` varchar(100) DEFAULT NULL,
        \`category_id\` int DEFAULT NULL,
        \`sell_price\` decimal(12,2) NOT NULL,
        \`stock\` int DEFAULT '0',
        \`product_image\` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL,
        \`branch_id\` int DEFAULT NULL,
        \`created_at\` datetime DEFAULT CURRENT_TIMESTAMP,
        \`updated_at\` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (\`id\`),
        UNIQUE KEY \`barcode\` (\`barcode\`),
        KEY \`idx_products_category\` (\`category_id\`),
        KEY \`idx_products_branch\` (\`branch_id\`),
        CONSTRAINT \`fk_products_branch\` FOREIGN KEY (\`branch_id\`) REFERENCES \`branches\` (\`id\`) ON DELETE SET NULL ON UPDATE CASCADE,
        CONSTRAINT \`fk_products_category\` FOREIGN KEY (\`category_id\`) REFERENCES \`categories\` (\`id\`) ON DELETE SET NULL ON UPDATE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci`,

    `CREATE TABLE IF NOT EXISTS \`transactions\` (
        \`id\` int NOT NULL AUTO_INCREMENT,
        \`uuid\` varchar(255) DEFAULT NULL,
        \`user_id\` int NOT NULL,
        \`branch_id\` int NOT NULL,
        \`total_amount\` decimal(12,2) NOT NULL,
        \`discount\` decimal(12,2) DEFAULT '0.00',
        \`final_amount\` decimal(12,2) NOT NULL,
        \`payment_status\` enum('paid','unpaid','partial') NOT NULL DEFAULT 'unpaid',
        \`created_at\` datetime DEFAULT CURRENT_TIMESTAMP,
        \`updated_at\` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (\`id\`),
        UNIQUE KEY \`uuid\` (\`uuid\`),
        KEY \`idx_transactions_user\` (\`user_id\`),
        KEY \`idx_transactions_branch\` (\`branch_id\`),
        CONSTRAINT \`fk_transactions_branch\` FOREIGN KEY (\`branch_id\`) REFERENCES \`branches\` (\`id\`) ON DELETE RESTRICT ON UPDATE CASCADE,
        CONSTRAINT \`fk_transactions_user\` FOREIGN KEY (\`user_id\`) REFERENCES \`users\` (\`id\`) ON DELETE RESTRICT ON UPDATE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci`,

    `CREATE TABLE IF NOT EXISTS \`transaction_items\` (
        \`id\` int NOT NULL AUTO_INCREMENT,
        \`transaction_id\` int NOT NULL,
        \`product_id\` int NOT NULL,
        \`qty\` int NOT NULL,
        \`price\` decimal(12,2) NOT NULL,
        \`subtotal\` decimal(12,2) NOT NULL,
        PRIMARY KEY (\`id\`),
        KEY \`idx_ti_transaction\` (\`transaction_id\`),
        KEY \`idx_ti_product\` (\`product_id\`),
        CONSTRAINT \`fk_ti_product\` FOREIGN KEY (\`product_id\`) REFERENCES \`products\` (\`id\`) ON DELETE RESTRICT ON UPDATE CASCADE,
        CONSTRAINT \`fk_ti_transaction\` FOREIGN KEY (\`transaction_id\`) REFERENCES \`transactions\` (\`id\`) ON DELETE CASCADE ON UPDATE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci`,

    `CREATE TABLE IF NOT EXISTS \`payments\` (
        \`id\` int NOT NULL AUTO_INCREMENT,
        \`transaction_id\` int NOT NULL,
        \`method\` enum('cash','transfer','e-wallet','card') NOT NULL,
        \`amount\` decimal(12,2) NOT NULL,
        \`created_at\` datetime DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (\`id\`),
        KEY \`idx_payment_transaction\` (\`transaction_id\`),
        CONSTRAINT \`fk_payments_transaction\` FOREIGN KEY (\`transaction_id\`) REFERENCES \`transactions\` (\`id\`) ON DELETE CASCADE ON UPDATE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci`,

    `CREATE TABLE IF NOT EXISTS \`returns\` (
        \`id\` int NOT NULL AUTO_INCREMENT,
        \`transaction_id\` int NOT NULL,
        \`product_id\` int NOT NULL,
        \`qty\` int NOT NULL,
        \`reason\` text,
        \`created_at\` datetime DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (\`id\`),
        KEY \`idx_returns_transaction\` (\`transaction_id\`),
        KEY \`idx_returns_product\` (\`product_id\`),
        CONSTRAINT \`fk_returns_product\` FOREIGN KEY (\`product_id\`) REFERENCES \`products\` (\`id\`) ON DELETE RESTRICT ON UPDATE CASCADE,
        CONSTRAINT \`fk_returns_transaction\` FOREIGN KEY (\`transaction_id\`) REFERENCES \`transactions\` (\`id\`) ON DELETE CASCADE ON UPDATE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci`,

    `CREATE TABLE IF NOT EXISTS \`stock_movements\` (
        \`id\` int NOT NULL AUTO_INCREMENT,
        \`product_id\` int NOT NULL,
        \`branch_id\` int NOT NULL,
        \`type\` enum('in','out') NOT NULL,
        \`qty\` int NOT NULL,
        \`note\` text,
        \`created_at\` datetime DEFAULT CURRENT_TIMESTAMP,
        \`updated_at\` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (\`id\`),
        KEY \`fk_stock_branch\` (\`branch_id\`),
        KEY \`idx_stock_product_branch\` (\`product_id\`,\`branch_id\`),
        CONSTRAINT \`fk_stock_branch\` FOREIGN KEY (\`branch_id\`) REFERENCES \`branches\` (\`id\`) ON DELETE CASCADE ON UPDATE CASCADE,
        CONSTRAINT \`fk_stock_product\` FOREIGN KEY (\`product_id\`) REFERENCES \`products\` (\`id\`) ON DELETE CASCADE ON UPDATE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci`,

    `CREATE TABLE IF NOT EXISTS \`vouchers\` (
        \`id\` int NOT NULL AUTO_INCREMENT,
        \`code\` varchar(50) NOT NULL,
        \`description\` text,
        \`target_type\` enum('categories','product') CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL,
        \`target_id\` bigint DEFAULT NULL,
        \`discount_type\` enum('percent','fixed') NOT NULL,
        \`discount_value\` decimal(12,2) NOT NULL,
        \`valid_from\` date DEFAULT NULL,
        \`valid_to\` date DEFAULT NULL,
        \`is_active\` tinyint(1) DEFAULT '1',
        \`created_at\` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
        \`updated_at\` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (\`id\`),
        UNIQUE KEY \`code\` (\`code\`),
        KEY \`idx_target_id\` (\`target_id\`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci`,

    // The original dump has no AUTO_INCREMENT on absensi.id; kept as-is for the baseline.
    `CREATE TABLE IF NOT EXISTS \`absensi\` (
        \`id\` int NOT NULL,
        \`absensi_image\` varchar(255) NOT NULL,
        \`kehadiran\` enum('Hadir','Izin','Sakit','Tidak Masuk','Tanpa Keterangan') NOT NULL,
        \`users_id\` int NOT NULL,
        \`branches_id\` int NOT NULL,
        \`created_at\` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
        \`updated_at\` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (\`id\`),
        KEY \`idx_users_id\` (\`users_id\`) USING BTREE,
        KEY \`idx_branches_id\` (\`branches_id\`) USING BTREE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci`,
];

exports.up = async function (knex) {
    for (const sql of TABLES) {
        await knex.raw(sql);
    }

    // Older databases were created before users.last_active_at was added.
    const hasLastActive = await knex.schema.hasColumn('users', 'last_active_at');
    if (!hasLastActive) {
        await knex.raw('ALTER TABLE `users` ADD COLUMN `last_active_at` DATETIME NULL DEFAULT NULL AFTER `branch_id`');
    }
};

exports.down = async function () {
    // Rolling back the baseline would drop every table and all business data.
    throw new Error('The baseline migration cannot be rolled back. Drop the database manually if you really want to start over.');
};
