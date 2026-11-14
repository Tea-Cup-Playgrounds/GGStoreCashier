/**
 * Completes the accounting module:
 *
 * - Document dates: goods receipts get the date the goods arrived (received_date) and stock counts
 *   the date their differences are booked (adjustment_date). Stock movements and journals of a
 *   document carry that date, and its number is taken from it.
 * - Opening balances: journal source 'opening_balance' (against 3-3000 Ekuitas Saldo Awal) and stock
 *   movement reason 'opening' for opening stock, which no longer lands in Selisih Persediaan.
 * - Expenses (Biaya): an `expenses` table; each expense posts Dr expense account / Cr cash or bank.
 *   Permission expenses.manage for branch managers and accountants.
 * - Pulsa deposit: product_variants.cost_price (cost of a digital item, e.g. pulsa 10rb costs
 *   10.150), mapping key pulsa_deposit -> 1-1600, journal source 'pulsa_deposit' for top-ups. A pulsa
 *   sale books its cost: Dr HPP, Cr Deposit Pulsa.
 */

const JOURNAL_SOURCES_OLD = ['sale', 'sale_void', 'sale_return', 'goods_receipt', 'supplier_payment',
    'stock_adjustment', 'opname', 'transfer', 'cash_session', 'expense', 'manual'];
const JOURNAL_SOURCES_NEW = [...JOURNAL_SOURCES_OLD, 'expense_void', 'opening_balance', 'pulsa_deposit'];

const MOVEMENT_REASONS_OLD = ['purchase', 'purchase_return', 'sale', 'sale_return', 'transfer_out', 'transfer_in',
    'adjustment', 'opname', 'trade_in', 'service_part', 'write_off'];
const MOVEMENT_REASONS_NEW = [...MOVEMENT_REASONS_OLD, 'opening'];

const enumSql = (values) => `enum(${values.map((v) => `'${v}'`).join(',')})`;

exports.up = async function (knex) {
    await knex.raw(`ALTER TABLE \`journal_entries\` MODIFY \`source_type\` ${enumSql(JOURNAL_SOURCES_NEW)} NOT NULL`);
    await knex.raw(`ALTER TABLE \`stock_movements\` MODIFY \`reason\` ${enumSql(MOVEMENT_REASONS_NEW)} NOT NULL`);
    await knex.raw("ALTER TABLE `product_units` MODIFY `source_type` enum('purchase','trade_in','adjustment','return','opening') NOT NULL");

    // ── document dates ───────────────────────────────────────────────────────
    await knex.raw('ALTER TABLE `goods_receipts` ADD COLUMN `received_date` date NULL AFTER `due_date`');
    await knex.raw('UPDATE `goods_receipts` SET `received_date` = DATE(COALESCE(`posted_at`, `created_at`)), `updated_at` = `updated_at`');
    await knex.raw('ALTER TABLE `stock_opnames` ADD COLUMN `adjustment_date` date NULL AFTER `approved_at`');
    await knex.raw("UPDATE `stock_opnames` SET `adjustment_date` = DATE(`approved_at`), `updated_at` = `updated_at` WHERE `status` = 'approved'");

    // ── inter-location account ───────────────────────────────────────────────
    // A transfer moves stock value from one location to another. Booking it through this account
    // (receiver owes sender) keeps every location's own books balanced; company-wide it nets to 0.
    await knex.raw(
        `INSERT INTO \`accounts\` (\`code\`, \`name\`, \`type\`, \`parent_id\`, \`is_postable\`, \`is_system\`)
         SELECT '1-1700', 'Rekening Antar Lokasi', 'asset', \`id\`, 1, 1 FROM \`accounts\` WHERE \`code\` = '1-0000'`
    );
    await knex.raw(
        "INSERT INTO `account_mappings` (`key`, `location_id`, `account_id`) SELECT 'inter_location', NULL, `id` FROM `accounts` WHERE `code` = '1-1700'"
    );

    // ── pulsa deposit ────────────────────────────────────────────────────────
    await knex.raw('ALTER TABLE `product_variants` ADD COLUMN `cost_price` decimal(15,2) NULL AFTER `min_price`');
    await knex.raw(
        "INSERT INTO `account_mappings` (`key`, `location_id`, `account_id`) SELECT 'pulsa_deposit', NULL, `id` FROM `accounts` WHERE `code` = '1-1600'"
    );

    // ── expenses ─────────────────────────────────────────────────────────────
    await knex.raw(`
        CREATE TABLE \`expenses\` (
            \`id\` char(36) NOT NULL,
            \`number\` varchar(30) NOT NULL,
            \`location_id\` int NULL,
            \`expense_date\` date NOT NULL,
            \`account_id\` int NOT NULL,
            \`amount\` decimal(15,2) NOT NULL,
            \`paid_from\` enum('cash','bank') NOT NULL,
            \`payee\` varchar(150) NULL,
            \`note\` text NULL,
            \`status\` enum('posted','void') NOT NULL DEFAULT 'posted',
            \`void_reason\` text NULL,
            \`voided_by\` int NULL,
            \`voided_at\` datetime(3) NULL,
            \`created_by\` int NULL,
            \`created_at\` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
            \`updated_at\` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
            PRIMARY KEY (\`id\`),
            UNIQUE KEY \`uq_expenses_number\` (\`number\`),
            KEY \`idx_expenses_location_date\` (\`location_id\`, \`expense_date\`),
            KEY \`idx_expenses_account\` (\`account_id\`),
            CONSTRAINT \`fk_expenses_location\` FOREIGN KEY (\`location_id\`) REFERENCES \`locations\` (\`id\`) ON DELETE RESTRICT,
            CONSTRAINT \`fk_expenses_account\` FOREIGN KEY (\`account_id\`) REFERENCES \`accounts\` (\`id\`) ON DELETE RESTRICT,
            CONSTRAINT \`fk_expenses_created_by\` FOREIGN KEY (\`created_by\`) REFERENCES \`users\` (\`id\`) ON DELETE SET NULL,
            CONSTRAINT \`fk_expenses_voided_by\` FOREIGN KEY (\`voided_by\`) REFERENCES \`users\` (\`id\`) ON DELETE SET NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
    `);
    await knex.raw(
        "INSERT IGNORE INTO `role_permissions` (`role_id`, `permission`) SELECT `id`, 'expenses.manage' FROM `roles` WHERE `code` IN ('branch_manager', 'accountant')"
    );
};

