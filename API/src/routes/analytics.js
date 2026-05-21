const express = require('express');
const pool = require('../db');
const { authenticateToken, requireRole } = require('../middleware/auth');

const router = express.Router();
router.use(authenticateToken);
router.use(requireRole(['superadmin']));

// ── GET /api/analytics/revenue-trend?days=30 ─────────────────────────────────
// Daily revenue for all branches combined over the last N days
router.get('/revenue-trend', async (req, res) => {
    try {
        const days = Math.min(parseInt(req.query.days, 10) || 30, 90);
        const [rows] = await pool.execute(
            `SELECT DATE(created_at) AS date,
                    COALESCE(SUM(final_amount), 0) AS revenue,
                    COUNT(*) AS transactions
             FROM transactions
             WHERE payment_status = 'paid'
               AND created_at >= DATE_SUB(CURDATE(), INTERVAL ${days} DAY)
             GROUP BY DATE(created_at)
             ORDER BY date ASC`,
            []
        );
        res.json({ data: rows });
    } catch (err) {
        console.error('revenue-trend error:', err);
        res.status(500).json({ error: 'Gagal mengambil data tren pendapatan' });
    }
});

// ── GET /api/analytics/branch-revenue?date=YYYY-MM-DD ────────────────────────
// Revenue per branch for a given day (defaults to today)
router.get('/branch-revenue', async (req, res) => {
    try {
        const date = req.query.date || new Date().toISOString().slice(0, 10);
        const [rows] = await pool.execute(
            `SELECT b.id AS branch_id, b.name AS branch_name,
                    COALESCE(SUM(t.final_amount), 0) AS revenue,
                    COUNT(t.id) AS transactions
             FROM branches b
             LEFT JOIN transactions t
               ON t.branch_id = b.id
               AND DATE(t.created_at) = ?
               AND t.payment_status = 'paid'
             WHERE b.id != 0
             GROUP BY b.id, b.name
             ORDER BY revenue DESC`,
            [date]
        );
        res.json({ data: rows, date });
    } catch (err) {
        console.error('branch-revenue error:', err);
        res.status(500).json({ error: 'Gagal mengambil data pendapatan cabang' });
    }
});

// ── GET /api/analytics/category-sales?days=30 ────────────────────────────────
// Most sold categories by quantity
router.get('/category-sales', async (req, res) => {
    try {
        const days = Math.min(parseInt(req.query.days, 10) || 30, 90);
        const [rows] = await pool.execute(
            `SELECT c.id AS category_id,
                    COALESCE(c.name, 'Uncategorized') AS category_name,
                    SUM(ti.qty) AS total_qty,
                    SUM(ti.subtotal) AS total_revenue
             FROM transaction_items ti
             JOIN transactions t ON ti.transaction_id = t.id
             JOIN products p ON ti.product_id = p.id
             LEFT JOIN categories c ON p.category_id = c.id
             WHERE t.payment_status = 'paid'
               AND t.created_at >= DATE_SUB(CURDATE(), INTERVAL ${days} DAY)
             GROUP BY c.id, c.name
             ORDER BY total_qty DESC
             LIMIT 10`,
            []
        );
        res.json({ data: rows });
    } catch (err) {
        console.error('category-sales error:', err);
        res.status(500).json({ error: 'Gagal mengambil data penjualan kategori' });
    }
});

// ── GET /api/analytics/top-products?days=30&limit=10 ─────────────────────────
// Top selling products by quantity
router.get('/top-products', async (req, res) => {
    try {
        const days  = Math.min(parseInt(req.query.days,  10) || 30, 90);
        const limit = Math.min(parseInt(req.query.limit, 10) || 10, 20);
        const [rows] = await pool.execute(
            `SELECT p.id, p.name,
                    SUM(ti.qty) AS total_qty,
                    SUM(ti.subtotal) AS total_revenue,
                    b.name AS branch_name
             FROM transaction_items ti
             JOIN transactions t ON ti.transaction_id = t.id
             JOIN products p ON ti.product_id = p.id
             LEFT JOIN branches b ON p.branch_id = b.id
             WHERE t.payment_status = 'paid'
               AND t.created_at >= DATE_SUB(CURDATE(), INTERVAL ${days} DAY)
             GROUP BY p.id, p.name, b.name
             ORDER BY total_qty DESC
             LIMIT ${limit}`,
            []
        );
        res.json({ data: rows });
    } catch (err) {
        console.error('top-products error:', err);
        res.status(500).json({ error: 'Gagal mengambil data produk terlaris' });
    }
});

// ── GET /api/analytics/summary ────────────────────────────────────────────────
// High-level KPIs across all branches
router.get('/summary', async (req, res) => {
    try {
        const [[today]] = await pool.execute(
            `SELECT COALESCE(SUM(final_amount),0) AS revenue, COUNT(*) AS transactions
             FROM transactions WHERE payment_status='paid' AND DATE(created_at)=CURDATE()`
        );
        const [[month]] = await pool.execute(
            `SELECT COALESCE(SUM(final_amount),0) AS revenue, COUNT(*) AS transactions
             FROM transactions WHERE payment_status='paid'
               AND YEAR(created_at)=YEAR(CURDATE()) AND MONTH(created_at)=MONTH(CURDATE())`
        );
        const [[allTime]] = await pool.execute(
            `SELECT COALESCE(SUM(final_amount),0) AS revenue, COUNT(*) AS transactions
             FROM transactions WHERE payment_status='paid'`
        );
        const [[activeBranches]] = await pool.execute(
            `SELECT COUNT(DISTINCT branch_id) AS count FROM transactions
             WHERE payment_status='paid' AND DATE(created_at)=CURDATE()`
        );
        res.json({
            today: { revenue: parseFloat(today.revenue), transactions: parseInt(today.transactions) },
            month: { revenue: parseFloat(month.revenue), transactions: parseInt(month.transactions) },
            allTime: { revenue: parseFloat(allTime.revenue), transactions: parseInt(allTime.transactions) },
            activeBranchesToday: parseInt(activeBranches.count),
        });
    } catch (err) {
        console.error('summary error:', err);
        res.status(500).json({ error: 'Gagal mengambil data ringkasan' });
    }
});

module.exports = router;
