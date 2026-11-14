const express = require('express');
const pool = require('../db');
const { authenticateToken, requirePermission } = require('../middleware/auth');
const { logAudit } = require('../services/audit');
const { postEntry, resolveAccount } = require('../services/journal');
const { documentDate } = require('../services/documentDate');
const { AppError, withTransaction } = require('../utils/transaction');
const { ctxOf, parseDate, parseMoney } = require('../utils/request');
const { uuidv7 } = require('../utils/uuid');

// Pulsa deposit (1-1600 Deposit Pulsa): money paid in advance to the pulsa / digital provider.
// Top-ups add to it (Dr deposit, Cr cash or bank); every pulsa sale uses it at the item's
// cost_price (Dr HPP, Cr deposit, see posting.postSale). A top-up can be voided as a journal
// (Akuntansi → Jurnal). A top-up without location is company-wide (users with every location).
const router = express.Router();

router.use(authenticateToken);

const VIEW_PERMISSIONS = ['expenses.manage', 'accounting.view'];
const round2 = (n) => Math.round(n * 100) / 100;

// Lines on the deposit account the user may see, as SQL + params.
const scope = (req) => {
    const scopes = VIEW_PERMISSIONS.map((p) => req.access.locationsFor(p));
    const all = scopes.some((s) => s === null);
    const allowed = all ? null : [...new Set(scopes.flat())];
    const requested = req.query.location_id ? Number(req.query.location_id) : null;
    if (requested) {
        if (allowed !== null && !allowed.includes(requested)) throw new AppError('Akses tidak diizinkan', 403);
        return { sql: ' AND jl.location_id = ?', params: [requested] };
    }
    if (allowed === null) return { sql: '', params: [] };
    if (allowed.length === 0) throw new AppError('Akses tidak diizinkan', 403);
    return { sql: ` AND jl.location_id IN (${allowed.map(() => '?').join(', ')})`, params: allowed };
};

// GET /api/pulsa-deposit?location_id=&from=&to=
// { balance (now), top_ups in the range, usage per month in the range }
router.get('/', async (req, res) => {
    try {
        const { sql, params } = scope(req);
        const accountId = await resolveAccount(pool, 'pulsa_deposit', req.query.location_id ? Number(req.query.location_id) : null);
        const from = parseDate(req.query.from);
        const to = parseDate(req.query.to);
        if (from === undefined || to === undefined) return res.status(400).json({ error: 'Format tanggal harus YYYY-MM-DD' });
        const range = `${from ? ' AND e.entry_date >= ?' : ''}${to ? ' AND e.entry_date <= ?' : ''}`;
        const rangeParams = [from, to].filter(Boolean);

        const [[total]] = await pool.execute(
            `SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS balance
             FROM journal_lines jl JOIN journal_entries e ON e.id = jl.entry_id
             WHERE jl.account_id = ? AND e.status IN ('posted', 'void')${sql}`,
            [accountId, ...params]
        );
        const [topUps] = await pool.execute(
            `SELECT e.id AS entry_id, e.number, DATE_FORMAT(e.entry_date, '%Y-%m-%d') AS date, e.memo, e.status, l.code AS location_code,
                    jl.debit AS amount
             FROM journal_lines jl JOIN journal_entries e ON e.id = jl.entry_id LEFT JOIN locations l ON l.id = jl.location_id
             WHERE jl.account_id = ? AND e.source_type = 'pulsa_deposit' AND e.reverses_entry_id IS NULL AND jl.debit > 0${sql}${range}
             ORDER BY e.entry_date DESC, e.created_at DESC LIMIT 500`,
            [accountId, ...params, ...rangeParams]
        );
        const [usage] = await pool.execute(
            `SELECT DATE_FORMAT(e.entry_date, '%Y-%m') AS month, SUM(jl.credit - jl.debit) AS used, COUNT(DISTINCT e.id) AS sales
             FROM journal_lines jl JOIN journal_entries e ON e.id = jl.entry_id
             WHERE jl.account_id = ? AND e.source_type IN ('sale', 'sale_void', 'sale_return')${sql}${range}
             GROUP BY month ORDER BY month DESC`,
            [accountId, ...params, ...rangeParams]
        );
        res.json({
            balance: round2(Number(total.balance)),
            top_ups: topUps.map((t) => ({ ...t, amount: Number(t.amount) })),
            usage: usage.map((u) => ({ month: u.month, used: round2(Number(u.used)), sales: Number(u.sales) })),
        });
    } catch (error) {
        if (error instanceof AppError) return res.status(error.status).json({ error: error.message });
        console.error('Get pulsa deposit error:', error);
        res.status(500).json({ error: 'Gagal mengambil data deposit pulsa' });
    }
});

// Body: { location_id?, date, amount, paid_from: 'cash' | 'bank', note? }
router.post('/top-ups', requirePermission('expenses.manage', { location: (req) => req.body.location_id }), async (req, res) => {
    if (!req.locationId && req.access.locationsFor('expenses.manage') !== null) {
        return res.status(403).json({ error: 'Top up tanpa lokasi hanya untuk pengguna dengan akses semua lokasi' });
    }
    const amount = parseMoney(req.body.amount);
    if (Number.isNaN(amount) || amount <= 0) return res.status(400).json({ error: 'Jumlah top up harus lebih dari 0' });
    if (!['cash', 'bank'].includes(req.body.paid_from)) return res.status(400).json({ error: 'Dibayar dari harus cash atau bank' });
    const note = req.body.note ? String(req.body.note).trim().slice(0, 200) : '';

    const result = await withTransaction(res, 'Gagal mencatat top up deposit', async (conn) => {
        const doc = await documentDate(conn, req.body.date, { label: 'Tanggal top up' });
        const id = uuidv7();
        const entryId = await postEntry(conn, ctxOf(req), {
            date: doc.date,
            locationId: req.locationId || null,
            sourceType: 'pulsa_deposit',
            sourceId: id,
            memo: `Top up deposit pulsa${note ? `: ${note}` : ''}`,
            lines: [
                { account: 'pulsa_deposit', debit: amount },
                { account: req.body.paid_from, credit: amount },
            ],
            strict: true,
        });
        const [[entry]] = await conn.execute("SELECT id, number, DATE_FORMAT(entry_date, '%Y-%m-%d') AS date FROM journal_entries WHERE id = ?", [entryId]);
        await logAudit(conn, req, { action: 'top_up', entity: 'pulsa_deposit', entityId: entryId, locationId: req.locationId || null, after: { amount, paid_from: req.body.paid_from } });
        return entry;
    });
    if (result) res.status(201).json({ message: `Top up deposit ${result.number} dicatat`, entry: result });
});

module.exports = router;
