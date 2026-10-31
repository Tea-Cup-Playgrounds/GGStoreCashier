const express = require('express');
const pool = require('../db');
const { authenticateToken } = require('../middleware/auth');

const router = express.Router();
router.use(authenticateToken);

// Revenue counts what customers kept: sale total minus refunds, voided sales excluded.
const NET_REVENUE = 'COALESCE(SUM(s.grand_total - s.refunded_total), 0)';

// GET /api/dashboard
// Returns stats + recent sales, branch-filtered by role. Response keys predate the sales model
// (recentTransactions, final_amount, ...) and are kept for the app's home screen.
router.get('/', async (req, res) => {
    try {
        const { role, branch_id } = req.user;
        const isSuperAdmin = role === 'superadmin';

        const branchClause = isSuperAdmin ? '' : 'AND s.location_id = ?';
        const branchParam = isSuperAdmin ? [] : [branch_id];

        const productBranchClause = isSuperAdmin ? '' : 'AND soh.location_id = ?';
        const productBranchParam = isSuperAdmin ? [] : [branch_id];

        // Stock rows (variant x branch) of active catalog items; see the stock_on_hand view.
        const stockFrom = `
            FROM stock_on_hand soh
            JOIN locations l ON l.id = soh.location_id AND l.type = 'branch'
            JOIN product_variants v ON v.id = soh.variant_id AND v.deleted_at IS NULL AND v.is_active = 1
            JOIN products p ON p.id = v.product_id AND p.deleted_at IS NULL AND p.is_active = 1`;

        const [todayRevenue] = await pool.execute(
            `SELECT ${NET_REVENUE} AS revenue, COUNT(*) AS count
             FROM sales s
             WHERE DATE(s.occurred_at) = CURDATE() AND s.status <> 'voided' ${branchClause}`,
            branchParam
        );

        const [monthlyStats] = await pool.execute(
            `SELECT COUNT(*) AS count, ${NET_REVENUE} AS revenue
             FROM sales s
             WHERE YEAR(s.occurred_at) = YEAR(CURDATE()) AND MONTH(s.occurred_at) = MONTH(CURDATE())
               AND s.status <> 'voided' ${branchClause}`,
            branchParam
        );

        const [lowStock] = await pool.execute(
            `SELECT COUNT(*) AS count
             ${stockFrom}
             WHERE soh.qty <= 5 AND soh.qty > 0
               ${productBranchClause}`,
            productBranchParam
        );

        const [outOfStock] = await pool.execute(
            `SELECT COUNT(*) AS count
             ${stockFrom}
             WHERE soh.qty <= 0
               ${productBranchClause}`,
            productBranchParam
        );

        const [recentTransactions] = await pool.execute(
            `SELECT s.id, s.number, s.grand_total - s.refunded_total AS final_amount,
                    CASE s.status WHEN 'voided' THEN 'voided' ELSE 'paid' END AS payment_status, s.status,
                    s.occurred_at AS created_at,
                    u.name AS user_name,
                    l.name AS branch_name,
                    (SELECT pm.name FROM sale_payments sp JOIN payment_methods pm ON pm.id = sp.payment_method_id
                     WHERE sp.sale_id = s.id ORDER BY sp.amount DESC LIMIT 1) AS payment_method,
                    (SELECT COALESCE(SUM(sl.qty), 0) FROM sale_lines sl WHERE sl.sale_id = s.id) AS item_count
             FROM sales s
             LEFT JOIN users u ON s.cashier_id = u.id
             LEFT JOIN locations l ON s.location_id = l.id
             WHERE 1=1 ${branchClause}
             ORDER BY s.occurred_at DESC
             LIMIT 10`,
            branchParam
        );

        res.json({
            stats: {
                todayRevenue: parseFloat(todayRevenue[0].revenue),
                todayTransactions: parseInt(todayRevenue[0].count),
                monthlyTransactions: parseInt(monthlyStats[0].count),
                monthlyRevenue: parseFloat(monthlyStats[0].revenue),
                lowStockCount: parseInt(lowStock[0].count),
                outOfStockCount: parseInt(outOfStock[0].count),
            },
            recentTransactions: recentTransactions.map((t) => ({ ...t, item_count: Number(t.item_count) })),
        });

    } catch (error) {
        console.error('Dashboard error:', error);
        res.status(500).json({ error: 'Gagal mengambil data dashboard' });
    }
});

module.exports = router;
