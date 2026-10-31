const express = require('express');
const pool = require('../db');
const { authenticateToken, requirePermission } = require('../middleware/auth');
const { logAudit } = require('../services/audit');
const posting = require('../services/posting');
const { AppError, withTransaction } = require('../utils/transaction');
const { ctxOf, requireLocation, parseMoney } = require('../utils/request');
const { uuidv7 } = require('../utils/uuid');

// Cashier shifts. Optional (a sale may have no session), one open session per user per location.
// Closing compares counted cash with expected cash:
//   expected = opening cash + cash received (net of change) - cash refunds, voided sales excluded.
const router = express.Router();

router.use(authenticateToken);

const round2 = (n) => Math.round(n * 100) / 100;

// Totals for a session: per payment method, plus the expected cash in the drawer.
const summarize = async (db, session) => {
    const [methods] = await db.execute(
        `SELECT pm.id, pm.name, pm.type, COALESCE(SUM(sp.amount), 0) AS amount, COUNT(DISTINCT s.id) AS sales
         FROM sales s
         JOIN sale_payments sp ON sp.sale_id = s.id
         JOIN payment_methods pm ON pm.id = sp.payment_method_id
         WHERE s.cash_session_id = ? AND s.status <> 'voided'
         GROUP BY pm.id, pm.name, pm.type ORDER BY pm.sort_order`,
        [session.id]
    );
    const [[sales]] = await db.execute(
        `SELECT COUNT(*) AS count, COALESCE(SUM(grand_total), 0) AS total, COALESCE(SUM(change_total), 0) AS change_total
         FROM sales WHERE cash_session_id = ? AND status <> 'voided'`,
        [session.id]
    );
    const [[refunds]] = await db.execute(
        `SELECT COALESCE(SUM(r.refund_total), 0) AS cash_refunds, COALESCE(SUM(r.refund_total), 0) AS total
         FROM sale_returns r JOIN payment_methods pm ON pm.id = r.refund_method_id
         WHERE r.cash_session_id = ? AND pm.type = 'cash'`,
        [session.id]
    );
    const cashReceived = methods.filter((m) => m.type === 'cash').reduce((s, m) => s + Number(m.amount), 0);
    const expected = round2(Number(session.opening_cash) + cashReceived - Number(sales.change_total) - Number(refunds.cash_refunds));
    return {
        sales_count: Number(sales.count),
        sales_total: Number(sales.total),
        change_total: Number(sales.change_total),
        cash_refunds: Number(refunds.cash_refunds),
        by_method: methods.map((m) => ({ ...m, amount: Number(m.amount), sales: Number(m.sales) })),
        expected_cash: expected,
    };
};

const loadSession = async (db, id) => {
    const [[session]] = await db.execute(
        `SELECT cs.*, l.code AS location_code, l.name AS location_name, ou.name AS opened_by_name, cu.name AS closed_by_name
         FROM cash_sessions cs
         JOIN locations l ON l.id = cs.location_id
         LEFT JOIN users ou ON ou.id = cs.opened_by
         LEFT JOIN users cu ON cu.id = cs.closed_by
         WHERE cs.id = ?`,
        [id]
    );
    if (!session) return null;
    return { ...session, summary: await summarize(db, session) };
};

const canSeeSession = (req, session) =>
    session.opened_by === req.user.id || req.access.can('cash_session.view_all', session.location_id);

// The caller's open session at a location, or null.
router.get('/current', requirePermission('sales.create'), requireLocation, async (req, res) => {
    try {
        const [[row]] = await pool.execute(
            "SELECT id FROM cash_sessions WHERE location_id = ? AND opened_by = ? AND status = 'open' ORDER BY opened_at DESC LIMIT 1",
            [req.locationId, req.user.id]
        );
        res.json({ session: row ? await loadSession(pool, row.id) : null });
    } catch (error) {
        console.error('Get current session error:', error);
        res.status(500).json({ error: 'Gagal mengambil data shift' });
    }
});

