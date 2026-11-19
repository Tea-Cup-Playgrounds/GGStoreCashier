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

// ── GET /api/analytics/overview?days=7 ──────────────────────────────────────
// Everything the owner's home screen shows, in one request:
//   today       revenue and sales so far, against yesterday up to the same time
//   month       month to date, against last month up to the same day and time
//   period      the last `days` days including today (7, 30 or 90): totals, the same span just
//               before it, and one row per day (days without sales are 0)
//   branches    every active branch over the period, with its open shifts right now
//   categories  top categories by revenue over the period
//   products    top variants by quantity over the period (all branches together)
//   attention   things the owner may need to act on today
router.get('/overview', async (req, res) => {
    try {
        const days = [7, 30, 90].includes(Number(req.query.days)) ? Number(req.query.days) : 7;
        const totals = async (where, params = []) => {
            const [[row]] = await pool.execute(
                `SELECT ${NET_REVENUE} AS revenue, COUNT(*) AS transactions FROM sales s WHERE s.status <> 'voided' AND ${where}`,
                params
            );
            return { revenue: Number(row.revenue), transactions: Number(row.transactions) };
        };

        const [[range]] = await pool.execute(
            `SELECT DATE_FORMAT(CURDATE() - INTERVAL ? DAY, '%Y-%m-%d') AS from_date,
                    DATE_FORMAT(CURDATE(), '%Y-%m-%d') AS to_date,
                    DATE_FORMAT(CURDATE() - INTERVAL ? DAY, '%Y-%m-%d') AS prev_from,
                    DATE_FORMAT(NOW(), '%Y-%m-%dT%H:%i:%s') AS now`,
            [days - 1, days * 2 - 1]
        );
        const { from_date: from, to_date: to, prev_from: prevFrom } = range;

        const [today, yesterday, month, lastMonth, period, previous] = await Promise.all([
            totals('s.occurred_at >= CURDATE()'),
            totals('s.occurred_at >= CURDATE() - INTERVAL 1 DAY AND s.occurred_at < NOW() - INTERVAL 1 DAY'),
            totals("s.occurred_at >= DATE_FORMAT(CURDATE(), '%Y-%m-01')"),
            totals(
                "s.occurred_at >= DATE_FORMAT(CURDATE() - INTERVAL 1 MONTH, '%Y-%m-01') AND s.occurred_at < NOW() - INTERVAL 1 MONTH"
            ),
            totals('s.occurred_at >= ?', [from]),
            totals('s.occurred_at >= ? AND s.occurred_at < ?', [prevFrom, from]),
        ]);

        const [
            [dailyRows],
            [branchRows],
            [categoryRows],
            [productRows],
            [[shifts]],
            [[cash]],
            [[stock]],
            [[voided]],
            [[activeToday]],
        ] = await Promise.all([
            pool.execute(
                `SELECT DATE_FORMAT(s.occurred_at, '%Y-%m-%d') AS date, ${NET_REVENUE} AS revenue, COUNT(*) AS transactions
                 FROM sales s WHERE s.status <> 'voided' AND s.occurred_at >= ?
                 GROUP BY date ORDER BY date`,
                [from]
            ),
            pool.execute(
                `SELECT b.id, b.code, b.name,
                        COALESCE(p.revenue, 0) AS revenue, COALESCE(p.transactions, 0) AS transactions,
                        (SELECT COUNT(*) FROM cash_sessions cs WHERE cs.location_id = b.id AND cs.status = 'open') AS open_shifts
                 FROM locations b
                 LEFT JOIN (
                     SELECT s.location_id, ${NET_REVENUE} AS revenue, COUNT(*) AS transactions
                     FROM sales s WHERE s.status <> 'voided' AND s.occurred_at >= ?
                     GROUP BY s.location_id
                 ) p ON p.location_id = b.id
                 WHERE b.type = 'branch' AND b.deleted_at IS NULL
                 ORDER BY revenue DESC, b.name`,
                [from]
            ),
            pool.execute(
                `SELECT c.id, COALESCE(c.name, 'Tanpa kategori') AS name, ${NET_LINE_REVENUE} AS revenue, ${NET_QTY} AS qty
                 FROM sale_lines sl
                 JOIN sales s ON sl.sale_id = s.id
                 JOIN product_variants v ON sl.variant_id = v.id
                 JOIN products p ON v.product_id = p.id
                 LEFT JOIN categories c ON p.category_id = c.id
                 WHERE s.status <> 'voided' AND s.occurred_at >= ?
                 GROUP BY c.id, c.name
                 ORDER BY revenue DESC`,
                [from]
            ),
            pool.execute(
                `SELECT v.id, ${DISPLAY_NAME_SQL} AS name, ${NET_QTY} AS qty, ${NET_LINE_REVENUE} AS revenue
                 FROM sale_lines sl
                 JOIN sales s ON sl.sale_id = s.id
                 JOIN product_variants v ON sl.variant_id = v.id
                 JOIN products p ON v.product_id = p.id
                 WHERE s.status <> 'voided' AND s.occurred_at >= ?
                 GROUP BY v.id, name
                 HAVING qty > 0
                 ORDER BY qty DESC, revenue DESC
                 LIMIT 5`,
                [from]
            ),
            pool.execute(
                `SELECT COUNT(*) AS open, COALESCE(SUM(cs.opened_at < NOW() - INTERVAL 12 HOUR), 0) AS overdue
                 FROM cash_sessions cs WHERE cs.status = 'open'`
            ),
            pool.execute(
                `SELECT COUNT(*) AS count, COALESCE(SUM(ABS(cs.difference)), 0) AS total
                 FROM cash_sessions cs
                 WHERE cs.status = 'closed' AND cs.closed_at >= CURDATE() AND cs.difference IS NOT NULL AND cs.difference <> 0`
            ),
            pool.execute(
                `SELECT COALESCE(SUM(soh.qty <= 0), 0) AS out_of_stock,
                        COALESCE(SUM(soh.qty > 0 AND soh.qty <= COALESCE(sl.reorder_level, 5)), 0) AS low_stock
                 FROM stock_on_hand soh
                 JOIN locations l ON l.id = soh.location_id AND l.type = 'branch' AND l.deleted_at IS NULL
                 JOIN product_variants v ON v.id = soh.variant_id AND v.deleted_at IS NULL AND v.is_active = 1
                 JOIN products p ON p.id = v.product_id AND p.deleted_at IS NULL AND p.is_active = 1
                 LEFT JOIN stock_levels sl ON sl.location_id = soh.location_id AND sl.variant_id = soh.variant_id`
            ),
            pool.execute(
                "SELECT COUNT(*) AS count FROM sales s WHERE s.status = 'voided' AND s.occurred_at >= CURDATE()"
            ),
            pool.execute(
                "SELECT COUNT(DISTINCT s.location_id) AS count FROM sales s WHERE s.status <> 'voided' AND s.occurred_at >= CURDATE()"
            ),
        ]);

        // One row per day in the period, so days without sales show as 0 instead of vanishing.
        const byDate = new Map(dailyRows.map((r) => [r.date, r]));
        const daily = [];
        for (let d = new Date(`${from}T00:00:00Z`); d.toISOString().slice(0, 10) <= to; d.setUTCDate(d.getUTCDate() + 1)) {
            const date = d.toISOString().slice(0, 10);
            const row = byDate.get(date);
            daily.push({ date, revenue: row ? Number(row.revenue) : 0, transactions: row ? Number(row.transactions) : 0 });
        }

        res.json({
            generated_at: range.now,
            today: { ...today, previous: yesterday },
            month: { ...month, previous: lastMonth },
            period: { days, from, to, ...period, previous, daily },
            branches: branchRows.map((b) => ({
                id: b.id, code: b.code, name: b.name,
                revenue: Number(b.revenue), transactions: Number(b.transactions), open_shifts: Number(b.open_shifts),
            })),
            active_branches_today: Number(activeToday.count),
            categories: categoryRows.map((c) => ({ id: c.id, name: c.name, revenue: Number(c.revenue), qty: Number(c.qty) })),
            products: productRows.map((p) => ({ id: p.id, name: p.name, revenue: Number(p.revenue), qty: Number(p.qty) })),
            attention: {
                open_shifts: Number(shifts.open),
                overdue_shifts: Number(shifts.overdue),
                cash_differences_today: { count: Number(cash.count), total: Number(cash.total) },
                out_of_stock: Number(stock.out_of_stock),
                low_stock: Number(stock.low_stock),
                voided_today: Number(voided.count),
            },
        });
    } catch (err) {
        console.error('overview error:', err);
        res.status(500).json({ error: 'Gagal mengambil ringkasan bisnis' });
    }
});

module.exports = router;
