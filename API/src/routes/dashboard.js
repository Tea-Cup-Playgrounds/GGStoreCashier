const express = require('express');
const pool = require('../db');
const { authenticateToken } = require('../middleware/auth');

const router = express.Router();
router.use(authenticateToken);

// GET /api/dashboard
// Returns stats + recent transactions, branch-filtered by role
router.get('/', async (req, res) => {
    try {
        const { role, branch_id } = req.user;
        const isSuperAdmin = role === 'superadmin';

        // Branch filter clause
        const branchClause = isSuperAdmin ? '' : 'AND t.branch_id = ?';
        const branchParam = isSuperAdmin ? [] : [branch_id];

        const productBranchClause = isSuperAdmin ? '' : 'AND branch_id = ?';
        const productBranchParam = isSuperAdmin ? [] : [branch_id];

        // Today's revenue (sum of final_amount for today)
        const [todayRevenue] = await pool.execute(
            `SELECT COALESCE(SUM(final_amount), 0) AS revenue, COUNT(*) AS count
             FROM transactions t
             WHERE DATE(t.created_at) = CURDATE()
               AND t.payment_status = 'paid'
               ${branchClause}`,
            branchParam
        );

        // This month's transaction count
        const [monthlyStats] = await pool.execute(
            `SELECT COUNT(*) AS count, COALESCE(SUM(final_amount), 0) AS revenue
             FROM transactions t
             WHERE YEAR(t.created_at) = YEAR(CURDATE())
               AND MONTH(t.created_at) = MONTH(CURDATE())
               AND t.payment_status = 'paid'
               ${branchClause}`,
            branchParam
        );

        // Low stock products (stock <= 5)
        const [lowStock] = await pool.execute(
            `SELECT COUNT(*) AS count
             FROM products
             WHERE stock <= 5 AND stock > 0
               ${productBranchClause}`,
            productBranchParam
        );

        // Out of stock products (stock = 0)
        const [outOfStock] = await pool.execute(
            `SELECT COUNT(*) AS count
             FROM products
             WHERE stock = 0
               ${productBranchClause}`,
            productBranchParam
        );

        // Recent transactions (last 10) — use subquery for payment to avoid duplicate rows
        const [recentTransactions] = await pool.execute(
            `SELECT t.id, t.final_amount, t.payment_status, t.created_at,
                    u.name AS user_name,
                    b.name AS branch_name,
                    (SELECT method FROM payments WHERE transaction_id = t.id LIMIT 1) AS payment_method,
                    (SELECT COUNT(*) FROM transaction_items ti WHERE ti.transaction_id = t.id) AS item_count
             FROM transactions t
             LEFT JOIN users u ON t.user_id = u.id
             LEFT JOIN branches b ON t.branch_id = b.id
             WHERE 1=1 ${branchClause}
             ORDER BY t.created_at DESC
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
            recentTransactions,
        });

    } catch (error) {
        console.error('Dashboard error:', error);
        res.status(500).json({ error: 'Gagal mengambil data dashboard' });
    }
});

module.exports = router;
