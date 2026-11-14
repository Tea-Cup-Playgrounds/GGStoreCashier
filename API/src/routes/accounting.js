const express = require('express');
const pool = require('../db');
const { authenticateToken, requirePermission } = require('../middleware/auth');
const { logAudit } = require('../services/audit');
const { postEntry, reverseSource, resolveAccount, dateOnly, toCents, fromCents } = require('../services/journal');
const { documentDate } = require('../services/documentDate');
const { AppError, withTransaction } = require('../utils/transaction');
const { ctxOf, parseDate, parseMoney } = require('../utils/request');
const { uuidv7 } = require('../utils/uuid');

// Chart of accounts, journals, trial balance / profit & loss, periods and account mappings.
// Non-rent costs such as rent, building tax (PBB) or salaries are recorded as manual journals
// (e.g. Dr 6-1000 Beban Sewa, Cr 1-1100 Kas) until the expenses module arrives.
const router = express.Router();

router.use(authenticateToken);

const TYPES = ['asset', 'liability', 'equity', 'income', 'expense'];
// Normal balance side: assets and expenses grow with debits, the rest with credits.
const DEBIT_NORMAL = new Set(['asset', 'expense']);

// Location filter for accounting reads. Users with accounting.view everywhere see company-wide
// entries (location NULL) too; others only their locations.
const scopeClause = (req, column, params) => {
    const scope = req.access.locationsFor('accounting.view');
    const requested = req.query.location_id ? Number(req.query.location_id) : null;
    if (requested) {
        if (scope !== null && !scope.includes(requested)) throw new AppError('Akses tidak diizinkan', 403);
        params.push(requested);
        return ` AND ${column} = ?`;
    }
    if (scope === null) return '';
    if (scope.length === 0) throw new AppError('Akses tidak diizinkan', 403);
    params.push(...scope);
    return ` AND ${column} IN (${scope.map(() => '?').join(', ')})`;
};

const handle = (fallback, fn) => async (req, res) => {
    try {
        await fn(req, res);
    } catch (error) {
        if (error instanceof AppError) return res.status(error.status).json({ error: error.message });
        console.error(`${fallback}:`, error);
        res.status(500).json({ error: fallback });
    }
};

// ── accounts ─────────────────────────────────────────────────────────────────

router.get('/accounts', requirePermission('accounting.view'), handle('Gagal mengambil daftar akun', async (req, res) => {
    const [accounts] = await pool.execute(
        `SELECT a.id, a.code, a.name, a.type, a.parent_id, p.code AS parent_code, a.is_postable, a.is_system, a.is_active
         FROM accounts a LEFT JOIN accounts p ON p.id = a.parent_id ORDER BY a.code`
    );
    res.json({ accounts: accounts.map((a) => ({ ...a, is_postable: !!a.is_postable, is_system: !!a.is_system, is_active: !!a.is_active })) });
}));

// Body: { code, name, type, parent_code? }. New accounts are postable; e.g. "6-1200 Beban Keamanan".
router.post('/accounts', requirePermission('accounting.post_manual'), async (req, res) => {
    const result = await withTransaction(res, 'Gagal membuat akun', async (conn) => {
        const code = String(req.body.code || '').trim();
        const name = String(req.body.name || '').trim();
        if (!/^\d-\d{4}$/.test(code)) throw new AppError('Kode akun harus berformat 9-9999, mis. 6-1200');
        if (!name || name.length > 100) throw new AppError('Nama akun wajib diisi (maks. 100 karakter)');
        let parent = null;
        if (req.body.parent_code) {
            [[parent]] = await conn.execute('SELECT id, type FROM accounts WHERE code = ?', [req.body.parent_code]);
            if (!parent) throw new AppError('Akun induk tidak ditemukan');
        }
        const type = req.body.type || parent?.type;
        if (!TYPES.includes(type)) throw new AppError('Tipe akun tidak valid');
        if (parent && parent.type !== type) throw new AppError('Tipe akun harus sama dengan akun induk');
        try {
            const [r] = await conn.execute('INSERT INTO accounts (code, name, type, parent_id) VALUES (?, ?, ?, ?)', [code, name, type, parent?.id || null]);
            await logAudit(conn, req, { action: 'create', entity: 'account', entityId: r.insertId, after: { code, name, type } });
            return { id: r.insertId, code, name, type };
        } catch (error) {
            if (error.code === 'ER_DUP_ENTRY') throw new AppError('Kode akun sudah digunakan');
            throw error;
        }
    });
    if (result) res.status(201).json({ message: 'Akun dibuat', account: result });
});

