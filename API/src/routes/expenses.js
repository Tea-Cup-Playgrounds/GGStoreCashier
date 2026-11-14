const express = require('express');
const pool = require('../db');
const { authenticateToken, requirePermission } = require('../middleware/auth');
const { logAudit } = require('../services/audit');
const { postEntry, reverseSource } = require('../services/journal');
const { documentDate } = require('../services/documentDate');
const { nextDocumentNumber } = require('../services/documents');
const { AppError, withTransaction } = require('../utils/transaction');
const { ctxOf, parseDate, parseMoney } = require('../utils/request');
const { uuidv7 } = require('../utils/uuid');

// Expenses (Biaya): rent, salaries, electricity, internet, transport... Each one posts
// Dr <expense account> / Cr Kas or Bank at its location (journal source 'expense') and can be voided
// with a reversing journal. Categories are the expense accounts, except the ones the system books
// itself (HPP, Selisih Persediaan, Selisih Kas). New categories = new expense accounts (Bagan Akun).
// An expense without a location is company-wide (head office); only users with access to every
// location record or see those.
const router = express.Router();

router.use(authenticateToken);

const SYSTEM_KEYS = ['cogs', 'inventory_adjustment', 'cash_over_short'];

const loadCategories = async (db) => {
    const [rows] = await db.execute(
        `SELECT a.id, a.code, a.name FROM accounts a
         WHERE a.type = 'expense' AND a.is_postable = 1 AND a.is_active = 1
           AND a.id NOT IN (SELECT account_id FROM account_mappings WHERE \`key\` IN (?, ?, ?))
         ORDER BY a.code`,
        SYSTEM_KEYS
    );
    return rows;
};

const VIEW_PERMISSIONS = ['expenses.manage', 'accounting.view'];

// Locations whose expenses the user may see: null = every location (company-wide ones too).
const visibleLocations = (access) => {
    const scopes = VIEW_PERMISSIONS.map((p) => access.locationsFor(p));
    if (scopes.some((s) => s === null)) return null;
    return [...new Set(scopes.flat())];
};

const loadExpense = async (db, id) => {
    const [[row]] = await db.execute(
        `SELECT x.id, x.number, x.location_id, l.code AS location_code, l.name AS location_name,
                DATE_FORMAT(x.expense_date, '%Y-%m-%d') AS expense_date, x.account_id, a.code AS account_code, a.name AS account_name,
                x.amount, x.paid_from, x.payee, x.note, x.status, x.void_reason, x.voided_at, vu.name AS voided_by_name,
                x.created_at, cu.name AS created_by_name,
                (SELECT e.number FROM journal_entries e WHERE e.source_type = 'expense' AND e.source_id = x.id LIMIT 1) AS journal_number
         FROM expenses x
         JOIN accounts a ON a.id = x.account_id
         LEFT JOIN locations l ON l.id = x.location_id
         LEFT JOIN users cu ON cu.id = x.created_by
         LEFT JOIN users vu ON vu.id = x.voided_by
         WHERE x.id = ?`,
        [id]
    );
    return row ? { ...row, amount: Number(row.amount) } : null;
};

// Expense categories (expense accounts).
router.get('/categories', async (req, res) => {
    if (!VIEW_PERMISSIONS.some((p) => req.access.can(p))) return res.status(403).json({ error: 'Akses tidak diizinkan' });
    try {
        res.json({ categories: await loadCategories(pool) });
    } catch (error) {
        console.error('Get expense categories error:', error);
        res.status(500).json({ error: 'Gagal mengambil kategori biaya' });
    }
});

// GET /api/expenses?location_id=&from=&to=&account_id=&status=
router.get('/', async (req, res) => {
    try {
        const scope = visibleLocations(req.access);
        if (scope !== null && scope.length === 0) return res.status(403).json({ error: 'Akses tidak diizinkan' });
        const params = [];
        let where = 'WHERE 1 = 1';
        const locationId = req.query.location_id ? Number(req.query.location_id) : null;
        if (locationId) {
            if (scope !== null && !scope.includes(locationId)) return res.status(403).json({ error: 'Akses tidak diizinkan' });
            where += ' AND x.location_id = ?';
            params.push(locationId);
        } else if (scope !== null) {
            where += ` AND x.location_id IN (${scope.map(() => '?').join(', ')})`;
            params.push(...scope);
        }
        const from = parseDate(req.query.from);
        const to = parseDate(req.query.to);
        if (from === undefined || to === undefined) return res.status(400).json({ error: 'Format tanggal harus YYYY-MM-DD' });
        if (from) { where += ' AND x.expense_date >= ?'; params.push(from); }
        if (to) { where += ' AND x.expense_date <= ?'; params.push(to); }
        if (req.query.account_id) { where += ' AND x.account_id = ?'; params.push(Number(req.query.account_id)); }
        if (['posted', 'void'].includes(req.query.status)) { where += ' AND x.status = ?'; params.push(req.query.status); }

        const [rows] = await pool.execute(
            `SELECT x.id, x.number, x.location_id, l.code AS location_code, DATE_FORMAT(x.expense_date, '%Y-%m-%d') AS expense_date,
                    x.account_id, a.code AS account_code, a.name AS account_name, x.amount, x.paid_from, x.payee, x.note, x.status,
                    cu.name AS created_by_name
             FROM expenses x
             JOIN accounts a ON a.id = x.account_id
             LEFT JOIN locations l ON l.id = x.location_id
             LEFT JOIN users cu ON cu.id = x.created_by
             ${where}
             ORDER BY x.expense_date DESC, x.created_at DESC
             LIMIT 1000`,
            params
        );
        const expenses = rows.map((r) => ({ ...r, amount: Number(r.amount) }));
        const posted = expenses.filter((x) => x.status === 'posted');
        const byCategory = {};
        for (const x of posted) {
            const key = `${x.account_code} ${x.account_name}`;
            byCategory[key] = Math.round(((byCategory[key] || 0) + x.amount) * 100) / 100;
        }
        res.json({
            expenses,
            total: Math.round(posted.reduce((s, x) => s + x.amount, 0) * 100) / 100,
            by_category: Object.entries(byCategory).map(([category, amount]) => ({ category, amount })),
        });
    } catch (error) {
        console.error('Get expenses error:', error);
        res.status(500).json({ error: 'Gagal mengambil data biaya' });
    }
});

