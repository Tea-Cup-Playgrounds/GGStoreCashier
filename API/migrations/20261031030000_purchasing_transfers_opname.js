/**
 * Step 4 of the foundation plan (docs/foundation-design.md §4.3–4.4, §6): suppliers and goods
 * receipts, inter-location stock transfers, and stock counts (opname).
 *
 * All three are server-side documents (never created offline), numbered per location and day
 * through document_counters, e.g. GR-WH-261031-0001. Stock only changes when a document is
 * posted / sent / received / approved, always through services/stock.js.
 *
 * Journal entries for receipts and supplier payments arrive with the accounting core (step 5).
 */

const TABLE_OPTS = 'ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci';

exports.up = async function (knex) {
    await knex.raw(`
        CREATE TABLE \`document_counters\` (
            \`prefix\` varchar(10) NOT NULL,
            \`location_id\` int NOT NULL,
            \`day\` date NOT NULL,
            \`last_seq\` int NOT NULL DEFAULT 0,
            PRIMARY KEY (\`prefix\`, \`location_id\`, \`day\`)
        ) ${TABLE_OPTS}
    `);

    // ── suppliers & purchasing ───────────────────────────────────────────────
    await knex.raw(`
        CREATE TABLE \`suppliers\` (
            \`id\` int NOT NULL AUTO_INCREMENT,
            \`code\` varchar(20) NOT NULL,
            \`name\` varchar(150) NOT NULL,
            \`phone\` varchar(30) NULL,
            \`email\` varchar(100) NULL,
            \`address\` text NULL,
            \`notes\` text NULL,
            \`is_active\` tinyint(1) NOT NULL DEFAULT 1,
            \`created_at\` datetime DEFAULT CURRENT_TIMESTAMP,
            \`updated_at\` datetime(3) DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
            \`deleted_at\` datetime(3) NULL,
            PRIMARY KEY (\`id\`),
            UNIQUE KEY \`uq_suppliers_code\` (\`code\`)
        ) ${TABLE_OPTS}
    `);

    await knex.raw(`
        CREATE TABLE \`goods_receipts\` (
            \`id\` char(36) NOT NULL,
            \`number\` varchar(30) NOT NULL,
            \`supplier_id\` int NOT NULL,
            \`location_id\` int NOT NULL,
            \`invoice_no\` varchar(50) NULL,
            \`invoice_date\` date NULL,
            \`due_date\` date NULL,
            \`status\` enum('draft','posted') NOT NULL DEFAULT 'draft',
            \`subtotal\` decimal(15,2) NOT NULL DEFAULT 0,
            \`tax_total\` decimal(15,2) NOT NULL DEFAULT 0,
            \`grand_total\` decimal(15,2) NOT NULL DEFAULT 0,
            \`paid_total\` decimal(15,2) NOT NULL DEFAULT 0,
            \`note\` text NULL,
            \`created_by\` int NULL,
            \`posted_by\` int NULL,
            \`posted_at\` datetime(3) NULL,
            \`created_at\` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
            \`updated_at\` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
            PRIMARY KEY (\`id\`),
            UNIQUE KEY \`uq_gr_number\` (\`number\`),
            KEY \`idx_gr_supplier\` (\`supplier_id\`, \`status\`),
            KEY \`idx_gr_location\` (\`location_id\`, \`created_at\`),
            CONSTRAINT \`fk_gr_supplier\` FOREIGN KEY (\`supplier_id\`) REFERENCES \`suppliers\` (\`id\`) ON DELETE RESTRICT,
            CONSTRAINT \`fk_gr_location\` FOREIGN KEY (\`location_id\`) REFERENCES \`locations\` (\`id\`) ON DELETE RESTRICT,
            CONSTRAINT \`fk_gr_created_by\` FOREIGN KEY (\`created_by\`) REFERENCES \`users\` (\`id\`) ON DELETE SET NULL,
            CONSTRAINT \`fk_gr_posted_by\` FOREIGN KEY (\`posted_by\`) REFERENCES \`users\` (\`id\`) ON DELETE SET NULL
        ) ${TABLE_OPTS}
    `);

    // unit_cost excludes tax; tax_amount is the PPN input on the line.
    await knex.raw(`
        CREATE TABLE \`goods_receipt_items\` (
            \`id\` char(36) NOT NULL,
            \`receipt_id\` char(36) NOT NULL,
            \`variant_id\` int NOT NULL,
            \`qty\` int NOT NULL,
            \`unit_cost\` decimal(15,2) NOT NULL,
            \`tax_rate\` decimal(5,2) NOT NULL DEFAULT 0,
            \`tax_amount\` decimal(15,2) NOT NULL DEFAULT 0,
            \`line_total\` decimal(15,2) NOT NULL,
            \`sort_order\` int NOT NULL DEFAULT 0,
            PRIMARY KEY (\`id\`),
            KEY \`idx_gri_receipt\` (\`receipt_id\`),
            CONSTRAINT \`fk_gri_receipt\` FOREIGN KEY (\`receipt_id\`) REFERENCES \`goods_receipts\` (\`id\`) ON DELETE CASCADE,
            CONSTRAINT \`fk_gri_variant\` FOREIGN KEY (\`variant_id\`) REFERENCES \`product_variants\` (\`id\`) ON DELETE RESTRICT
        ) ${TABLE_OPTS}
    `);

    // IMEIs/serials entered on a draft receipt for serialized items; turned into product_units on post.
    await knex.raw(`
        CREATE TABLE \`goods_receipt_units\` (
            \`id\` char(36) NOT NULL,
            \`receipt_item_id\` char(36) NOT NULL,
            \`imei1\` varchar(20) NULL,
            \`imei2\` varchar(20) NULL,
            \`serial_number\` varchar(50) NULL,
            \`condition_grade\` enum('new','A','B','C') NOT NULL DEFAULT 'new',
            \`unit_id\` char(36) NULL,
            PRIMARY KEY (\`id\`),
            KEY \`idx_gru_item\` (\`receipt_item_id\`),
            CONSTRAINT \`fk_gru_item\` FOREIGN KEY (\`receipt_item_id\`) REFERENCES \`goods_receipt_items\` (\`id\`) ON DELETE CASCADE,
            CONSTRAINT \`fk_gru_unit\` FOREIGN KEY (\`unit_id\`) REFERENCES \`product_units\` (\`id\`) ON DELETE SET NULL
        ) ${TABLE_OPTS}
    `);

    await knex.raw(`
        CREATE TABLE \`supplier_payments\` (
            \`id\` char(36) NOT NULL,
            \`supplier_id\` int NOT NULL,
            \`receipt_id\` char(36) NULL,
            \`amount\` decimal(15,2) NOT NULL,
            \`method\` enum('cash','transfer','giro','other') NOT NULL,
            \`reference\` varchar(100) NULL,
            \`paid_at\` date NOT NULL,
            \`note\` text NULL,
            \`created_by\` int NULL,
            \`created_at\` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
            PRIMARY KEY (\`id\`),
            KEY \`idx_sp_supplier\` (\`supplier_id\`, \`paid_at\`),
            KEY \`idx_sp_receipt\` (\`receipt_id\`),
            CONSTRAINT \`fk_sp_supplier\` FOREIGN KEY (\`supplier_id\`) REFERENCES \`suppliers\` (\`id\`) ON DELETE RESTRICT,
            CONSTRAINT \`fk_sp_receipt\` FOREIGN KEY (\`receipt_id\`) REFERENCES \`goods_receipts\` (\`id\`) ON DELETE RESTRICT,
            CONSTRAINT \`fk_sp_created_by\` FOREIGN KEY (\`created_by\`) REFERENCES \`users\` (\`id\`) ON DELETE SET NULL
        ) ${TABLE_OPTS}
    `);

    // ── transfers ────────────────────────────────────────────────────────────
    // draft -> sent -> received | partially_received; cancelled only from draft. Anything sent but
    // not received stays in transit until resolved (returned to the source or written off).
    await knex.raw(`
        CREATE TABLE \`stock_transfers\` (
            \`id\` char(36) NOT NULL,
            \`number\` varchar(30) NOT NULL,
            \`from_location_id\` int NOT NULL,
            \`to_location_id\` int NOT NULL,
            \`status\` enum('draft','sent','received','partially_received','cancelled') NOT NULL DEFAULT 'draft',
            \`note\` text NULL,
            \`created_by\` int NULL,
            \`sent_by\` int NULL,
            \`sent_at\` datetime(3) NULL,
            \`received_by\` int NULL,
            \`received_at\` datetime(3) NULL,
            \`receive_note\` text NULL,
            \`resolved_by\` int NULL,
            \`resolved_at\` datetime(3) NULL,
            \`created_at\` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
            \`updated_at\` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
            PRIMARY KEY (\`id\`),
            UNIQUE KEY \`uq_st_number\` (\`number\`),
            KEY \`idx_st_from\` (\`from_location_id\`, \`status\`),
            KEY \`idx_st_to\` (\`to_location_id\`, \`status\`),
            CONSTRAINT \`fk_st_from\` FOREIGN KEY (\`from_location_id\`) REFERENCES \`locations\` (\`id\`) ON DELETE RESTRICT,
            CONSTRAINT \`fk_st_to\` FOREIGN KEY (\`to_location_id\`) REFERENCES \`locations\` (\`id\`) ON DELETE RESTRICT
        ) ${TABLE_OPTS}
    `);

    // qty_resolved: in-transit quantity later returned to the source or written off.
    await knex.raw(`
        CREATE TABLE \`stock_transfer_items\` (
            \`id\` char(36) NOT NULL,
            \`transfer_id\` char(36) NOT NULL,
            \`variant_id\` int NOT NULL,
            \`qty_sent\` int NOT NULL,
            \`qty_received\` int NULL,
            \`qty_resolved\` int NOT NULL DEFAULT 0,
            \`unit_cost\` decimal(15,2) NOT NULL DEFAULT 0,
            \`note\` text NULL,
            \`sort_order\` int NOT NULL DEFAULT 0,
            PRIMARY KEY (\`id\`),
            KEY \`idx_sti_transfer\` (\`transfer_id\`),
            CONSTRAINT \`fk_sti_transfer\` FOREIGN KEY (\`transfer_id\`) REFERENCES \`stock_transfers\` (\`id\`) ON DELETE CASCADE,
            CONSTRAINT \`fk_sti_variant\` FOREIGN KEY (\`variant_id\`) REFERENCES \`product_variants\` (\`id\`) ON DELETE RESTRICT
        ) ${TABLE_OPTS}
    `);

    // Serialized units on a transfer. outcome: NULL while pending/in transit.
    await knex.raw(`
        CREATE TABLE \`stock_transfer_units\` (
            \`transfer_item_id\` char(36) NOT NULL,
            \`unit_id\` char(36) NOT NULL,
            \`outcome\` enum('received','returned','written_off') NULL,
            PRIMARY KEY (\`transfer_item_id\`, \`unit_id\`),
            KEY \`idx_stu_unit\` (\`unit_id\`),
            CONSTRAINT \`fk_stu_item\` FOREIGN KEY (\`transfer_item_id\`) REFERENCES \`stock_transfer_items\` (\`id\`) ON DELETE CASCADE,
            CONSTRAINT \`fk_stu_unit\` FOREIGN KEY (\`unit_id\`) REFERENCES \`product_units\` (\`id\`) ON DELETE RESTRICT
        ) ${TABLE_OPTS}
    `);

    // ── stock opname ─────────────────────────────────────────────────────────
    await knex.raw(`
        CREATE TABLE \`stock_opnames\` (
            \`id\` char(36) NOT NULL,
            \`number\` varchar(30) NOT NULL,
            \`location_id\` int NOT NULL,
            \`status\` enum('counting','approved','cancelled') NOT NULL DEFAULT 'counting',
            \`category_id\` int NULL,
            \`note\` text NULL,
            \`created_by\` int NULL,
            \`approved_by\` int NULL,
            \`approved_at\` datetime(3) NULL,
            \`created_at\` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
            \`updated_at\` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
            PRIMARY KEY (\`id\`),
            UNIQUE KEY \`uq_so_number\` (\`number\`),
            KEY \`idx_so_location\` (\`location_id\`, \`status\`),
            CONSTRAINT \`fk_so_location\` FOREIGN KEY (\`location_id\`) REFERENCES \`locations\` (\`id\`) ON DELETE RESTRICT,
            CONSTRAINT \`fk_so_category\` FOREIGN KEY (\`category_id\`) REFERENCES \`categories\` (\`id\`) ON DELETE SET NULL
        ) ${TABLE_OPTS}
    `);

    // system_qty is the snapshot when counting started; approval applies (counted - system_qty).
    await knex.raw(`
        CREATE TABLE \`stock_opname_items\` (
            \`id\` char(36) NOT NULL,
            \`opname_id\` char(36) NOT NULL,
            \`variant_id\` int NOT NULL,
            \`system_qty\` int NOT NULL,
            \`counted_qty\` int NULL,
            \`note\` text NULL,
            PRIMARY KEY (\`id\`),
            UNIQUE KEY \`uq_soi_variant\` (\`opname_id\`, \`variant_id\`),
            CONSTRAINT \`fk_soi_opname\` FOREIGN KEY (\`opname_id\`) REFERENCES \`stock_opnames\` (\`id\`) ON DELETE CASCADE,
            CONSTRAINT \`fk_soi_variant\` FOREIGN KEY (\`variant_id\`) REFERENCES \`product_variants\` (\`id\`) ON DELETE RESTRICT
        ) ${TABLE_OPTS}
    `);

    // Serialized units expected at the location when counting started, and whether they were scanned.
    await knex.raw(`
        CREATE TABLE \`stock_opname_units\` (
            \`opname_id\` char(36) NOT NULL,
            \`unit_id\` char(36) NOT NULL,
            \`found\` tinyint(1) NOT NULL DEFAULT 0,
            PRIMARY KEY (\`opname_id\`, \`unit_id\`),
            CONSTRAINT \`fk_sou_opname\` FOREIGN KEY (\`opname_id\`) REFERENCES \`stock_opnames\` (\`id\`) ON DELETE CASCADE,
            CONSTRAINT \`fk_sou_unit\` FOREIGN KEY (\`unit_id\`) REFERENCES \`product_units\` (\`id\`) ON DELETE RESTRICT
        ) ${TABLE_OPTS}
    `);

    // IMEIs/serials scanned during the count that weren't expected here (unknown, or registered elsewhere).
    await knex.raw(`
        CREATE TABLE \`stock_opname_extras\` (
            \`id\` char(36) NOT NULL,
            \`opname_id\` char(36) NOT NULL,
            \`identifier\` varchar(50) NOT NULL,
            \`unit_id\` char(36) NULL,
            \`created_at\` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
            PRIMARY KEY (\`id\`),
            UNIQUE KEY \`uq_soe_identifier\` (\`opname_id\`, \`identifier\`),
            CONSTRAINT \`fk_soe_opname\` FOREIGN KEY (\`opname_id\`) REFERENCES \`stock_opnames\` (\`id\`) ON DELETE CASCADE,
            CONSTRAINT \`fk_soe_unit\` FOREIGN KEY (\`unit_id\`) REFERENCES \`product_units\` (\`id\`) ON DELETE SET NULL
        ) ${TABLE_OPTS}
    `);
};

exports.down = async function (knex) {
    for (const table of [
        'stock_opname_extras', 'stock_opname_units', 'stock_opname_items', 'stock_opnames',
        'stock_transfer_units', 'stock_transfer_items', 'stock_transfers',
        'supplier_payments', 'goods_receipt_units', 'goods_receipt_items', 'goods_receipts', 'suppliers',
        'document_counters',
    ]) {
        await knex.raw(`DROP TABLE IF EXISTS \`${table}\``);
    }
};