// Body: { name?, is_active? }. Codes and types are fixed once created.
router.put('/accounts/:id', requirePermission('accounting.post_manual'), async (req, res) => {
    const result = await withTransaction(res, 'Gagal memperbarui akun', async (conn) => {
        const [[before]] = await conn.execute('SELECT * FROM accounts WHERE id = ?', [req.params.id]);
        if (!before) throw new AppError('Akun tidak ditemukan', 404);
        const name = req.body.name !== undefined ? String(req.body.name).trim() : before.name;
        if (!name || name.length > 100) throw new AppError('Nama akun wajib diisi (maks. 100 karakter)');
        const active = req.body.is_active === undefined ? before.is_active : (req.body.is_active ? 1 : 0);
        if (!active && before.is_active) {
            const [[used]] = await conn.execute('SELECT COUNT(*) AS n FROM account_mappings WHERE account_id = ?', [before.id]);
            if (Number(used.n) > 0) throw new AppError('Akun dipakai pemetaan otomatis; ubah pemetaannya dulu');
        }
        await conn.execute('UPDATE accounts SET name = ?, is_active = ? WHERE id = ?', [name, active, before.id]);
        await logAudit(conn, req, { action: 'update', entity: 'account', entityId: before.id, before, after: { name, is_active: active } });
        return true;
    });
    if (result) res.json({ message: 'Akun diperbarui' });
});

// ── journals ─────────────────────────────────────────────────────────────────

// GET /api/accounting/journals?from=&to=&location_id=&source_type=&account_id=
router.get('/journals', requirePermission('accounting.view'), handle('Gagal mengambil jurnal', async (req, res) => {
    const params = [];
    let query = `
        SELECT e.id, e.number, DATE_FORMAT(e.entry_date, '%Y-%m-%d') AS entry_date, e.location_id, l.code AS location_code,
               e.source_type, e.source_id, e.memo, e.status, e.reverses_entry_id, u.name AS created_by_name, e.created_at,
               (SELECT SUM(debit) FROM journal_lines jl WHERE jl.entry_id = e.id) AS amount
        FROM journal_entries e
        LEFT JOIN locations l ON l.id = e.location_id
        LEFT JOIN users u ON u.id = e.created_by
        WHERE 1 = 1`;
    query += scopeClause(req, 'e.location_id', params);
    const from = parseDate(req.query.from);
    const to = parseDate(req.query.to);
    if (from) { query += ' AND e.entry_date >= ?'; params.push(from); }
    if (to) { query += ' AND e.entry_date <= ?'; params.push(to); }
    if (req.query.source_type) { query += ' AND e.source_type = ?'; params.push(String(req.query.source_type)); }
    if (req.query.account_id) { query += ' AND EXISTS (SELECT 1 FROM journal_lines x WHERE x.entry_id = e.id AND x.account_id = ?)'; params.push(Number(req.query.account_id)); }
    query += ' ORDER BY e.entry_date DESC, e.created_at DESC LIMIT 300';
    const [entries] = await pool.execute(query, params);
    res.json({ journals: entries.map((e) => ({ ...e, amount: Number(e.amount) })) });
}));

const loadJournal = async (db, id) => {
    const [[entry]] = await db.execute(
        `SELECT e.*, DATE_FORMAT(e.entry_date, '%Y-%m-%d') AS entry_date, l.code AS location_code, u.name AS created_by_name
         FROM journal_entries e LEFT JOIN locations l ON l.id = e.location_id LEFT JOIN users u ON u.id = e.created_by
         WHERE e.id = ?`,
        [id]
    );
    if (!entry) return null;
    const [lines] = await db.execute(
        `SELECT jl.id, jl.account_id, a.code AS account_code, a.name AS account_name, jl.location_id, jl.debit, jl.credit, jl.memo
         FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id WHERE jl.entry_id = ? ORDER BY jl.credit > 0, a.code`,
        [id]
    );
    return { ...entry, lines };
};

