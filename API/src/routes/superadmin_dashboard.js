const express = require('express');
const pool = require('../db');
const { authenticateToken, requireRole } = require('../middleware/auth');

const router = express.Router();
router.use(authenticateToken);
router.use(requireRole(['superadmin']));

// ── GET /api/superadmin-dashboard/low-freq ────────────────────────────────────
// Macro KPIs, leaderboard, trends, top items.
// Intended to be polled every 3 minutes or on pull-to-refresh.
router.get('/low-freq', async (req, res) => {
    try {
        // ── Sales KPIs ─────────────────────────────────────────────────────────
        const [[today]] = await pool.execute(`
            SELECT COALESCE(SUM(final_amount),0) AS revenue, COUNT(*) AS tx_count
            FROM transactions WHERE payment_status='paid' AND DATE(created_at)=CURDATE()
        `);
        const [[yesterday]] = await pool.execute(`
            SELECT COALESCE(SUM(final_amount),0) AS revenue, COUNT(*) AS tx_count
            FROM transactions WHERE payment_status='paid' AND DATE(created_at)=DATE_SUB(CURDATE(),INTERVAL 1 DAY)
        `);
        const [[lastWeekSameDay]] = await pool.execute(`
            SELECT COALESCE(SUM(final_amount),0) AS revenue, COUNT(*) AS tx_count
            FROM transactions WHERE payment_status='paid' AND DATE(created_at)=DATE_SUB(CURDATE(),INTERVAL 7 DAY)
        `);

        const todayRev = parseFloat(today.revenue);
        const yestRev  = parseFloat(yesterday.revenue);
        const lwRev    = parseFloat(lastWeekSameDay.revenue);

        const vsYesterday = yestRev === 0
            ? (todayRev > 0 ? 100 : 0)
            : parseFloat((((todayRev - yestRev) / yestRev) * 100).toFixed(1));
        const vsLastWeek  = lwRev === 0
            ? (todayRev > 0 ? 100 : 0)
            : parseFloat((((todayRev - lwRev)  / lwRev)  * 100).toFixed(1));

        const avgOrderValue = today.tx_count > 0
            ? parseFloat((todayRev / today.tx_count).toFixed(0))
            : 0;

        // ── Active / offline branches ──────────────────────────────────────────
        const [allBranches] = await pool.execute(`SELECT id FROM branches WHERE id != 0`);
        const [activeBranches] = await pool.execute(`
            SELECT COUNT(DISTINCT branch_id) AS cnt
            FROM transactions WHERE payment_status='paid' AND DATE(created_at)=CURDATE()
        `);
        const totalBranches  = allBranches.length;
        const activeCnt      = parseInt(activeBranches[0].cnt);
        const offlineCnt     = totalBranches - activeCnt;

        // ── Leaderboard: today vs yesterday per branch ──────────────────────────
        const [leaderboard] = await pool.execute(`
            SELECT
                b.id   AS branch_id,
                b.name AS branch_name,
                COALESCE(SUM(CASE WHEN DATE(t.created_at)=CURDATE() AND t.payment_status='paid' THEN t.final_amount END),0) AS today_revenue,
                COALESCE(SUM(CASE WHEN DATE(t.created_at)=DATE_SUB(CURDATE(),INTERVAL 1 DAY) AND t.payment_status='paid' THEN t.final_amount END),0) AS yesterday_revenue,
                COALESCE(COUNT(CASE WHEN DATE(t.created_at)=CURDATE() AND t.payment_status='paid' THEN 1 END),0) AS today_tx
            FROM branches b
            LEFT JOIN transactions t ON t.branch_id = b.id
            WHERE b.id != 0
            GROUP BY b.id, b.name
            ORDER BY today_revenue DESC
        `);

        // ── Sales trend (hourly for today, returned always; aggregated variants ─
        // Client toggles the display: hourly (today), daily (last 30d), weekly (last 12w), monthly (last 12m)
        const trendType = (req.query.trend || 'hourly');
        let trendRows = [];

        if (trendType === 'hourly') {
            [trendRows] = await pool.execute(`
                SELECT HOUR(created_at) AS label_key,
                       CONCAT(LPAD(HOUR(created_at),2,'0'),':00') AS label,
                       COALESCE(SUM(final_amount),0) AS revenue,
                       COUNT(*) AS tx_count
                FROM transactions
                WHERE payment_status='paid' AND DATE(created_at)=CURDATE()
                GROUP BY HOUR(created_at), CONCAT(LPAD(HOUR(created_at),2,'0'),':00')
                ORDER BY HOUR(created_at) ASC
            `);
        } else if (trendType === 'daily') {
            [trendRows] = await pool.execute(`
                SELECT DATE(created_at) AS label_key,
                       DATE_FORMAT(created_at,'%d %b') AS label,
                       COALESCE(SUM(final_amount),0) AS revenue,
                       COUNT(*) AS tx_count
                FROM transactions
                WHERE payment_status='paid' AND created_at >= DATE_SUB(CURDATE(),INTERVAL 29 DAY)
                GROUP BY DATE(created_at), DATE_FORMAT(created_at,'%d %b')
                ORDER BY DATE(created_at) ASC
            `);
        } else if (trendType === 'weekly') {
            [trendRows] = await pool.execute(`
                SELECT YEARWEEK(created_at,1) AS label_key,
                       CONCAT('W',WEEK(created_at,1)) AS label,
                       COALESCE(SUM(final_amount),0) AS revenue,
                       COUNT(*) AS tx_count
                FROM transactions
                WHERE payment_status='paid' AND created_at >= DATE_SUB(CURDATE(),INTERVAL 12 WEEK)
                GROUP BY YEARWEEK(created_at,1), WEEK(created_at,1), CONCAT('W',WEEK(created_at,1))
                ORDER BY YEARWEEK(created_at,1) ASC
            `);
        } else if (trendType === 'monthly') {
            [trendRows] = await pool.execute(`
                SELECT DATE_FORMAT(created_at,'%Y-%m') AS label_key,
                       DATE_FORMAT(created_at,'%b %Y') AS label,
                       COALESCE(SUM(final_amount),0) AS revenue,
                       COUNT(*) AS tx_count
                FROM transactions
                WHERE payment_status='paid' AND created_at >= DATE_SUB(CURDATE(),INTERVAL 12 MONTH)
                GROUP BY DATE_FORMAT(created_at,'%Y-%m'), DATE_FORMAT(created_at,'%b %Y')
                ORDER BY DATE_FORMAT(created_at,'%Y-%m') ASC
            `);
        }

        // ── Top 10 products & categories ───────────────────────────────────────
        const [topProducts] = await pool.execute(`
            SELECT p.id, p.name,
                   SUM(ti.qty) AS total_qty,
                   SUM(ti.subtotal) AS total_revenue
            FROM transaction_items ti
            JOIN transactions t ON ti.transaction_id = t.id
            JOIN products p ON ti.product_id = p.id
            WHERE t.payment_status='paid' AND DATE(t.created_at)=CURDATE()
            GROUP BY p.id, p.name
            ORDER BY total_qty DESC
            LIMIT 10
        `);

        const [topCategories] = await pool.execute(`
            SELECT COALESCE(c.id,0) AS category_id,
                   COALESCE(c.name,'Uncategorized') AS category_name,
                   SUM(ti.qty) AS total_qty,
                   SUM(ti.subtotal) AS total_revenue
            FROM transaction_items ti
            JOIN transactions t ON ti.transaction_id = t.id
            JOIN products p ON ti.product_id = p.id
            LEFT JOIN categories c ON p.category_id = c.id
            WHERE t.payment_status='paid' AND DATE(t.created_at)=CURDATE()
            GROUP BY c.id, c.name
            ORDER BY total_qty DESC
            LIMIT 10
        `);

        res.json({
            sales: {
                todayRevenue: todayRev,
                todayTxCount: parseInt(today.tx_count),
                avgOrderValue,
                vsYesterday,
                vsLastWeek,
            },
            branches: {
                total: totalBranches,
                active: activeCnt,
                offline: offlineCnt,
            },
            leaderboard: leaderboard.map(r => ({
                branch_id: r.branch_id,
                branch_name: r.branch_name,
                today_revenue: parseFloat(r.today_revenue),
                yesterday_revenue: parseFloat(r.yesterday_revenue),
                today_tx: parseInt(r.today_tx),
            })),
            trend: {
                type: trendType,
                data: trendRows.map(r => ({
                    label_key: r.label_key,
                    label: r.label,
                    revenue: parseFloat(r.revenue),
                    tx_count: parseInt(r.tx_count),
                })),
            },
            topProducts: topProducts.map(r => ({
                id: r.id,
                name: r.name,
                total_qty: parseInt(r.total_qty),
                total_revenue: parseFloat(r.total_revenue),
            })),
            topCategories: topCategories.map(r => ({
                category_id: r.category_id,
                category_name: r.category_name,
                total_qty: parseInt(r.total_qty),
                total_revenue: parseFloat(r.total_revenue),
            })),
        });
    } catch (err) {
        console.error('superadmin-dashboard/low-freq error:', err);
        res.status(500).json({ error: 'Gagal mengambil data dashboard' });
    }
});

