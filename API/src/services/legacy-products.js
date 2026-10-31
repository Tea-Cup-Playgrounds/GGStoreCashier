// Compatibility layer for the pre-catalog /api/products contract, used by the current Flutter
// app until it moves to /api/catalog and /api/stock. A legacy "product" is one variant as seen
// from one location: id = variant id, stock = on-hand there, sell_price = effective price there.
// Without a location, stock is the total over all branches and sell_price is the base price.
const pool = require('../db');
const { ON_HAND_SQL, DISPLAY_NAME_SQL, ACTIVE_VARIANT_SQL } = require('./catalog');

const legacyProductSelect = (locationId) => {
    if (locationId) {
        return {
            sql: `
                SELECT v.id, ${DISPLAY_NAME_SQL} AS name, v.barcode, p.category_id,
                       COALESCE(sl.sell_price, v.base_price) AS sell_price,
                       ${ON_HAND_SQL} AS stock,
                       p.image AS product_image, p.is_serialized, l.id AS branch_id, p.description,
                       c.name AS category_name, l.name AS branch_name,
                       v.created_at, GREATEST(p.updated_at, v.updated_at) AS updated_at
                FROM product_variants v
                JOIN products p ON p.id = v.product_id
                JOIN locations l ON l.id = ?
                LEFT JOIN stock_levels sl ON sl.variant_id = v.id AND sl.location_id = l.id
                LEFT JOIN categories c ON c.id = p.category_id
                WHERE p.kind = 'goods' AND ${ACTIVE_VARIANT_SQL}`,
            params: [Number(locationId)],
        };
    }
    return {
        sql: `
            SELECT v.id, ${DISPLAY_NAME_SQL} AS name, v.barcode, p.category_id, v.base_price AS sell_price,
                   COALESCE((SELECT SUM(soh.qty) FROM stock_on_hand soh JOIN locations bl ON bl.id = soh.location_id
                             WHERE soh.variant_id = v.id AND bl.type = 'branch'), 0) AS stock,
                   p.image AS product_image, p.is_serialized, NULL AS branch_id, p.description,
                   c.name AS category_name, NULL AS branch_name,
                   v.created_at, GREATEST(p.updated_at, v.updated_at) AS updated_at
            FROM product_variants v
            JOIN products p ON p.id = v.product_id
            LEFT JOIN categories c ON c.id = p.category_id
            WHERE p.kind = 'goods' AND ${ACTIVE_VARIANT_SQL}`,
        params: [],
    };
};

const normalize = (row) => ({ ...row, stock: Number(row.stock), is_serialized: !!row.is_serialized });

const listLegacyProducts = async (db, { locationId, categoryId, search }) => {
    const base = legacyProductSelect(locationId);
    let sql = base.sql;
    const params = [...base.params];
    if (categoryId) { sql += ' AND p.category_id = ?'; params.push(Number(categoryId)); }
    if (search) {
        sql += ' AND (p.name LIKE ? OR v.name LIKE ? OR v.barcode LIKE ? OR v.sku LIKE ?)';
        params.push(`%${search}%`, `%${search}%`, `%${search}%`, `%${search}%`);
    }
    sql += ' ORDER BY v.created_at DESC, v.id DESC';
    const [rows] = await db.execute(sql, params);
    return rows.map(normalize);
};

const getLegacyProduct = async (db, variantId, locationId) => {
    const base = legacyProductSelect(locationId);
    const [rows] = await db.execute(`${base.sql} AND v.id = ?`, [...base.params, Number(variantId)]);
    return rows.length > 0 ? normalize(rows[0]) : null;
};

// Socket.IO rooms are per branch; 'branch-0' is the superadmin "all branches" room.
const emitLegacyProduct = async (req, event, variantId, locationIds) => {
    const io = req.app.get('io');
    if (!io) return;
    for (const locationId of locationIds) {
        const product = await getLegacyProduct(pool, variantId, locationId);
        if (product) io.to(`branch-${locationId}`).emit(event, product);
    }
    const overall = await getLegacyProduct(pool, variantId, null);
    if (overall) io.to('branch-0').emit(event, overall);
};

module.exports = {
    listLegacyProducts,
    getLegacyProduct,
    emitLegacyProduct,
};