router.get('/journals/:id', requirePermission('accounting.view'), handle('Gagal mengambil jurnal', async (req, res) => {
    const journal = await loadJournal(pool, req.params.id);
    if (!journal) return res.status(404).json({ error: 'Jurnal tidak ditemukan' });
    if (journal.location_id ? !req.access.can('accounting.view', journal.location_id) : req.access.locationsFor('accounting.view') !== null) {
        return res.status(403).json({ error: 'Akses tidak diizinkan' });
    }
    res.json({ journal });
}));

// Body: { date, location_id?, memo, lines: [{ account_code | account_id, debit, credit, memo }] }
router.post('/journals', requirePermission('accounting.post_manual', { location: (req) => req.body.location_id }), async (req, res) => {
    const date = parseDate(req.body.date) ?? dateOnly();
    if (date === undefined) return res.status(400).json({ error: 'Format tanggal harus YYYY-MM-DD' });
    if (!req.locationId && req.access.locationsFor('accounting.post_manual') !== null) {
        return res.status(403).json({ error: 'Jurnal tanpa lokasi hanya untuk pengguna dengan akses semua lokasi' });
    }
    if (!req.body.memo || !String(req.body.memo).trim()) return res.status(400).json({ error: 'Keterangan jurnal wajib diisi' });
    if (!Array.isArray(req.body.lines) || req.body.lines.length < 2) return res.status(400).json({ error: 'Minimal dua baris jurnal' });

    const result = await withTransaction(res, 'Gagal menyimpan jurnal', async (conn) => {
        const lines = [];
        for (const l of req.body.lines) {
            let accountId = Number(l.account_id);
            if (l.account_code) {
                const [[a]] = await conn.execute('SELECT id FROM accounts WHERE code = ?', [String(l.account_code)]);
                if (!a) throw new AppError(`Akun ${l.account_code} tidak ditemukan`);
                accountId = a.id;
            }
            const debit = l.debit ? parseMoney(l.debit) : 0;
            const credit = l.credit ? parseMoney(l.credit) : 0;
            if (Number.isNaN(debit) || Number.isNaN(credit) || (debit > 0 && credit > 0)) throw new AppError('Setiap baris berisi debit atau kredit saja');
            lines.push({ account: accountId, debit, credit, memo: l.memo });
        }
        const id = uuidv7();
        const entryId = await postEntry(conn, ctxOf(req), {
            date, locationId: req.locationId || null, sourceType: 'manual', sourceId: id, memo: String(req.body.memo).trim(), lines, strict: true,
        });
        if (!entryId) throw new AppError('Nilai jurnal tidak boleh nol');
        await logAudit(conn, req, { action: 'create', entity: 'journal', entityId: entryId, locationId: req.locationId || null, after: req.body });
        return loadJournal(conn, entryId);
    });
    if (result) res.status(201).json({ message: `Jurnal ${result.number} disimpan`, journal: result });
});

// ── opening balances ─────────────────────────────────────────────────────────

