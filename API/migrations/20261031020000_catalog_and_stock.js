/**
 * Step 3 of the foundation plan (docs/foundation-design.md §4.2–4.3, §6): catalog and stock.
 *
 *   products (model) -> product_variants (sellable SKU) -> product_units (one physical IMEI/serial item)
 *   stock_levels: per-location quantity (non-serialized), moving-average cost, optional price override
 *   stock_movements: every stock change, written by services/stock.js in the same transaction
 *   stock_on_hand (view): sellable quantity per location for both serialized and non-serialized items
 *
 * Each legacy product becomes a product + one variant with the SAME id, so transaction_items.product_id
 * and returns.product_id keep pointing at the right row (their foreign keys now reference
 * product_variants). Legacy stock becomes a stock_levels row at the product's branch (or the
 * warehouse when it had no branch) plus an opening-balance movement. The old stock_movements
 * rows are kept, unlinked, in stock_movements_legacy.
 */

const TABLE_OPTS = 'ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci';

exports.up = async function (knex) {
    await knex.raw('RENAME TABLE `products` TO `products_legacy`');
    await knex.raw('RENAME TABLE `stock_movements` TO `stock_movements_legacy`');

    // ── reference data ───────────────────────────────────────────────────────
    await knex.raw(`
        CREATE TABLE \`brands\` (
            \`id\` int NOT NULL AUTO_INCREMENT,
            \`name\` varchar(100) NOT NULL,
            \`created_at\` datetime DEFAULT CURRENT_TIMESTAMP,
            \`updated_at\` datetime(3) DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
            \`deleted_at\` datetime(3) NULL,
            PRIMARY KEY (\`id\`),
            UNIQUE KEY \`uq_brands_name\` (\`name\`)
        ) ${TABLE_OPTS}
    `);

    await knex.raw(`
        CREATE TABLE \`tax_rates\` (
            \`id\` int NOT NULL AUTO_INCREMENT,
            \`name\` varchar(50) NOT NULL,
            \`rate\` decimal(5,2) NOT NULL,
            \`is_active\` tinyint(1) NOT NULL DEFAULT 1,
            \`created_at\` datetime DEFAULT CURRENT_TIMESTAMP,
            \`updated_at\` datetime(3) DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
            PRIMARY KEY (\`id\`),
            UNIQUE KEY \`uq_tax_rates_name\` (\`name\`)
        ) ${TABLE_OPTS}
    `);
    await knex.raw("INSERT INTO `tax_rates` (`name`, `rate`) VALUES ('PPN 11%', 11.00)");

    await knex.raw(`
        ALTER TABLE \`categories\`
            ADD COLUMN \`parent_id\` int NULL AFTER \`id\`,
            ADD KEY \`idx_categories_parent\` (\`parent_id\`),
            ADD CONSTRAINT \`fk_categories_parent\` FOREIGN KEY (\`parent_id\`) REFERENCES \`categories\` (\`id\`) ON DELETE SET NULL
    `);

    // ── catalog ──────────────────────────────────────────────────────────────
    // Constraint names must be unique per schema; products_legacy still holds fk_products_*.
    await knex.raw(`
        CREATE TABLE \`products\` (
            \`id\` int NOT NULL AUTO_INCREMENT,
            \`name\` varchar(150) NOT NULL,
            \`description\` text NULL,
            \`category_id\` int NULL,
            \`brand_id\` int NULL,
            \`kind\` enum('goods','service','digital') NOT NULL DEFAULT 'goods',
            \`is_serialized\` tinyint(1) NOT NULL DEFAULT 0,
            \`serial_type\` enum('imei','imei_dual','serial') NULL,
            \`warranty_months\` smallint NOT NULL DEFAULT 0,
            \`tax_rate_id\` int NULL,
            \`image\` varchar(255) NULL,
            \`is_active\` tinyint(1) NOT NULL DEFAULT 1,
            \`created_at\` datetime DEFAULT CURRENT_TIMESTAMP,
            \`updated_at\` datetime(3) DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
            \`deleted_at\` datetime(3) NULL,
            PRIMARY KEY (\`id\`),
            KEY \`idx_prod_category\` (\`category_id\`),
            KEY \`idx_prod_brand\` (\`brand_id\`),
            KEY \`idx_prod_updated\` (\`updated_at\`),
            CONSTRAINT \`fk_prod_category\` FOREIGN KEY (\`category_id\`) REFERENCES \`categories\` (\`id\`) ON DELETE SET NULL,
            CONSTRAINT \`fk_prod_brand\` FOREIGN KEY (\`brand_id\`) REFERENCES \`brands\` (\`id\`) ON DELETE SET NULL,
            CONSTRAINT \`fk_prod_tax\` FOREIGN KEY (\`tax_rate_id\`) REFERENCES \`tax_rates\` (\`id\`) ON DELETE SET NULL
        ) ${TABLE_OPTS}
    `);

    // name NULL = the product's only/default variant; display name is the product name alone.
    await knex.raw(`
        CREATE TABLE \`product_variants\` (
            \`id\` int NOT NULL AUTO_INCREMENT,
            \`product_id\` int NOT NULL,
            \`sku\` varchar(50) NOT NULL,
            \`barcode\` varchar(100) NULL,
            \`name\` varchar(100) NULL,
            \`attributes\` json NULL,
            \`base_price\` decimal(15,2) NOT NULL DEFAULT 0,
            \`min_price\` decimal(15,2) NULL,
            \`is_active\` tinyint(1) NOT NULL DEFAULT 1,
            \`created_at\` datetime DEFAULT CURRENT_TIMESTAMP,
            \`updated_at\` datetime(3) DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
            \`deleted_at\` datetime(3) NULL,
            PRIMARY KEY (\`id\`),
            UNIQUE KEY \`uq_variants_sku\` (\`sku\`),
            UNIQUE KEY \`uq_variants_barcode\` (\`barcode\`),
            KEY \`idx_variants_product\` (\`product_id\`),
            KEY \`idx_variants_updated\` (\`updated_at\`),
            CONSTRAINT \`fk_variants_product\` FOREIGN KEY (\`product_id\`) REFERENCES \`products\` (\`id\`) ON DELETE RESTRICT
        ) ${TABLE_OPTS}
    `);

    // ── stock ────────────────────────────────────────────────────────────────
    // A row means "this variant is stocked at this location". For serialized variants qty stays 0
    // (units are counted instead) and the row only carries the price override and reorder level.
    await knex.raw(`
        CREATE TABLE \`stock_levels\` (
            \`location_id\` int NOT NULL,
            \`variant_id\` int NOT NULL,
            \`qty\` int NOT NULL DEFAULT 0,
            \`avg_cost\` decimal(15,2) NOT NULL DEFAULT 0,
            \`sell_price\` decimal(15,2) NULL,
            \`reorder_level\` int NULL,
            \`updated_at\` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
            PRIMARY KEY (\`location_id\`, \`variant_id\`),
            KEY \`idx_stock_levels_variant\` (\`variant_id\`),
            CONSTRAINT \`fk_sl_location\` FOREIGN KEY (\`location_id\`) REFERENCES \`locations\` (\`id\`) ON DELETE RESTRICT,
            CONSTRAINT \`fk_sl_variant\` FOREIGN KEY (\`variant_id\`) REFERENCES \`product_variants\` (\`id\`) ON DELETE RESTRICT
        ) ${TABLE_OPTS}
    `);

    // location_id is NULL while a unit is in transit or after it has been sold / written off.
    await knex.raw(`
        CREATE TABLE \`product_units\` (
            \`id\` char(36) NOT NULL,
            \`variant_id\` int NOT NULL,
            \`location_id\` int NULL,
            \`imei1\` varchar(20) NULL,
            \`imei2\` varchar(20) NULL,
            \`serial_number\` varchar(50) NULL,
            \`status\` enum('in_stock','in_transit','reserved','sold','returned','in_service','defective','written_off') NOT NULL DEFAULT 'in_stock',
            \`condition_grade\` enum('new','A','B','C') NOT NULL DEFAULT 'new',
            \`unit_cost\` decimal(15,2) NOT NULL DEFAULT 0,
            \`sell_price\` decimal(15,2) NULL,
            \`source_type\` enum('purchase','trade_in','adjustment','return') NOT NULL,
            \`source_id\` char(36) NULL,
            \`sold_sale_line_id\` char(36) NULL,
            \`warranty_until\` date NULL,
            \`notes\` text NULL,
            \`created_at\` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
            \`updated_at\` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
            PRIMARY KEY (\`id\`),
            UNIQUE KEY \`uq_units_imei1\` (\`imei1\`),
            UNIQUE KEY \`uq_units_imei2\` (\`imei2\`),
            UNIQUE KEY \`uq_units_serial\` (\`serial_number\`),
            KEY \`idx_units_lookup\` (\`variant_id\`, \`location_id\`, \`status\`),
            KEY \`idx_units_location\` (\`location_id\`, \`status\`),
            KEY \`idx_units_updated\` (\`updated_at\`),
            CONSTRAINT \`fk_units_variant\` FOREIGN KEY (\`variant_id\`) REFERENCES \`product_variants\` (\`id\`) ON DELETE RESTRICT,
            CONSTRAINT \`fk_units_location\` FOREIGN KEY (\`location_id\`) REFERENCES \`locations\` (\`id\`) ON DELETE RESTRICT
        ) ${TABLE_OPTS}
    `);

    await knex.raw(`
        CREATE TABLE \`stock_movements\` (
            \`id\` char(36) NOT NULL,
            \`location_id\` int NOT NULL,
            \`variant_id\` int NOT NULL,
            \`unit_id\` char(36) NULL,
            \`qty_change\` int NOT NULL,
            \`unit_cost\` decimal(15,2) NOT NULL DEFAULT 0,
            \`reason\` enum('purchase','purchase_return','sale','sale_return','transfer_out','transfer_in',
                            'adjustment','opname','trade_in','service_part','write_off') NOT NULL,
            \`ref_type\` varchar(30) NULL,
            \`ref_id\` varchar(36) NULL,
            \`user_id\` int NULL,
            \`device_id\` char(36) NULL,
            \`note\` text NULL,
            \`created_at\` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
            PRIMARY KEY (\`id\`),
            KEY \`idx_sm_location_variant\` (\`location_id\`, \`variant_id\`, \`created_at\`),
            KEY \`idx_sm_unit\` (\`unit_id\`),
            KEY \`idx_sm_ref\` (\`ref_type\`, \`ref_id\`),
            CONSTRAINT \`fk_sm_location\` FOREIGN KEY (\`location_id\`) REFERENCES \`locations\` (\`id\`) ON DELETE RESTRICT,
            CONSTRAINT \`fk_sm_variant\` FOREIGN KEY (\`variant_id\`) REFERENCES \`product_variants\` (\`id\`) ON DELETE RESTRICT,
            CONSTRAINT \`fk_sm_unit\` FOREIGN KEY (\`unit_id\`) REFERENCES \`product_units\` (\`id\`) ON DELETE RESTRICT,
            CONSTRAINT \`fk_sm_user\` FOREIGN KEY (\`user_id\`) REFERENCES \`users\` (\`id\`) ON DELETE SET NULL
        ) ${TABLE_OPTS}
    `);

    await knex.raw(`
        CREATE VIEW \`stock_on_hand\` AS
        SELECT sl.location_id, sl.variant_id,
               CASE WHEN p.is_serialized = 1
                    THEN (SELECT COUNT(*) FROM product_units u
                          WHERE u.variant_id = sl.variant_id AND u.location_id = sl.location_id AND u.status = 'in_stock')
                    ELSE sl.qty END AS qty
        FROM stock_levels sl
        JOIN product_variants v ON v.id = sl.variant_id
        JOIN products p ON p.id = v.product_id
    `);

    // ── migrate legacy data ──────────────────────────────────────────────────
    await knex.raw(`
        INSERT INTO products (id, name, category_id, kind, is_serialized, image, created_at, updated_at)
        SELECT id, name, category_id, 'goods', 0, product_image, created_at, updated_at FROM products_legacy
    `);
    await knex.raw(`
        INSERT INTO product_variants (id, product_id, sku, barcode, name, base_price, created_at, updated_at)
        SELECT id, id, CONCAT('SKU-', LPAD(id, 6, '0')), NULLIF(barcode, ''), NULL, sell_price, created_at, updated_at
        FROM products_legacy
    `);
    await knex.raw(`
        INSERT INTO stock_levels (location_id, variant_id, qty, avg_cost)
        SELECT COALESCE(pl.branch_id, wh.id), pl.id, GREATEST(COALESCE(pl.stock, 0), 0), 0
        FROM products_legacy pl
        CROSS JOIN (SELECT id FROM locations WHERE code = 'WH') wh
    `);
    await knex.raw(`
        INSERT INTO stock_movements (id, location_id, variant_id, qty_change, unit_cost, reason, note)
        SELECT UUID(), location_id, variant_id, qty, 0, 'adjustment', 'Saldo awal (migrasi dari skema lama)'
        FROM stock_levels WHERE qty > 0
    `);

    // ── repoint legacy foreign keys ──────────────────────────────────────────
    await knex.raw('ALTER TABLE `transaction_items` DROP FOREIGN KEY `fk_ti_product`');
    await knex.raw('ALTER TABLE `transaction_items` ADD CONSTRAINT `fk_ti_variant` FOREIGN KEY (`product_id`) REFERENCES `product_variants` (`id`) ON DELETE RESTRICT ON UPDATE CASCADE');
    await knex.raw('ALTER TABLE `returns` DROP FOREIGN KEY `fk_returns_product`');
    await knex.raw('ALTER TABLE `returns` ADD CONSTRAINT `fk_returns_variant` FOREIGN KEY (`product_id`) REFERENCES `product_variants` (`id`) ON DELETE RESTRICT ON UPDATE CASCADE');

    await knex.raw('ALTER TABLE `stock_movements_legacy` DROP FOREIGN KEY `fk_stock_product`, DROP FOREIGN KEY `fk_stock_branch`');
    await knex.raw('DROP TABLE `products_legacy`');
};

