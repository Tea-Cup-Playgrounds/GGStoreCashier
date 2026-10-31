// Shared catalog queries.

// On-hand quantity of variant `v` at the location in `sl` (stock_levels row, may be NULL).
// Serialized variants count in-stock units; others use stock_levels.qty.
const ON_HAND_SQL = `
    CASE WHEN p.is_serialized = 1
         THEN (SELECT COUNT(*) FROM product_units u
               WHERE u.variant_id = v.id AND u.location_id = sl.location_id AND u.status = 'in_stock')
         ELSE COALESCE(sl.qty, 0) END`;

// Average cost at the location: stock_levels.avg_cost for quantity items; for serialized items
// (cost tracked per unit) the mean cost of the units in stock there.
const AVG_COST_SQL = `
    CASE WHEN p.is_serialized = 1
         THEN (SELECT ROUND(AVG(u.unit_cost), 2) FROM product_units u
               WHERE u.variant_id = v.id AND u.location_id = sl.location_id AND u.status = 'in_stock')
         ELSE sl.avg_cost END`;

const DISPLAY_NAME_SQL = "CONCAT(p.name, IF(v.name IS NULL OR v.name = '', '', CONCAT(' ', v.name)))";

const ACTIVE_VARIANT_SQL = `
    v.deleted_at IS NULL AND v.is_active = 1 AND p.deleted_at IS NULL AND p.is_active = 1`;

// Cost prices are hidden from cashiers: only people who adjust stock or read reports at the
// location see them.
const canSeeCost = (access, locationId) =>
    access.can('stock.adjust', locationId) || access.can('reports.view_location', locationId) ||
    access.can('purchases.manage', locationId) || access.can('accounting.view', locationId);

// Next free SKU for a generated variant. Uses the variant id, so call after INSERT.
const assignGeneratedSku = async (db, variantId) => {
    await db.execute(
        "UPDATE product_variants SET sku = CONCAT('SKU-', LPAD(id, 6, '0')) WHERE id = ?",
        [variantId]
    );
};

module.exports = {
    ON_HAND_SQL,
    AVG_COST_SQL,
    DISPLAY_NAME_SQL,
    ACTIVE_VARIANT_SQL,
    canSeeCost,
    assignGeneratedSku,
};