// Balance-sheet amounts the business had when it started using the system: cash, bank,
// receivables, supplier debt, loans, capital. The difference goes to Ekuitas Saldo Awal (mapping
// opening_balance). Stock is not entered here but as opening stock (POST /api/stock/adjust or
// /api/stock/units with opening: true), so quantities and their value stay together.
// Body: { date, location_id?, memo?, lines: [{ account_code | account_id, debit?, credit? }] }
router.post('/opening-balances', requirePermission('accounting.post_manual', { location: (req) => req.body.location_id }), async (req, res) => {
    if (!req.locationId && req.access.locationsFor('accounting.post_manual') !== null) {
        return res.status(403).json({ error: 'Saldo awal tanpa lokasi hanya untuk pengguna dengan akses semua lokasi' });
    }
    if (!Array.isArray(req.body.lines) || req.body.lines.length === 0) return res.status(400).json({ error: 'Isi minimal satu saldo akun' });

    const result = await withTransaction(res, 'Gagal menyimpan saldo awal', async (conn) => {
        const doc = await documentDate(conn, req.body.date, { label: 'Tanggal saldo awal' });
        const inventoryId = await resolveAccount(conn, 'inventory', req.locationId);
        const openingId = await resolveAccount(conn, 'opening_balance', req.locationId);
        const interLocationId = await resolveAccount(conn, 'inter_location', req.locationId);
        const lines = [];
        let netCents = 0;
        for (const l of req.body.lines) {
            const [[account]] = l.account_code
                ? await conn.execute('SELECT id, code, type, is_postable, is_active FROM accounts WHERE code = ?', [String(l.account_code)])
                : await conn.execute('SELECT id, code, type, is_postable, is_active FROM accounts WHERE id = ?', [Number(l.account_id)]);
            if (!account) throw new AppError(`Akun ${l.account_code || l.account_id} tidak ditemukan`);
            if (!['asset', 'liability', 'equity'].includes(account.type)) throw new AppError(`Akun ${account.code} bukan akun neraca (aset, kewajiban, ekuitas)`);
            if (account.id === inventoryId) {
                throw new AppError('Persediaan diisi lewat stok awal (Stok → Sesuaikan, pilih "Stok awal") agar jumlah barang dan nilainya sama');
            }
            if (account.id === openingId) throw new AppError(`Akun ${account.code} dihitung otomatis dari selisih saldo`);
            if (account.id === interLocationId) throw new AppError(`Akun ${account.code} hanya diisi oleh transfer antar lokasi`);
            const debit = l.debit ? parseMoney(l.debit) : 0;
            const credit = l.credit ? parseMoney(l.credit) : 0;
            if (Number.isNaN(debit) || Number.isNaN(credit) || (debit > 0 && credit > 0)) throw new AppError('Setiap baris berisi debit atau kredit saja');
            if (debit === 0 && credit === 0) continue;
            netCents += toCents(debit) - toCents(credit);
            lines.push({ account: account.id, debit, credit, memo: l.memo });
        }
        if (lines.length === 0) throw new AppError('Isi minimal satu saldo akun');
        if (netCents !== 0) {
            lines.push({
                account: openingId, debit: netCents < 0 ? fromCents(-netCents) : 0, credit: netCents > 0 ? fromCents(netCents) : 0,
                memo: 'Selisih ke Ekuitas Saldo Awal',
            });
        }
        const id = uuidv7();
        const entryId = await postEntry(conn, ctxOf(req), {
            date: doc.date, locationId: req.locationId || null, sourceType: 'opening_balance', sourceId: id,
            memo: String(req.body.memo || '').trim() || 'Saldo awal', lines, strict: true,
        });
        await logAudit(conn, req, { action: 'create', entity: 'opening_balance', entityId: entryId, locationId: req.locationId || null, after: req.body });
        return loadJournal(conn, entryId);
    });
    if (result) res.status(201).json({ message: `Saldo awal ${result.number} disimpan`, journal: result });
});

// Manual journals and opening balances only; automatic ones are voided through their documents
// (sale void, return, expense void...).
router.post('/journals/:id/void', requirePermission('accounting.post_manual'), async (req, res) => {
    const result = await withTransaction(res, 'Gagal membatalkan jurnal', async (conn) => {
        const [[entry]] = await conn.execute('SELECT * FROM journal_entries WHERE id = ?', [req.params.id]);
        if (!entry) throw new AppError('Jurnal tidak ditemukan', 404);
        if (!['manual', 'opening_balance', 'pulsa_deposit'].includes(entry.source_type) || entry.reverses_entry_id) {
            throw new AppError('Hanya jurnal manual, saldo awal, dan top up deposit yang dapat dibatalkan di sini');
        }
        if (entry.status !== 'posted') throw new AppError('Jurnal ini sudah dibatalkan');
        if (entry.location_id && !req.access.can('accounting.post_manual', entry.location_id)) throw new AppError('Akses tidak diizinkan', 403);
        await reverseSource(conn, ctxOf(req), { sourceType: entry.source_type, sourceId: entry.source_id, memo: `Pembatalan ${entry.number}: ${req.body.reason || ''}`.trim() });
        await logAudit(conn, req, { action: 'void', entity: 'journal', entityId: entry.id, locationId: entry.location_id, after: { reason: req.body.reason || null } });
        return true;
    });
    if (result) res.json({ message: 'Jurnal dibatalkan dengan jurnal pembalik' });
});