// ── GET /api/superadmin-dashboard/high-freq ───────────────────────────────────
// Three live cards + last 20 transactions + stock counters.
// Called once on load; after that the client uses socket events.
router.get('/high-freq', async (req, res) => {
    try {
        // Three KPI cards (same as low-freq sales section but always fresh)
        const [[today]] = await pool.execute(`
            SELECT COALESCE(SUM(final_amount),0) AS revenue, COUNT(*) AS tx_count
            FROM transactions WHERE payment_status='paid' AND DATE(created_at)=CURDATE()
        `);
        const [[yesterday]] = await pool.execute(`
            SELECT COALESCE(SUM(final_amount),0) AS revenue, COUNT(*) AS tx_count
            FROM transactions WHERE payment_status='paid' AND DATE(created_at)=DATE_SUB(CURDATE(),INTERVAL 1 DAY)
        `);
        const [[lastWeekSameDay]] = await pool.execute(`
            SELECT COALESCE(SUM(final_amount),0) AS revenue, COUNT(*) AS tx_count
            FROM transactions WHERE payment_status='paid' AND DATE(created_at)=DATE_SUB(CURDATE(),INTERVAL 7 DAY)
        `);
        const [allBranches] = await pool.execute(`SELECT id FROM branches WHERE id != 0`);
        const [activeBranches] = await pool.execute(`
            SELECT COUNT(DISTINCT branch_id) AS cnt
            FROM transactions WHERE payment_status='paid' AND DATE(created_at)=CURDATE()
        `);

        const todayRev = parseFloat(today.revenue);
        const yestRev  = parseFloat(yesterday.revenue);
        const lwRev    = parseFloat(lastWeekSameDay.revenue);
        const avgOrderValue = today.tx_count > 0
            ? parseFloat((todayRev / today.tx_count).toFixed(0)) : 0;

        const vsYesterday = yestRev === 0
            ? (todayRev > 0 ? 100 : 0)
            : parseFloat((((todayRev - yestRev) / yestRev) * 100).toFixed(1));
        const vsLastWeek  = lwRev === 0
            ? (todayRev > 0 ? 100 : 0)
            : parseFloat((((todayRev - lwRev)  / lwRev)  * 100).toFixed(1));

        // Last 20 transactions
        const [recentTx] = await pool.execute(`
            SELECT t.id, t.final_amount, t.payment_status, t.created_at,
                   u.name AS user_name, b.name AS branch_name,
                   (SELECT method FROM payments WHERE transaction_id=t.id LIMIT 1) AS payment_method,
                   (SELECT COUNT(*) FROM transaction_items ti WHERE ti.transaction_id=t.id) AS item_count
            FROM transactions t
            LEFT JOIN users u ON t.user_id = u.id
            LEFT JOIN branches b ON t.branch_id = b.id
            ORDER BY t.created_at DESC
            LIMIT 20
        `);

        // Stock counters
        const [[lowStock]]    = await pool.execute(`SELECT COUNT(*) AS cnt FROM products WHERE stock > 0 AND stock <= 50`);
        const [[outOfStock]]  = await pool.execute(`SELECT COUNT(*) AS cnt FROM products WHERE stock = 0`);

        res.json({
            sales: {
                todayRevenue: todayRev,
                todayTxCount: parseInt(today.tx_count),
                avgOrderValue,
                vsYesterday,
                vsLastWeek,
            },
            branches: {
                total: allBranches.length,
                active: parseInt(activeBranches[0].cnt),
                offline: allBranches.length - parseInt(activeBranches[0].cnt),
            },
            recentTransactions: recentTx,
            stock: {
                lowCount: parseInt(lowStock.cnt),
                outCount: parseInt(outOfStock.cnt),
            },
        });
    } catch (err) {
        console.error('superadmin-dashboard/high-freq error:', err);
        res.status(500).json({ error: 'Gagal mengambil data live' });
    }
});

// ── GET /api/superadmin-dashboard/stock-detail ────────────────────────────────
// List of low-stock and out-of-stock products for modal display.
router.get('/stock-detail', async (req, res) => {
    try {
        const type = req.query.type || 'low'; // 'low' | 'out'
        const condition = type === 'out' ? 'stock = 0' : 'stock > 0 AND stock <= 50';

        const [products] = await pool.execute(`
            SELECT p.id, p.name, p.stock, p.sell_price,
                   c.name AS category_name, b.name AS branch_name
            FROM products p
            LEFT JOIN categories c ON p.category_id = c.id
            LEFT JOIN branches b ON p.branch_id = b.id
            WHERE ${condition}
            ORDER BY p.stock ASC, p.name ASC
            LIMIT 100
        `);

        res.json({ products });
    } catch (err) {
        console.error('stock-detail error:', err);
        res.status(500).json({ error: 'Gagal mengambil data stok' });
    }
});

module.exports = router;
