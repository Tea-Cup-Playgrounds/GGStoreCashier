const express = require('express');
const pool = require('../db');
const { authenticateToken, requirePermission } = require('../middleware/auth');
const { DISPLAY_NAME_SQL } = require('../services/catalog');

const router = express.Router();
router.use(authenticateToken);
router.use(requirePermission('reports.view_all'));

// Revenue is what customers kept (total minus refunds); voided sales are excluded. Quantities
// are net of returned items. Response keys predate the sales model and are kept for the app.
const NET_REVENUE = 'COALESCE(SUM(s.grand_total - s.refunded_total), 0)';
const NET_QTY = 'SUM(sl.qty - sl.returned_qty)';
const NET_LINE_REVENUE = 'SUM(sl.line_total * (sl.qty - sl.returned_qty) / sl.qty)';

// ── GET /api/analytics/revenue-trend?days=30 ─────────────────────────────────
// Daily revenue for all branches combined over the last N days
router.get('/revenue-trend', async (req, res) => {
    try {
        const days = Math.min(parseInt(req.query.days, 10) || 30, 90);
        const [rows] = await pool.execute(
            `SELECT DATE(s.occurred_at) AS date,
                    ${NET_REVENUE} AS revenue,
                    COUNT(*) AS transactions
             FROM sales s
             WHERE s.status <> 'voided'
               AND s.occurred_at >= DATE_SUB(CURDATE(), INTERVAL ${days} DAY)
             GROUP BY DATE(s.occurred_at)
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
                    ${NET_REVENUE} AS revenue,
                    COUNT(s.id) AS transactions
             FROM locations b
             LEFT JOIN sales s
               ON s.location_id = b.id
               AND DATE(s.occurred_at) = ?
               AND s.status <> 'voided'
             WHERE b.type = 'branch' AND b.deleted_at IS NULL
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
                    ${NET_QTY} AS total_qty,
                    ${NET_LINE_REVENUE} AS total_revenue
             FROM sale_lines sl
             JOIN sales s ON sl.sale_id = s.id
             JOIN product_variants v ON sl.variant_id = v.id
             JOIN products p ON v.product_id = p.id
             LEFT JOIN categories c ON p.category_id = c.id
             WHERE s.status <> 'voided'
               AND s.occurred_at >= DATE_SUB(CURDATE(), INTERVAL ${days} DAY)
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
            `SELECT v.id, ${DISPLAY_NAME_SQL} AS name,
                    ${NET_QTY} AS total_qty,
                    ${NET_LINE_REVENUE} AS total_revenue,
                    b.name AS branch_name
             FROM sale_lines sl
             JOIN sales s ON sl.sale_id = s.id
             JOIN product_variants v ON sl.variant_id = v.id
             JOIN products p ON v.product_id = p.id
             LEFT JOIN locations b ON s.location_id = b.id
             WHERE s.status <> 'voided'
               AND s.occurred_at >= DATE_SUB(CURDATE(), INTERVAL ${days} DAY)
             GROUP BY v.id, name, b.name
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
            `SELECT ${NET_REVENUE} AS revenue, COUNT(*) AS transactions
             FROM sales s WHERE s.status <> 'voided' AND DATE(s.occurred_at) = CURDATE()`
        );
        const [[month]] = await pool.execute(
            `SELECT ${NET_REVENUE} AS revenue, COUNT(*) AS transactions
             FROM sales s WHERE s.status <> 'voided'
               AND YEAR(s.occurred_at) = YEAR(CURDATE()) AND MONTH(s.occurred_at) = MONTH(CURDATE())`
        );
        const [[allTime]] = await pool.execute(
            `SELECT ${NET_REVENUE} AS revenue, COUNT(*) AS transactions
             FROM sales s WHERE s.status <> 'voided'`
        );
        const [[activeBranches]] = await pool.execute(
            `SELECT COUNT(DISTINCT s.location_id) AS count FROM sales s
             WHERE s.status <> 'voided' AND DATE(s.occurred_at) = CURDATE()`
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