exports.down = async function (knex) {
    // Best effort, for development rollbacks: each variant becomes one legacy product (same id)
    // at the first branch that stocks it. Stock at other locations, units, brands and tax rates
    // are lost.
    await knex.raw(`
        CREATE TABLE \`products_legacy\` (
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
            KEY \`idx_products_branch\` (\`branch_id\`)
        ) ${TABLE_OPTS}
    `);
    await knex.raw(`
        INSERT INTO products_legacy (id, name, barcode, category_id, sell_price, stock, product_image, branch_id, created_at, updated_at)
        SELECT v.id,
               LEFT(CONCAT(p.name, IF(v.name IS NULL, '', CONCAT(' ', v.name))), 150),
               v.barcode, p.category_id, v.base_price,
               COALESCE((SELECT soh.qty FROM stock_on_hand soh JOIN locations l ON l.id = soh.location_id
                         WHERE soh.variant_id = v.id AND l.type = 'branch' ORDER BY soh.location_id LIMIT 1), 0),
               p.image,
               (SELECT sl.location_id FROM stock_levels sl JOIN locations l ON l.id = sl.location_id
                WHERE sl.variant_id = v.id AND l.type = 'branch' ORDER BY sl.location_id LIMIT 1),
               v.created_at, v.updated_at
        FROM product_variants v JOIN products p ON p.id = v.product_id
    `);

    await knex.raw('ALTER TABLE `transaction_items` DROP FOREIGN KEY `fk_ti_variant`');
    await knex.raw('ALTER TABLE `returns` DROP FOREIGN KEY `fk_returns_variant`');

    await knex.raw('DROP VIEW `stock_on_hand`');
    await knex.raw('DROP TABLE `stock_movements`');
    await knex.raw('DROP TABLE `product_units`');
    await knex.raw('DROP TABLE `stock_levels`');
    await knex.raw('DROP TABLE `product_variants`');
    await knex.raw('DROP TABLE `products`');
    await knex.raw('DROP TABLE `brands`');
    await knex.raw('DROP TABLE `tax_rates`');
    await knex.raw('ALTER TABLE `categories` DROP FOREIGN KEY `fk_categories_parent`, DROP INDEX `idx_categories_parent`, DROP COLUMN `parent_id`');

    await knex.raw('RENAME TABLE `products_legacy` TO `products`');
    await knex.raw(`
        ALTER TABLE \`products\`
            ADD CONSTRAINT \`fk_products_branch\` FOREIGN KEY (\`branch_id\`) REFERENCES \`locations\` (\`id\`) ON DELETE SET NULL ON UPDATE CASCADE,
            ADD CONSTRAINT \`fk_products_category\` FOREIGN KEY (\`category_id\`) REFERENCES \`categories\` (\`id\`) ON DELETE SET NULL ON UPDATE CASCADE
    `);
    await knex.raw('ALTER TABLE `transaction_items` ADD CONSTRAINT `fk_ti_product` FOREIGN KEY (`product_id`) REFERENCES `products` (`id`) ON DELETE RESTRICT ON UPDATE CASCADE');
    await knex.raw('ALTER TABLE `returns` ADD CONSTRAINT `fk_returns_product` FOREIGN KEY (`product_id`) REFERENCES `products` (`id`) ON DELETE RESTRICT ON UPDATE CASCADE');

    await knex.raw('RENAME TABLE `stock_movements_legacy` TO `stock_movements`');
    await knex.raw(`
        ALTER TABLE \`stock_movements\`
            ADD CONSTRAINT \`fk_stock_branch\` FOREIGN KEY (\`branch_id\`) REFERENCES \`locations\` (\`id\`) ON DELETE CASCADE ON UPDATE CASCADE,
            ADD CONSTRAINT \`fk_stock_product\` FOREIGN KEY (\`product_id\`) REFERENCES \`products\` (\`id\`) ON DELETE CASCADE ON UPDATE CASCADE
    `);
};