exports.down = async function (knex) {
    await knex.raw("DELETE FROM `role_permissions` WHERE `permission` = 'expenses.manage'");
    // Reversals first: they reference the entries they reverse.
    const newSources = "('expense', 'expense_void', 'opening_balance', 'pulsa_deposit')";
    await knex.raw(`DELETE FROM \`journal_entries\` WHERE \`source_type\` IN ${newSources} AND \`reverses_entry_id\` IS NOT NULL`);
    await knex.raw(`DELETE FROM \`journal_entries\` WHERE \`source_type\` IN ${newSources}`);
    await knex.raw('DROP TABLE IF EXISTS `expenses`');
    await knex.raw("DELETE FROM `account_mappings` WHERE `key` IN ('pulsa_deposit', 'inter_location')");
    await knex.raw("DELETE FROM `journal_entries` WHERE `source_type` = 'transfer' AND `memo` LIKE 'Transfer % diterima'");
    await knex.raw("DELETE FROM `accounts` WHERE `code` = '1-1700'");
    await knex.raw('ALTER TABLE `product_variants` DROP COLUMN `cost_price`');
    await knex.raw('ALTER TABLE `stock_opnames` DROP COLUMN `adjustment_date`');
    await knex.raw('ALTER TABLE `goods_receipts` DROP COLUMN `received_date`');
    await knex.raw("UPDATE `product_units` SET `source_type` = 'adjustment' WHERE `source_type` = 'opening'");
    await knex.raw("ALTER TABLE `product_units` MODIFY `source_type` enum('purchase','trade_in','adjustment','return') NOT NULL");
    await knex.raw("UPDATE `stock_movements` SET `reason` = 'adjustment' WHERE `reason` = 'opening'");
    await knex.raw(`ALTER TABLE \`stock_movements\` MODIFY \`reason\` ${enumSql(MOVEMENT_REASONS_OLD)} NOT NULL`);
    await knex.raw(`ALTER TABLE \`journal_entries\` MODIFY \`source_type\` ${enumSql(JOURNAL_SOURCES_OLD)} NOT NULL`);
};
