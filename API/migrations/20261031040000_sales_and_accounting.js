/**
 * Step 5 of the foundation plan (docs/foundation-design.md §4.5–4.7, §6): the accounting core
 * (chart of accounts, mappings, periods, journals) and the new sales model (payment methods,
 * customers, cash sessions, sales, payments, returns).
 *
 * Decisions (2026-10-31): selling prices include PPN 11% (extracted for tax); shifts are optional;
 * a customer is required when an IMEI unit is sold.
 *
 * Legacy transactions / transaction_items / payments are copied into sales / sale_lines /
 * sale_payments and then dropped (the unused legacy `returns` table too). Their journals are
 * created afterwards by `npm run accounting:backfill`, together with step 4's receipts and payments.
 */

const TABLE_OPTS = 'ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci';

// [code, name, type, parentCode, postable]
const ACCOUNTS = [
    ['1-0000', 'Aset', 'asset', null, 0],
    ['1-1100', 'Kas', 'asset', '1-0000', 1],
    ['1-1200', 'Bank', 'asset', '1-0000', 1],
    ['1-1300', 'Piutang QRIS / E-Wallet', 'asset', '1-0000', 1],
    ['1-1310', 'Piutang EDC (Kartu)', 'asset', '1-0000', 1],
    ['1-1400', 'Persediaan Barang', 'asset', '1-0000', 1],
    ['1-1500', 'PPN Masukan', 'asset', '1-0000', 1],
    ['1-1600', 'Deposit Pulsa', 'asset', '1-0000', 1],
    ['2-0000', 'Kewajiban', 'liability', null, 0],
    ['2-1100', 'Hutang Usaha', 'liability', '2-0000', 1],
    ['2-1200', 'PPN Keluaran', 'liability', '2-0000', 1],
    ['3-0000', 'Ekuitas', 'equity', null, 0],
    ['3-1000', 'Modal Pemilik', 'equity', '3-0000', 1],
    ['3-2000', 'Laba Ditahan', 'equity', '3-0000', 1],
    ['3-3000', 'Ekuitas Saldo Awal', 'equity', '3-0000', 1],
    ['4-0000', 'Pendapatan', 'income', null, 0],
    ['4-1000', 'Penjualan Barang', 'income', '4-0000', 1],
    ['4-2000', 'Pendapatan Jasa', 'income', '4-0000', 1],
    ['4-3000', 'Pendapatan Pulsa & Digital', 'income', '4-0000', 1],
    ['4-9000', 'Pendapatan Lain-lain', 'income', '4-0000', 1],
    ['5-0000', 'Harga Pokok', 'expense', null, 0],
    ['5-1000', 'Harga Pokok Penjualan', 'expense', '5-0000', 1],
    ['5-2000', 'Selisih Persediaan', 'expense', '5-0000', 1],
    ['6-0000', 'Beban Operasional', 'expense', null, 0],
    ['6-1000', 'Beban Sewa', 'expense', '6-0000', 1],
    ['6-1100', 'Pajak Bumi & Bangunan', 'expense', '6-0000', 1],
    ['6-2000', 'Gaji Karyawan', 'expense', '6-0000', 1],
    ['6-3000', 'Listrik, Air & Internet', 'expense', '6-0000', 1],
    ['6-9000', 'Beban Lain-lain', 'expense', '6-0000', 1],
    ['6-9100', 'Selisih Kas', 'expense', '6-0000', 1],
];

// Posting rules look accounts up by these keys (location-specific mapping first, then global).
const MAPPINGS = {
    cash: '1-1100',
    bank: '1-1200',
    ewallet_clearing: '1-1300',
    card_clearing: '1-1310',
    inventory: '1-1400',
    ppn_input: '1-1500',
    accounts_payable: '2-1100',
    ppn_output: '2-1200',
    opening_balance: '3-3000',
    sales_goods: '4-1000',
    sales_service: '4-2000',
    sales_digital: '4-3000',
    cogs: '5-1000',
    inventory_adjustment: '5-2000',
    cash_over_short: '6-9100',
};