router.get('/:id', async (req, res) => {
    try {
        const expense = await loadExpense(pool, req.params.id);
        if (!expense) return res.status(404).json({ error: 'Biaya tidak ditemukan' });
        const scope = visibleLocations(req.access);
        if (scope !== null && !scope.includes(expense.location_id)) return res.status(403).json({ error: 'Akses tidak diizinkan' });
        res.json({ expense });
    } catch (error) {
        console.error('Get expense error:', error);
        res.status(500).json({ error: 'Gagal mengambil data biaya' });
    }
});

// Body: { location_id?, date, account_id | account_code, amount, paid_from: 'cash' | 'bank', payee?, note? }
router.post('/', requirePermission('expenses.manage', { location: (req) => req.body.location_id }), async (req, res) => {
    if (!req.locationId && req.access.locationsFor('expenses.manage') !== null) {
        return res.status(403).json({ error: 'Biaya kantor pusat (tanpa lokasi) hanya untuk pengguna dengan akses semua lokasi' });
    }
    const amount = parseMoney(req.body.amount);
    if (Number.isNaN(amount) || amount <= 0) return res.status(400).json({ error: 'Jumlah biaya harus lebih dari 0' });
    if (!['cash', 'bank'].includes(req.body.paid_from)) return res.status(400).json({ error: 'Dibayar dari harus cash atau bank' });
    const payee = req.body.payee ? String(req.body.payee).trim().slice(0, 150) : null;
    const note = req.body.note ? String(req.body.note).trim() : null;

    const result = await withTransaction(res, 'Gagal mencatat biaya', async (conn) => {
        const categories = await loadCategories(conn);
        const account = categories.find((c) => (req.body.account_code ? c.code === String(req.body.account_code) : c.id === Number(req.body.account_id)));
        if (!account) throw new AppError('Kategori biaya tidak ditemukan');
        const doc = await documentDate(conn, req.body.date, { label: 'Tanggal biaya' });
        const id = uuidv7();
        const number = await nextDocumentNumber(conn, 'EXP', req.locationId || null, doc.date);
        await conn.execute(
            `INSERT INTO expenses (id, number, location_id, expense_date, account_id, amount, paid_from, payee, note, created_by)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [id, number, req.locationId || null, doc.date, account.id, amount, req.body.paid_from, payee, note, req.user.id]
        );
        await postEntry(conn, ctxOf(req), {
            date: doc.date,
            locationId: req.locationId || null,
            sourceType: 'expense',
            sourceId: id,
            memo: `Biaya ${number}: ${account.name}${payee ? ` - ${payee}` : ''}`,
            lines: [
                { account: account.id, debit: amount, memo: note },
                { account: req.body.paid_from, credit: amount },
            ],
            strict: true,
        });
        await logAudit(conn, req, { action: 'create', entity: 'expense', entityId: id, locationId: req.locationId || null, after: { number, account: account.code, amount } });
        return loadExpense(conn, id);
    });
    if (result) res.status(201).json({ message: `Biaya ${result.number} dicatat`, expense: result });
});

const expenseLocation = async (req) => {
    const [[row]] = await pool.execute('SELECT location_id FROM expenses WHERE id = ?', [req.params.id]);
    return row ? row.location_id : -1;
};

// Body: { reason }. Posts the reversing journal; the expense stays listed as void.
router.post('/:id/void', requirePermission('expenses.manage', { location: expenseLocation }), async (req, res) => {
    const reason = String(req.body.reason || '').trim();
    if (!reason) return res.status(400).json({ error: 'Alasan pembatalan wajib diisi' });
    const result = await withTransaction(res, 'Gagal membatalkan biaya', async (conn) => {
        const [[expense]] = await conn.execute('SELECT * FROM expenses WHERE id = ? FOR UPDATE', [req.params.id]);
        if (!expense) throw new AppError('Biaya tidak ditemukan', 404);
        if (!expense.location_id && req.access.locationsFor('expenses.manage') !== null) throw new AppError('Akses tidak diizinkan', 403);
        if (expense.status !== 'posted') throw new AppError('Biaya ini sudah dibatalkan');
        await reverseSource(conn, ctxOf(req), {
            sourceType: 'expense', sourceId: expense.id, reversalSourceType: 'expense_void', memo: `Pembatalan ${expense.number}: ${reason}`,
        });
        await conn.execute("UPDATE expenses SET status = 'void', void_reason = ?, voided_by = ?, voided_at = NOW(3) WHERE id = ?", [reason, req.user.id, expense.id]);
        await logAudit(conn, req, { action: 'void', entity: 'expense', entityId: expense.id, locationId: expense.location_id, after: { reason } });
        return loadExpense(conn, expense.id);
    });
    if (result) res.json({ message: 'Biaya dibatalkan', expense: result });
});

module.exports = router;