// GET /api/cash-sessions?location_id=  — own sessions, or all with cash_session.view_all.
router.get('/', requirePermission('sales.create'), requireLocation, async (req, res) => {
    try {
        const all = req.access.can('cash_session.view_all', req.locationId);
        const [sessions] = await pool.execute(
            `SELECT cs.id, cs.status, cs.opened_at, cs.closed_at, cs.opening_cash, cs.expected_cash, cs.counted_cash,
                    cs.difference, ou.name AS opened_by_name
             FROM cash_sessions cs LEFT JOIN users ou ON ou.id = cs.opened_by
             WHERE cs.location_id = ? ${all ? '' : 'AND cs.opened_by = ?'}
             ORDER BY cs.opened_at DESC LIMIT 100`,
            all ? [req.locationId] : [req.locationId, req.user.id]
        );
        res.json({ sessions });
    } catch (error) {
        console.error('Get sessions error:', error);
        res.status(500).json({ error: 'Gagal mengambil data shift' });
    }
});

router.get('/:id', async (req, res) => {
    try {
        const session = await loadSession(pool, req.params.id);
        if (!session) return res.status(404).json({ error: 'Shift tidak ditemukan' });
        if (!canSeeSession(req, session)) return res.status(403).json({ error: 'Akses tidak diizinkan' });
        res.json({ session });
    } catch (error) {
        console.error('Get session error:', error);
        res.status(500).json({ error: 'Gagal mengambil data shift' });
    }
});

// Body: { location_id, opening_cash }
router.post('/', requirePermission('cash_session.open'), requireLocation, async (req, res) => {
    const opening = req.body.opening_cash === undefined ? 0 : parseMoney(req.body.opening_cash);
    if (Number.isNaN(opening)) return res.status(400).json({ error: 'Modal awal tidak valid' });

    const result = await withTransaction(res, 'Gagal membuka shift', async (conn) => {
        const [open] = await conn.execute(
            "SELECT id FROM cash_sessions WHERE location_id = ? AND opened_by = ? AND status = 'open' FOR UPDATE",
            [req.locationId, req.user.id]
        );
        if (open.length > 0) throw new AppError('Anda masih memiliki shift yang terbuka di lokasi ini', 409);
        const id = uuidv7();
        await conn.execute(
            'INSERT INTO cash_sessions (id, location_id, device_id, opened_by, opened_at, opening_cash) VALUES (?, ?, ?, ?, NOW(3), ?)',
            [id, req.locationId, req.deviceId || null, req.user.id, opening]
        );
        await logAudit(conn, req, { action: 'open', entity: 'cash_session', entityId: id, locationId: req.locationId, after: { opening_cash: opening } });
        return loadSession(conn, id);
    });
    if (result) res.status(201).json({ message: 'Shift dibuka', session: result });
});

// Body: { counted_cash, note }. A difference is posted to the cash over/short account.
router.post('/:id/close', async (req, res) => {
    const counted = parseMoney(req.body.counted_cash);
    if (Number.isNaN(counted)) return res.status(400).json({ error: 'Jumlah kas dihitung wajib diisi' });

    const result = await withTransaction(res, 'Gagal menutup shift', async (conn) => {
        const [[session]] = await conn.execute('SELECT * FROM cash_sessions WHERE id = ? FOR UPDATE', [req.params.id]);
        if (!session) throw new AppError('Shift tidak ditemukan', 404);
        const own = session.opened_by === req.user.id;
        if (!(own && req.access.can('cash_session.close', session.location_id)) && !req.access.can('cash_session.view_all', session.location_id)) {
            throw new AppError('Akses tidak diizinkan', 403);
        }
        if (session.status !== 'open') throw new AppError('Shift ini sudah ditutup');

        const { expected_cash: expected } = await summarize(conn, session);
        const difference = round2(counted - expected);
        await conn.execute(
            `UPDATE cash_sessions SET status = 'closed', closed_by = ?, closed_at = NOW(3), expected_cash = ?, counted_cash = ?, difference = ?, note = ?
             WHERE id = ?`,
            [req.user.id, expected, counted, difference, req.body.note || null, session.id]
        );
        await posting.postCashSessionClose(conn, ctxOf(req), session.id);
        await logAudit(conn, req, { action: 'close', entity: 'cash_session', entityId: session.id, locationId: session.location_id, after: { expected, counted, difference } });
        return loadSession(conn, session.id);
    });
    if (result) {
        const diff = Number(result.difference);
        res.json({ message: diff === 0 ? 'Shift ditutup, kas sesuai' : `Shift ditutup, selisih kas ${diff > 0 ? '+' : ''}${diff}`, session: result });
    }
});

module.exports = router;