// [name, type, accountCode, requiresReference]
const PAYMENT_METHODS = [
    ['Tunai', 'cash', '1-1100', 0],
    ['QRIS', 'qris', '1-1300', 0],
    ['E-Wallet', 'ewallet', '1-1300', 1],
    ['Kartu Debit/Kredit', 'card', '1-1310', 1],
    ['Transfer Bank', 'transfer', '1-1200', 1],
];

exports.up = async function (knex) {
    // ── settings ─────────────────────────────────────────────────────────────
    await knex.raw(`
        CREATE TABLE \`settings\` (
            \`key\` varchar(64) NOT NULL,
            \`value\` json NOT NULL,
            \`updated_at\` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
            PRIMARY KEY (\`key\`)
        ) ${TABLE_OPTS}
    `);
    const [[ppn]] = await knex.raw("SELECT id FROM tax_rates WHERE name = 'PPN 11%'");
    await knex.raw("INSERT INTO settings (`key`, `value`) VALUES ('tax.prices_include_tax', 'true'), ('tax.default_rate_id', ?)",
        [JSON.stringify(ppn ? ppn.id : null)]);

    // ── chart of accounts & journals ─────────────────────────────────────────
    await knex.raw(`
        CREATE TABLE \`accounts\` (
            \`id\` int NOT NULL AUTO_INCREMENT,
            \`code\` varchar(20) NOT NULL,
            \`name\` varchar(100) NOT NULL,
            \`type\` enum('asset','liability','equity','income','expense') NOT NULL,
            \`parent_id\` int NULL,
            \`is_postable\` tinyint(1) NOT NULL DEFAULT 1,
            \`is_system\` tinyint(1) NOT NULL DEFAULT 0,
            \`is_active\` tinyint(1) NOT NULL DEFAULT 1,
            \`created_at\` datetime DEFAULT CURRENT_TIMESTAMP,
            \`updated_at\` datetime(3) DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
            PRIMARY KEY (\`id\`),
            UNIQUE KEY \`uq_accounts_code\` (\`code\`),
            KEY \`idx_accounts_parent\` (\`parent_id\`),
            CONSTRAINT \`fk_accounts_parent\` FOREIGN KEY (\`parent_id\`) REFERENCES \`accounts\` (\`id\`) ON DELETE RESTRICT
        ) ${TABLE_OPTS}
    `);
    const accountIds = {};
    for (const [code, name, type, parentCode, postable] of ACCOUNTS) {
        const [result] = await knex.raw(
            'INSERT INTO accounts (code, name, type, parent_id, is_postable, is_system) VALUES (?, ?, ?, ?, ?, 1)',
            [code, name, type, parentCode ? accountIds[parentCode] : null, postable]
        );
        accountIds[code] = result.insertId;
    }

    await knex.raw(`
        CREATE TABLE \`account_mappings\` (
            \`id\` int NOT NULL AUTO_INCREMENT,
            \`key\` varchar(50) NOT NULL,
            \`location_id\` int NULL,
            \`account_id\` int NOT NULL,
            PRIMARY KEY (\`id\`),
            UNIQUE KEY \`uq_mapping\` (\`key\`, \`location_id\`),
            CONSTRAINT \`fk_mapping_location\` FOREIGN KEY (\`location_id\`) REFERENCES \`locations\` (\`id\`) ON DELETE CASCADE,
            CONSTRAINT \`fk_mapping_account\` FOREIGN KEY (\`account_id\`) REFERENCES \`accounts\` (\`id\`) ON DELETE RESTRICT
        ) ${TABLE_OPTS}
    `);
    for (const [key, code] of Object.entries(MAPPINGS)) {
        await knex.raw('INSERT INTO account_mappings (`key`, location_id, account_id) VALUES (?, NULL, ?)', [key, accountIds[code]]);
    }

    await knex.raw(`
        CREATE TABLE \`accounting_periods\` (
            \`year\` smallint NOT NULL,
            \`month\` tinyint NOT NULL,
            \`status\` enum('open','closed') NOT NULL DEFAULT 'open',
            \`closed_by\` int NULL,
            \`closed_at\` datetime(3) NULL,
            PRIMARY KEY (\`year\`, \`month\`),
            CONSTRAINT \`fk_period_user\` FOREIGN KEY (\`closed_by\`) REFERENCES \`users\` (\`id\`) ON DELETE SET NULL
        ) ${TABLE_OPTS}
    `);

    // A posted entry is never edited: it is voided by a reversing entry (reverses_entry_id).
    await knex.raw(`
        CREATE TABLE \`journal_entries\` (
            \`id\` char(36) NOT NULL,
            \`number\` varchar(30) NOT NULL,
            \`entry_date\` date NOT NULL,
            \`location_id\` int NULL,
            \`source_type\` enum('sale','sale_void','sale_return','goods_receipt','supplier_payment',
                                 'stock_adjustment','opname','transfer','cash_session','expense','manual') NOT NULL,
            \`source_id\` varchar(36) NULL,
            \`memo\` varchar(255) NULL,
            \`status\` enum('posted','void') NOT NULL DEFAULT 'posted',
            \`reverses_entry_id\` char(36) NULL,
            \`created_by\` int NULL,
            \`created_at\` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
            PRIMARY KEY (\`id\`),
            UNIQUE KEY \`uq_je_number\` (\`number\`),
            KEY \`idx_je_source\` (\`source_type\`, \`source_id\`),
            KEY \`idx_je_date\` (\`entry_date\`, \`location_id\`),
            CONSTRAINT \`fk_je_location\` FOREIGN KEY (\`location_id\`) REFERENCES \`locations\` (\`id\`) ON DELETE RESTRICT,
            CONSTRAINT \`fk_je_reverses\` FOREIGN KEY (\`reverses_entry_id\`) REFERENCES \`journal_entries\` (\`id\`) ON DELETE RESTRICT,
            CONSTRAINT \`fk_je_user\` FOREIGN KEY (\`created_by\`) REFERENCES \`users\` (\`id\`) ON DELETE SET NULL
        ) ${TABLE_OPTS}
    `);
    await knex.raw(`
        CREATE TABLE \`journal_lines\` (
            \`id\` char(36) NOT NULL,
            \`entry_id\` char(36) NOT NULL,
            \`account_id\` int NOT NULL,
            \`location_id\` int NULL,
            \`debit\` decimal(15,2) NOT NULL DEFAULT 0,
            \`credit\` decimal(15,2) NOT NULL DEFAULT 0,
            \`memo\` varchar(255) NULL,
            PRIMARY KEY (\`id\`),
            KEY \`idx_jl_entry\` (\`entry_id\`),
            KEY \`idx_jl_account\` (\`account_id\`, \`location_id\`),
            CONSTRAINT \`fk_jl_entry\` FOREIGN KEY (\`entry_id\`) REFERENCES \`journal_entries\` (\`id\`) ON DELETE CASCADE,
            CONSTRAINT \`fk_jl_account\` FOREIGN KEY (\`account_id\`) REFERENCES \`accounts\` (\`id\`) ON DELETE RESTRICT,
            CONSTRAINT \`fk_jl_location\` FOREIGN KEY (\`location_id\`) REFERENCES \`locations\` (\`id\`) ON DELETE RESTRICT
        ) ${TABLE_OPTS}
    `);

    // ── payment methods, customers, cash sessions ────────────────────────────
    await knex.raw(`
        CREATE TABLE \`payment_methods\` (
            \`id\` int NOT NULL AUTO_INCREMENT,
            \`name\` varchar(50) NOT NULL,
            \`type\` enum('cash','qris','ewallet','card','transfer') NOT NULL,
            \`account_id\` int NOT NULL,
            \`requires_reference\` tinyint(1) NOT NULL DEFAULT 0,
            \`location_id\` int NULL,
            \`sort_order\` int NOT NULL DEFAULT 0,
            \`is_active\` tinyint(1) NOT NULL DEFAULT 1,
            \`created_at\` datetime DEFAULT CURRENT_TIMESTAMP,
            \`updated_at\` datetime(3) DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
            PRIMARY KEY (\`id\`),
            CONSTRAINT \`fk_pm_account\` FOREIGN KEY (\`account_id\`) REFERENCES \`accounts\` (\`id\`) ON DELETE RESTRICT,
            CONSTRAINT \`fk_pm_location\` FOREIGN KEY (\`location_id\`) REFERENCES \`locations\` (\`id\`) ON DELETE CASCADE
        ) ${TABLE_OPTS}
    `);
    const methodIds = {};
    for (const [index, [name, type, code, ref]] of PAYMENT_METHODS.entries()) {
        const [result] = await knex.raw(
            'INSERT INTO payment_methods (name, type, account_id, requires_reference, sort_order) VALUES (?, ?, ?, ?, ?)',
            [name, type, accountIds[code], ref, index]
        );
        methodIds[type] = methodIds[type] || result.insertId;
    }

    // phone is the natural key at the counter; code is optional (imports).
    await knex.raw(`
        CREATE TABLE \`customers\` (
            \`id\` char(36) NOT NULL,
            \`code\` varchar(30) NULL,
            \`name\` varchar(150) NOT NULL,
            \`phone\` varchar(30) NULL,
            \`email\` varchar(100) NULL,
            \`address\` text NULL,
            \`id_number\` varchar(30) NULL,
            \`notes\` text NULL,
            \`created_at\` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
            \`updated_at\` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
            \`deleted_at\` datetime(3) NULL,
            PRIMARY KEY (\`id\`),
            UNIQUE KEY \`uq_customers_code\` (\`code\`),
            UNIQUE KEY \`uq_customers_phone\` (\`phone\`),
            KEY \`idx_customers_name\` (\`name\`),
            KEY \`idx_customers_updated\` (\`updated_at\`)
        ) ${TABLE_OPTS}
    `);

    await knex.raw(`
        CREATE TABLE \`cash_sessions\` (
            \`id\` char(36) NOT NULL,
            \`location_id\` int NOT NULL,
            \`device_id\` char(36) NULL,
            \`status\` enum('open','closed') NOT NULL DEFAULT 'open',
            \`opened_by\` int NOT NULL,
            \`opened_at\` datetime(3) NOT NULL,
            \`opening_cash\` decimal(15,2) NOT NULL DEFAULT 0,
            \`closed_by\` int NULL,
            \`closed_at\` datetime(3) NULL,
            \`expected_cash\` decimal(15,2) NULL,
            \`counted_cash\` decimal(15,2) NULL,
            \`difference\` decimal(15,2) NULL,
            \`note\` text NULL,
            \`created_at\` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
            \`updated_at\` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
            PRIMARY KEY (\`id\`),
            KEY \`idx_cs_location\` (\`location_id\`, \`status\`),
            CONSTRAINT \`fk_cs_location\` FOREIGN KEY (\`location_id\`) REFERENCES \`locations\` (\`id\`) ON DELETE RESTRICT,
            CONSTRAINT \`fk_cs_opened_by\` FOREIGN KEY (\`opened_by\`) REFERENCES \`users\` (\`id\`) ON DELETE RESTRICT,
            CONSTRAINT \`fk_cs_closed_by\` FOREIGN KEY (\`closed_by\`) REFERENCES \`users\` (\`id\`) ON DELETE SET NULL
        ) ${TABLE_OPTS}
    `);

    // ── sales ────────────────────────────────────────────────────────────────
    // Amounts: unit_price is the tag price (PPN included); line discount includes its share of
    // any sale-level discount; line_total = qty * unit_price - discount; tax_amount is the PPN
    // inside line_total. grand_total = sum(line_total); refunded_total grows with returns.
    await knex.raw(`
        CREATE TABLE \`sales\` (
            \`id\` char(36) NOT NULL,
            \`number\` varchar(40) NOT NULL,
            \`location_id\` int NOT NULL,
            \`device_id\` char(36) NULL,
            \`cash_session_id\` char(36) NULL,
            \`cashier_id\` int NOT NULL,
            \`customer_id\` char(36) NULL,
            \`voucher_id\` int NULL,
            \`subtotal\` decimal(15,2) NOT NULL,
            \`discount_total\` decimal(15,2) NOT NULL DEFAULT 0,
            \`tax_total\` decimal(15,2) NOT NULL DEFAULT 0,
            \`grand_total\` decimal(15,2) NOT NULL,
            \`paid_total\` decimal(15,2) NOT NULL,
            \`change_total\` decimal(15,2) NOT NULL DEFAULT 0,
            \`refunded_total\` decimal(15,2) NOT NULL DEFAULT 0,
            \`status\` enum('completed','voided','partially_returned','returned') NOT NULL DEFAULT 'completed',
            \`note\` text NULL,
            \`void_reason\` text NULL,
            \`voided_by\` int NULL,
            \`voided_at\` datetime(3) NULL,
            \`occurred_at\` datetime(3) NOT NULL,
            \`received_at\` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
            \`sync_flags\` json NULL,
            \`legacy_id\` int NULL,
            \`updated_at\` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
            PRIMARY KEY (\`id\`),
            UNIQUE KEY \`uq_sales_number\` (\`number\`),
            KEY \`idx_sales_location\` (\`location_id\`, \`occurred_at\`),
            KEY \`idx_sales_session\` (\`cash_session_id\`),
            KEY \`idx_sales_customer\` (\`customer_id\`),
            KEY \`idx_sales_cashier\` (\`cashier_id\`, \`occurred_at\`),
            CONSTRAINT \`fk_sales_location\` FOREIGN KEY (\`location_id\`) REFERENCES \`locations\` (\`id\`) ON DELETE RESTRICT,
            CONSTRAINT \`fk_sales_session\` FOREIGN KEY (\`cash_session_id\`) REFERENCES \`cash_sessions\` (\`id\`) ON DELETE RESTRICT,
            CONSTRAINT \`fk_sales_cashier\` FOREIGN KEY (\`cashier_id\`) REFERENCES \`users\` (\`id\`) ON DELETE RESTRICT,
            CONSTRAINT \`fk_sales_customer\` FOREIGN KEY (\`customer_id\`) REFERENCES \`customers\` (\`id\`) ON DELETE RESTRICT,
            CONSTRAINT \`fk_sales_voucher\` FOREIGN KEY (\`voucher_id\`) REFERENCES \`vouchers\` (\`id\`) ON DELETE SET NULL
        ) ${TABLE_OPTS}
    `);

    // Serialized units are one line each (qty 1, unit_id), so returns and warranty are per unit.
    await knex.raw(`
        CREATE TABLE \`sale_lines\` (
            \`id\` char(36) NOT NULL,
            \`sale_id\` char(36) NOT NULL,
            \`line_type\` enum('goods','service','digital','fee') NOT NULL DEFAULT 'goods',
            \`variant_id\` int NULL,
            \`unit_id\` char(36) NULL,
            \`description\` varchar(200) NOT NULL,
            \`qty\` int NOT NULL,
            \`unit_price\` decimal(15,2) NOT NULL,
            \`discount\` decimal(15,2) NOT NULL DEFAULT 0,
            \`tax_rate\` decimal(5,2) NOT NULL DEFAULT 0,
            \`tax_amount\` decimal(15,2) NOT NULL DEFAULT 0,
            \`line_total\` decimal(15,2) NOT NULL,
            \`unit_cost\` decimal(15,2) NOT NULL DEFAULT 0,
            \`returned_qty\` int NOT NULL DEFAULT 0,
            \`warranty_until\` date NULL,
            \`sort_order\` int NOT NULL DEFAULT 0,
            PRIMARY KEY (\`id\`),
            KEY \`idx_sl_sale\` (\`sale_id\`),
            KEY \`idx_sl_variant\` (\`variant_id\`),
            KEY \`idx_sl_unit\` (\`unit_id\`),
            CONSTRAINT \`fk_sline_sale\` FOREIGN KEY (\`sale_id\`) REFERENCES \`sales\` (\`id\`) ON DELETE CASCADE,
            CONSTRAINT \`fk_sline_variant\` FOREIGN KEY (\`variant_id\`) REFERENCES \`product_variants\` (\`id\`) ON DELETE RESTRICT,
            CONSTRAINT \`fk_sline_unit\` FOREIGN KEY (\`unit_id\`) REFERENCES \`product_units\` (\`id\`) ON DELETE RESTRICT
        ) ${TABLE_OPTS}
    `);

    await knex.raw(`
        CREATE TABLE \`sale_payments\` (
            \`id\` char(36) NOT NULL,
            \`sale_id\` char(36) NOT NULL,
            \`payment_method_id\` int NOT NULL,
            \`amount\` decimal(15,2) NOT NULL,
            \`reference\` varchar(100) NULL,
            PRIMARY KEY (\`id\`),
            KEY \`idx_spay_sale\` (\`sale_id\`),
            CONSTRAINT \`fk_spay_sale\` FOREIGN KEY (\`sale_id\`) REFERENCES \`sales\` (\`id\`) ON DELETE CASCADE,
            CONSTRAINT \`fk_spay_method\` FOREIGN KEY (\`payment_method_id\`) REFERENCES \`payment_methods\` (\`id\`) ON DELETE RESTRICT
        ) ${TABLE_OPTS}
    `);

    await knex.raw(`
        CREATE TABLE \`sale_returns\` (
            \`id\` char(36) NOT NULL,
            \`number\` varchar(30) NOT NULL,
            \`sale_id\` char(36) NOT NULL,
            \`location_id\` int NOT NULL,
            \`cash_session_id\` char(36) NULL,
            \`refund_method_id\` int NOT NULL,
            \`refund_total\` decimal(15,2) NOT NULL,
            \`tax_total\` decimal(15,2) NOT NULL DEFAULT 0,
            \`reason\` text NOT NULL,
            \`created_by\` int NULL,
            \`created_at\` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
            PRIMARY KEY (\`id\`),
            UNIQUE KEY \`uq_sr_number\` (\`number\`),
            KEY \`idx_sr_sale\` (\`sale_id\`),
            CONSTRAINT \`fk_sr_sale\` FOREIGN KEY (\`sale_id\`) REFERENCES \`sales\` (\`id\`) ON DELETE RESTRICT,
            CONSTRAINT \`fk_sr_location\` FOREIGN KEY (\`location_id\`) REFERENCES \`locations\` (\`id\`) ON DELETE RESTRICT,
            CONSTRAINT \`fk_sr_session\` FOREIGN KEY (\`cash_session_id\`) REFERENCES \`cash_sessions\` (\`id\`) ON DELETE RESTRICT,
            CONSTRAINT \`fk_sr_method\` FOREIGN KEY (\`refund_method_id\`) REFERENCES \`payment_methods\` (\`id\`) ON DELETE RESTRICT,
            CONSTRAINT \`fk_sr_user\` FOREIGN KEY (\`created_by\`) REFERENCES \`users\` (\`id\`) ON DELETE SET NULL
        ) ${TABLE_OPTS}
    `);

    // restock = 0: the item came back defective (serialized units become 'defective').
    await knex.raw(`
        CREATE TABLE \`sale_return_lines\` (
            \`id\` char(36) NOT NULL,
            \`return_id\` char(36) NOT NULL,
            \`sale_line_id\` char(36) NOT NULL,
            \`qty\` int NOT NULL,
            \`amount\` decimal(15,2) NOT NULL,
            \`tax_amount\` decimal(15,2) NOT NULL DEFAULT 0,
            \`unit_cost\` decimal(15,2) NOT NULL DEFAULT 0,
            \`restock\` tinyint(1) NOT NULL DEFAULT 1,
            PRIMARY KEY (\`id\`),
            KEY \`idx_srl_return\` (\`return_id\`),
            CONSTRAINT \`fk_srl_return\` FOREIGN KEY (\`return_id\`) REFERENCES \`sale_returns\` (\`id\`) ON DELETE CASCADE,
            CONSTRAINT \`fk_srl_line\` FOREIGN KEY (\`sale_line_id\`) REFERENCES \`sale_lines\` (\`id\`) ON DELETE RESTRICT
        ) ${TABLE_OPTS}
    `);

    // ── migrate legacy transactions ──────────────────────────────────────────
    const [[{ legacyReturns }]] = await knex.raw('SELECT COUNT(*) AS legacyReturns FROM `returns`');
    if (Number(legacyReturns) > 0) {
        throw new Error('Tabel returns lama berisi data; migrasi otomatisnya belum didukung. Hubungi developer.');
    }

    await knex.raw(`
        INSERT INTO sales (id, number, location_id, cashier_id, subtotal, discount_total, tax_total, grand_total,
                           paid_total, change_total, status, occurred_at, received_at, legacy_id)
        SELECT UUID(), CONCAT('LEGACY-', t.id), t.branch_id, t.user_id, t.total_amount, COALESCE(t.discount, 0), 0, t.final_amount,
               GREATEST(COALESCE((SELECT SUM(p.amount) FROM payments p WHERE p.transaction_id = t.id), t.final_amount), t.final_amount),
               GREATEST(COALESCE((SELECT SUM(p.amount) FROM payments p WHERE p.transaction_id = t.id), t.final_amount) - t.final_amount, 0),
               'completed', COALESCE(t.created_at, NOW()), COALESCE(t.created_at, NOW()), t.id
        FROM transactions t
    `);
    // Legacy discounts were sale-level; spread them over the lines by value.
    await knex.raw(`
        INSERT INTO sale_lines (id, sale_id, line_type, variant_id, description, qty, unit_price, discount, line_total, sort_order)
        SELECT UUID(), s.id, 'goods', ti.product_id,
               LEFT(CONCAT(p.name, IF(v.name IS NULL OR v.name = '', '', CONCAT(' ', v.name))), 200),
               ti.qty, ti.price,
               ROUND(IF(s.subtotal > 0, s.discount_total * ti.subtotal / s.subtotal, 0), 2),
               ti.subtotal - ROUND(IF(s.subtotal > 0, s.discount_total * ti.subtotal / s.subtotal, 0), 2),
               ti.id
        FROM transaction_items ti
        JOIN sales s ON s.legacy_id = ti.transaction_id
        JOIN product_variants v ON v.id = ti.product_id
        JOIN products p ON p.id = v.product_id
    `);
    for (const [legacy, type] of [['cash', 'cash'], ['transfer', 'transfer'], ['e-wallet', 'ewallet'], ['card', 'card']]) {
        await knex.raw(`
            INSERT INTO sale_payments (id, sale_id, payment_method_id, amount)
            SELECT UUID(), s.id, ?, p.amount FROM payments p JOIN sales s ON s.legacy_id = p.transaction_id WHERE p.method = ?
        `, [methodIds[type], legacy]);
    }
    // Legacy sales without a payment row were recorded as paid in cash.
    await knex.raw(`
        INSERT INTO sale_payments (id, sale_id, payment_method_id, amount)
        SELECT UUID(), s.id, ?, s.grand_total FROM sales s
        WHERE s.legacy_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sale_payments sp WHERE sp.sale_id = s.id)
    `, [methodIds.cash]);

    await knex.raw('DROP TABLE `payments`');
    await knex.raw('DROP TABLE `returns`');
    await knex.raw('DROP TABLE `transaction_items`');
    await knex.raw('DROP TABLE `transactions`');
    await knex.raw('ALTER TABLE `sales` DROP COLUMN `legacy_id`');
};