// ── reports ──────────────────────────────────────────────────────────────────

const balances = async (req, { from, to, types }) => {
    const params = [];
    let where = "WHERE e.status IN ('posted', 'void')";
    // Voided entries stay in the ledger together with their reversals, so both are summed.
    where += scopeClause(req, 'jl.location_id', params);
    if (from) { where += ' AND e.entry_date >= ?'; params.push(from); }
    if (to) { where += ' AND e.entry_date <= ?'; params.push(to); }
    const [rows] = await pool.execute(
        `SELECT a.id, a.code, a.name, a.type, COALESCE(SUM(jl.debit), 0) AS debit, COALESCE(SUM(jl.credit), 0) AS credit
         FROM journal_lines jl
         JOIN journal_entries e ON e.id = jl.entry_id
         JOIN accounts a ON a.id = jl.account_id
         ${where} ${types ? `AND a.type IN (${types.map(() => '?').join(', ')})` : ''}
         GROUP BY a.id, a.code, a.name, a.type
         ORDER BY a.code`,
        types ? [...params, ...types] : params
    );
    return rows.map((r) => {
        const debit = Number(r.debit);
        const credit = Number(r.credit);
        const balance = Math.round((DEBIT_NORMAL.has(r.type) ? debit - credit : credit - debit) * 100) / 100;
        return { ...r, debit, credit, balance };
    });
};

// GET /api/accounting/trial-balance?to=&location_id=   (from is optional)
router.get('/trial-balance', requirePermission('accounting.view'), handle('Gagal menyusun neraca saldo', async (req, res) => {
    const rows = await balances(req, { from: parseDate(req.query.from), to: parseDate(req.query.to) });
    const totals = rows.reduce((t, r) => ({ debit: t.debit + r.debit, credit: t.credit + r.credit }), { debit: 0, credit: 0 });
    res.json({ accounts: rows, totals: { debit: Math.round(totals.debit * 100) / 100, credit: Math.round(totals.credit * 100) / 100 } });
}));

// GET /api/accounting/profit-loss?from=&to=&location_id=
router.get('/profit-loss', requirePermission('accounting.view'), handle('Gagal menyusun laba rugi', async (req, res) => {
    const rows = await balances(req, { from: parseDate(req.query.from), to: parseDate(req.query.to), types: ['income', 'expense'] });
    const income = rows.filter((r) => r.type === 'income');
    const expense = rows.filter((r) => r.type === 'expense');
    const sum = (list) => Math.round(list.reduce((s, r) => s + r.balance, 0) * 100) / 100;
    const cogs = rows.filter((r) => r.code.startsWith('5-'));
    res.json({
        income, expense,
        totals: {
            income: sum(income),
            cost_of_goods: sum(cogs),
            gross_profit: Math.round((sum(income) - sum(cogs)) * 100) / 100,
            expense: sum(expense),
            net_profit: Math.round((sum(income) - sum(expense)) * 100) / 100,
        },
    });
}));

const round2 = (n) => Math.round(n * 100) / 100;

// Profit in balance rows: income adds, expense (HPP included) subtracts.
const profitOf = (rows) => round2(rows.reduce((s, r) => s + (r.type === 'income' ? r.balance : r.type === 'expense' ? -r.balance : 0), 0));

