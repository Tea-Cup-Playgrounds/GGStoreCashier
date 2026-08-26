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

        // Low stock products (stock <= 50)
        const [lowStock] = await pool.execute(
            `SELECT COUNT(*) AS count
             FROM products
             WHERE stock <= 50
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

// ── GET /api/dashboard/admin ──────────────────────────────────────────────────
// Admin-specific dashboard: omset today vs target, payment split, hourly trend.
router.get('/admin', async (req, res) => {
    try {
        const { role, branch_id } = req.user;
        if (role !== 'admin') {
            return res.status(403).json({ error: 'Akses ditolak' });
        }

        // Today's revenue + tx count
        const [[today]] = await pool.execute(
            `SELECT COALESCE(SUM(final_amount),0) AS revenue, COUNT(*) AS tx_count
             FROM transactions WHERE payment_status='paid' AND DATE(created_at)=CURDATE() AND branch_id=?`,
            [branch_id]
        );

        // Branch target_pendapatan
        const [[branch]] = await pool.execute(
            `SELECT name, COALESCE(target_pendapatan,0) AS target_pendapatan FROM branches WHERE id=?`,
            [branch_id]
        );

        // Payment split today: cash vs digital
        const [paymentSplit] = await pool.execute(
            `SELECT p.method, COALESCE(SUM(p.amount),0) AS total
             FROM payments p
             JOIN transactions t ON p.transaction_id = t.id
             WHERE t.payment_status='paid' AND DATE(t.created_at)=CURDATE() AND t.branch_id=?
             GROUP BY p.method`,
            [branch_id]
        );

        let cashTotal = 0, digitalTotal = 0;
        for (const row of paymentSplit) {
            const m = (row.method || '').toLowerCase();
            if (m === 'cash' || m === 'tunai') {
                cashTotal += parseFloat(row.total);
            } else {
                digitalTotal += parseFloat(row.total);
            }
        }

        // Trend query — same pattern as superadmin but branch-scoped
        const trendType = req.query.trend || 'hourly';
        let trendRows = [];

        if (trendType === 'hourly') {
            [trendRows] = await pool.execute(
                `SELECT HOUR(created_at) AS label_key,
                        CONCAT(LPAD(HOUR(created_at),2,'0'),':00') AS label,
                        COALESCE(SUM(final_amount),0) AS revenue,
                        COUNT(*) AS tx_count
                 FROM transactions
                 WHERE payment_status='paid' AND DATE(created_at)=CURDATE() AND branch_id=?
                 GROUP BY HOUR(created_at), CONCAT(LPAD(HOUR(created_at),2,'0'),':00')
                 ORDER BY HOUR(created_at) ASC`,
                [branch_id]
            );
        } else if (trendType === 'daily') {
            [trendRows] = await pool.execute(
                `SELECT DATE(created_at) AS label_key,
                        DATE_FORMAT(created_at,'%d %b') AS label,
                        COALESCE(SUM(final_amount),0) AS revenue,
                        COUNT(*) AS tx_count
                 FROM transactions
                 WHERE payment_status='paid' AND created_at >= DATE_SUB(CURDATE(),INTERVAL 29 DAY) AND branch_id=?
                 GROUP BY DATE(created_at), DATE_FORMAT(created_at,'%d %b')
                 ORDER BY DATE(created_at) ASC`,
                [branch_id]
            );
        } else if (trendType === 'weekly') {
            [trendRows] = await pool.execute(
                `SELECT YEARWEEK(created_at,1) AS label_key,
                        CONCAT('W',WEEK(created_at,1)) AS label,
                        COALESCE(SUM(final_amount),0) AS revenue,
                        COUNT(*) AS tx_count
                 FROM transactions
                 WHERE payment_status='paid' AND created_at >= DATE_SUB(CURDATE(),INTERVAL 12 WEEK) AND branch_id=?
                 GROUP BY YEARWEEK(created_at,1), WEEK(created_at,1), CONCAT('W',WEEK(created_at,1))
                 ORDER BY YEARWEEK(created_at,1) ASC`,
                [branch_id]
            );
        } else if (trendType === 'monthly') {
            [trendRows] = await pool.execute(
                `SELECT DATE_FORMAT(created_at,'%Y-%m') AS label_key,
                        DATE_FORMAT(created_at,'%b %Y') AS label,
                        COALESCE(SUM(final_amount),0) AS revenue,
                        COUNT(*) AS tx_count
                 FROM transactions
                 WHERE payment_status='paid' AND created_at >= DATE_SUB(CURDATE(),INTERVAL 12 MONTH) AND branch_id=?
                 GROUP BY DATE_FORMAT(created_at,'%Y-%m'), DATE_FORMAT(created_at,'%b %Y')
                 ORDER BY DATE_FORMAT(created_at,'%Y-%m') ASC`,
                [branch_id]
            );
        }

        res.json({
            branchName: branch.name,
            todayRevenue: parseFloat(today.revenue),
            todayTxCount: parseInt(today.tx_count),
            targetPendapatan: parseFloat(branch.target_pendapatan),
            cashTotal,
            digitalTotal,
            trend: {
                type: trendType,
                data: trendRows.map(r => ({
                    label_key: r.label_key,
                    label: r.label,
                    revenue: parseFloat(r.revenue),
                    tx_count: parseInt(r.tx_count),
                })),
            },
        });
    } catch (error) {
        console.error('Admin dashboard error:', error);
        res.status(500).json({ error: 'Gagal mengambil data dashboard admin' });
    }
});

module.exports = router;