exports.down = async function (knex) {
    // Recreates the legacy tables (baseline definitions) and copies sales back, best effort:
    // returns, voids, customers, shifts, journals and IMEI links are lost.
    await knex.raw(`
        CREATE TABLE \`transactions\` (
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
            CONSTRAINT \`fk_transactions_branch\` FOREIGN KEY (\`branch_id\`) REFERENCES \`locations\` (\`id\`) ON DELETE RESTRICT ON UPDATE CASCADE,
            CONSTRAINT \`fk_transactions_user\` FOREIGN KEY (\`user_id\`) REFERENCES \`users\` (\`id\`) ON DELETE RESTRICT ON UPDATE CASCADE
        ) ${TABLE_OPTS}
    `);
    await knex.raw(`
        CREATE TABLE \`transaction_items\` (
            \`id\` int NOT NULL AUTO_INCREMENT,
            \`transaction_id\` int NOT NULL,
            \`product_id\` int NOT NULL,
            \`qty\` int NOT NULL,
            \`price\` decimal(12,2) NOT NULL,
            \`subtotal\` decimal(12,2) NOT NULL,
            PRIMARY KEY (\`id\`),
            KEY \`idx_ti_transaction\` (\`transaction_id\`),
            KEY \`idx_ti_product\` (\`product_id\`),
            CONSTRAINT \`fk_ti_variant\` FOREIGN KEY (\`product_id\`) REFERENCES \`product_variants\` (\`id\`) ON DELETE RESTRICT ON UPDATE CASCADE,
            CONSTRAINT \`fk_ti_transaction\` FOREIGN KEY (\`transaction_id\`) REFERENCES \`transactions\` (\`id\`) ON DELETE CASCADE ON UPDATE CASCADE
        ) ${TABLE_OPTS}
    `);
    await knex.raw(`
        CREATE TABLE \`payments\` (
            \`id\` int NOT NULL AUTO_INCREMENT,
            \`transaction_id\` int NOT NULL,
            \`method\` enum('cash','transfer','e-wallet','card') NOT NULL,
            \`amount\` decimal(12,2) NOT NULL,
            \`created_at\` datetime DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (\`id\`),
            KEY \`idx_payment_transaction\` (\`transaction_id\`),
            CONSTRAINT \`fk_payments_transaction\` FOREIGN KEY (\`transaction_id\`) REFERENCES \`transactions\` (\`id\`) ON DELETE CASCADE ON UPDATE CASCADE
        ) ${TABLE_OPTS}
    `);
    await knex.raw(`
        CREATE TABLE \`returns\` (
            \`id\` int NOT NULL AUTO_INCREMENT,
            \`transaction_id\` int NOT NULL,
            \`product_id\` int NOT NULL,
            \`qty\` int NOT NULL,
            \`reason\` text,
            \`created_at\` datetime DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (\`id\`),
            KEY \`idx_returns_transaction\` (\`transaction_id\`),
            KEY \`idx_returns_product\` (\`product_id\`),
            CONSTRAINT \`fk_returns_variant\` FOREIGN KEY (\`product_id\`) REFERENCES \`product_variants\` (\`id\`) ON DELETE RESTRICT ON UPDATE CASCADE,
            CONSTRAINT \`fk_returns_transaction\` FOREIGN KEY (\`transaction_id\`) REFERENCES \`transactions\` (\`id\`) ON DELETE CASCADE ON UPDATE CASCADE
        ) ${TABLE_OPTS}
    `);

    await knex.raw('ALTER TABLE `transactions` ADD COLUMN `sale_ref` char(36) NULL');
    await knex.raw(`
        INSERT INTO transactions (user_id, branch_id, total_amount, discount, final_amount, payment_status, created_at, sale_ref)
        SELECT cashier_id, location_id, subtotal, discount_total, grand_total, 'paid', occurred_at, id
        FROM sales WHERE status <> 'voided'
    `);
    await knex.raw(`
        INSERT INTO transaction_items (transaction_id, product_id, qty, price, subtotal)
        SELECT t.id, l.variant_id, l.qty, l.unit_price, l.qty * l.unit_price
        FROM sale_lines l JOIN transactions t ON t.sale_ref = l.sale_id WHERE l.variant_id IS NOT NULL
    `);
    await knex.raw(`
        INSERT INTO payments (transaction_id, method, amount)
        SELECT t.id, CASE pm.type WHEN 'cash' THEN 'cash' WHEN 'transfer' THEN 'transfer' WHEN 'card' THEN 'card' ELSE 'e-wallet' END, sp.amount
        FROM sale_payments sp JOIN transactions t ON t.sale_ref = sp.sale_id JOIN payment_methods pm ON pm.id = sp.payment_method_id
    `);
    await knex.raw('ALTER TABLE `transactions` DROP COLUMN `sale_ref`');

    for (const table of [
        'sale_return_lines', 'sale_returns', 'sale_payments', 'sale_lines', 'sales', 'cash_sessions', 'customers',
        'payment_methods', 'journal_lines', 'journal_entries', 'accounting_periods', 'account_mappings', 'accounts', 'settings',
    ]) {
        await knex.raw(`DROP TABLE \`${table}\``);
    }
};