// GET /api/accounting/balance-sheet?to=&location_id=   (Neraca / laporan posisi keuangan)
// Assets = liabilities + equity at the end of `to` (default today). Profit is not closed into an
// account at year end: this year's profit (from 1 January) and earlier years' profit are worked
// out from the income and expense accounts and shown under equity.
router.get('/balance-sheet', requirePermission('accounting.view'), handle('Gagal menyusun neraca', async (req, res) => {
    const to = req.query.to ? parseDate(req.query.to) : dateOnly();
    if (!to) return res.status(400).json({ error: 'Format tanggal harus YYYY-MM-DD' });
    const year = to.slice(0, 4);
    const rows = await balances(req, { to });
    const thisYear = await balances(req, { from: `${year}-01-01`, to, types: ['income', 'expense'] });
    const currentProfit = profitOf(thisYear);
    const priorProfit = round2(profitOf(rows) - currentProfit);

    const section = (type) => rows.filter((r) => r.type === type && Math.round(r.balance * 100) !== 0)
        .map(({ id, code, name, balance }) => ({ id, code, name, balance }));
    const assets = section('asset');
    const liabilities = section('liability');
    const equity = [
        ...section('equity'),
        { id: null, code: null, name: 'Laba ditahan (tahun-tahun sebelumnya)', balance: priorProfit, computed: true },
        { id: null, code: null, name: `Laba tahun berjalan ${year}`, balance: currentProfit, computed: true },
    ];
    const sum = (list) => round2(list.reduce((s, r) => s + r.balance, 0));
    const totals = { assets: sum(assets), liabilities: sum(liabilities), equity: sum(equity) };
    totals.liabilities_and_equity = round2(totals.liabilities + totals.equity);
    totals.difference = round2(totals.assets - totals.liabilities_and_equity);
    res.json({ to, assets, liabilities, equity, totals });
}));

// GET /api/accounting/ledger?account_id=&from=&to=&location_id=   (Buku Besar)
// One account: its balance before `from`, every entry line in the range with the running balance,
// and the closing balance. Ranges with more than 5000 lines are cut off (truncated: true).
const LEDGER_LIMIT = 5000;
router.get('/ledger', requirePermission('accounting.view'), handle('Gagal menyusun buku besar', async (req, res) => {
    const [[account]] = await pool.execute('SELECT id, code, name, type FROM accounts WHERE id = ?', [Number(req.query.account_id)]);
    if (!account) return res.status(400).json({ error: 'Pilih akun' });
    const today = dateOnly();
    const from = req.query.from ? parseDate(req.query.from) : `${today.slice(0, 7)}-01`;
    const to = req.query.to ? parseDate(req.query.to) : today;
    if (!from || !to) return res.status(400).json({ error: 'Format tanggal harus YYYY-MM-DD' });
    const sign = DEBIT_NORMAL.has(account.type) ? 1 : -1;
    const net = (debit, credit) => sign * (Number(debit) - Number(credit));

    const totalBetween = async (condition, values) => {
        const params = [account.id];
        let where = "jl.account_id = ? AND e.status IN ('posted', 'void')";
        where += scopeClause(req, 'jl.location_id', params);
        const [[row]] = await pool.execute(
            `SELECT COALESCE(SUM(jl.debit), 0) AS debit, COALESCE(SUM(jl.credit), 0) AS credit
             FROM journal_lines jl JOIN journal_entries e ON e.id = jl.entry_id WHERE ${where} AND ${condition}`,
            [...params, ...values]
        );
        return round2(net(row.debit, row.credit));
    };
    const opening = await totalBetween('e.entry_date < ?', [from]);
    const closing = await totalBetween('e.entry_date <= ?', [to]);

    const params = [account.id];
    let where = "jl.account_id = ? AND e.status IN ('posted', 'void')";
    where += scopeClause(req, 'jl.location_id', params);
    const [lines] = await pool.execute(
        `SELECT e.id AS entry_id, e.number, DATE_FORMAT(e.entry_date, '%Y-%m-%d') AS date, e.source_type, e.source_id, e.memo,
                jl.memo AS line_memo, jl.debit, jl.credit, l.code AS location_code
         FROM journal_lines jl
         JOIN journal_entries e ON e.id = jl.entry_id
         LEFT JOIN locations l ON l.id = jl.location_id
         WHERE ${where} AND e.entry_date BETWEEN ? AND ?
         ORDER BY e.entry_date, e.created_at, e.number
         LIMIT ${LEDGER_LIMIT + 1}`,
        [...params, from, to]
    );
    const truncated = lines.length > LEDGER_LIMIT;
    let balance = opening;
    const entries = lines.slice(0, LEDGER_LIMIT).map((l) => {
        balance = round2(balance + net(l.debit, l.credit));
        return { ...l, debit: Number(l.debit), credit: Number(l.credit), balance };
    });
    res.json({ account, from, to, opening, closing, entries, truncated });
}));

// ── periods ──────────────────────────────────────────────────────────────────

router.get('/periods', requirePermission('accounting.view'), handle('Gagal mengambil periode', async (req, res) => {
    const [periods] = await pool.execute(
        `SELECT p.year, p.month, p.status, p.closed_at, u.name AS closed_by_name
         FROM accounting_periods p LEFT JOIN users u ON u.id = p.closed_by ORDER BY p.year DESC, p.month DESC`
    );
    res.json({ periods });
}));

const setPeriod = (status) => async (req, res) => {
    const year = Number(req.params.year);
    const month = Number(req.params.month);
    if (!Number.isInteger(year) || year < 2000 || !Number.isInteger(month) || month < 1 || month > 12) {
        return res.status(400).json({ error: 'Periode tidak valid' });
    }
    const result = await withTransaction(res, 'Gagal mengubah periode', async (conn) => {
        await conn.execute(
            `INSERT INTO accounting_periods (year, month, status, closed_by, closed_at) VALUES (?, ?, ?, ?, ?)
             ON DUPLICATE KEY UPDATE status = VALUES(status), closed_by = VALUES(closed_by), closed_at = VALUES(closed_at)`,
            [year, month, status, status === 'closed' ? req.user.id : null, status === 'closed' ? new Date() : null]
        );
        await logAudit(conn, req, { action: status === 'closed' ? 'close' : 'reopen', entity: 'period', entityId: `${year}-${month}` });
        return true;
    });
    if (result) res.json({ message: status === 'closed' ? `Periode ${year}-${String(month).padStart(2, '0')} ditutup` : 'Periode dibuka kembali' });
};

router.post('/periods/:year/:month/close', requirePermission('accounting.close_period'), setPeriod('closed'));
router.post('/periods/:year/:month/reopen', requirePermission('accounting.close_period'), setPeriod('open'));

// ── account mappings ─────────────────────────────────────────────────────────

router.get('/mappings', requirePermission('accounting.view'), handle('Gagal mengambil pemetaan akun', async (req, res) => {
    const [mappings] = await pool.execute(
        `SELECT m.id, m.key, m.location_id, l.code AS location_code, a.code AS account_code, a.name AS account_name
         FROM account_mappings m JOIN accounts a ON a.id = m.account_id LEFT JOIN locations l ON l.id = m.location_id
         ORDER BY m.key, m.location_id IS NOT NULL, l.code`
    );
    res.json({ mappings });
}));

// Body: { key, account_code, location_id? } — sets (or with account_code null, removes) a mapping.
// The company-wide mapping of a key cannot be removed.
router.put('/mappings', requirePermission('settings.manage'), async (req, res) => {
    const result = await withTransaction(res, 'Gagal menyimpan pemetaan akun', async (conn) => {
        const key = String(req.body.key || '');
        const locationId = req.body.location_id ? Number(req.body.location_id) : null;
        const [[known]] = await conn.execute('SELECT 1 FROM account_mappings WHERE `key` = ? AND location_id IS NULL', [key]);
        if (!known) throw new AppError('Kunci pemetaan tidak dikenal');
        if (req.body.account_code === null) {
            if (!locationId) throw new AppError('Pemetaan utama tidak dapat dihapus');
            await conn.execute('DELETE FROM account_mappings WHERE `key` = ? AND location_id = ?', [key, locationId]);
        } else {
            const [[account]] = await conn.execute('SELECT id FROM accounts WHERE code = ? AND is_postable = 1 AND is_active = 1', [String(req.body.account_code || '')]);
            if (!account) throw new AppError('Akun tidak ditemukan atau bukan akun yang dapat dijurnal');
            const [updated] = await conn.execute(
                `UPDATE account_mappings SET account_id = ? WHERE \`key\` = ? AND ${locationId ? 'location_id = ?' : 'location_id IS NULL'}`,
                locationId ? [account.id, key, locationId] : [account.id, key]
            );
            if (updated.affectedRows === 0) {
                await conn.execute('INSERT INTO account_mappings (`key`, location_id, account_id) VALUES (?, ?, ?)', [key, locationId, account.id]);
            }
        }
        await logAudit(conn, req, { action: 'update', entity: 'account_mapping', entityId: key, locationId, after: req.body });
        return true;
    });
    if (result) res.json({ message: 'Pemetaan akun disimpan' });
});

module.exports = router;
