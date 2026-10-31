const { uuidv7 } = require('../utils/uuid');
const { AppError } = require('../utils/transaction');
const { nextDocumentNumber } = require('./documents');

// Double-entry journal. Entries must balance, are never edited (voiding posts a reversing entry),
// and cannot be dated in a closed accounting period. Call inside a transaction.

const toCents = (n) => Math.round(Number(n) * 100);
const fromCents = (c) => c / 100;

// Local calendar date (YYYY-MM-DD) of a Date / datetime; YYYY-MM-DD strings pass through unchanged.
const dateOnly = (value) => {
    if (typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value)) return value;
    const d = value ? new Date(value) : new Date();
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};

// Account id for a mapping key ('cash', 'inventory', ...): the location's own mapping wins over the global one.
const resolveAccount = async (conn, key, locationId) => {
    const [rows] = await conn.execute(
        `SELECT account_id FROM account_mappings
         WHERE \`key\` = ? AND (location_id = ? OR location_id IS NULL)
         ORDER BY location_id IS NULL LIMIT 1`,
        [key, locationId || null]
    );
    if (rows.length === 0) throw new AppError(`Pemetaan akun "${key}" belum diatur`, 500);
    return rows[0].account_id;
};

const isPeriodClosed = async (conn, date) => {
    const [year, month] = date.split('-').map(Number);
    const [rows] = await conn.execute("SELECT status FROM accounting_periods WHERE year = ? AND month = ? FOR UPDATE", [year, month]);
    return rows.length > 0 && rows[0].status === 'closed';
};

// Posts one entry and returns its id (or null when every line is zero).
//   lines: [{ account: 'mapping_key' | accountId, debit?, credit?, memo?, locationId? }]
//   strict: refuse a closed period (manual entries). Otherwise an automatic posting into a closed
//   period is moved to today, so a late document never reopens closed books.
const postEntry = async (conn, ctx, { date, locationId = null, sourceType, sourceId = null, memo = null, lines, reversesEntryId = null, strict = false }) => {
    const resolved = [];
    for (const line of lines) {
        const debit = toCents(line.debit || 0);
        const credit = toCents(line.credit || 0);
        if (debit < 0 || credit < 0) throw new AppError('Nilai debit/kredit tidak boleh negatif');
        if (debit === 0 && credit === 0) continue;
        const lineLocation = line.locationId !== undefined ? line.locationId : locationId;
        const accountId = typeof line.account === 'number' ? line.account : await resolveAccount(conn, line.account, lineLocation);
        resolved.push({ accountId, debit, credit, memo: line.memo || null, locationId: lineLocation });
    }
    if (resolved.length === 0) return null;

    const debitTotal = resolved.reduce((s, l) => s + l.debit, 0);
    const creditTotal = resolved.reduce((s, l) => s + l.credit, 0);
    if (debitTotal !== creditTotal) {
        throw new AppError(`Jurnal tidak seimbang (debit ${fromCents(debitTotal)}, kredit ${fromCents(creditTotal)})`, strict ? 400 : 500);
    }

    const accountIds = [...new Set(resolved.map((l) => l.accountId))];
    const [accounts] = await conn.execute(
        `SELECT id, code, is_postable, is_active FROM accounts WHERE id IN (${accountIds.map(() => '?').join(', ')})`,
        accountIds
    );
    for (const id of accountIds) {
        const account = accounts.find((a) => a.id === id);
        if (!account) throw new AppError(`Akun ${id} tidak ditemukan`);
        if (!account.is_postable) throw new AppError(`Akun ${account.code} adalah akun induk dan tidak dapat dijurnal`);
        if (!account.is_active) throw new AppError(`Akun ${account.code} tidak aktif`);
    }

    let entryDate = dateOnly(date);
    if (await isPeriodClosed(conn, entryDate)) {
        if (strict) throw new AppError(`Periode ${entryDate.slice(0, 7)} sudah ditutup`);
        entryDate = dateOnly();
        if (await isPeriodClosed(conn, entryDate)) throw new AppError(`Periode ${entryDate.slice(0, 7)} sudah ditutup`);
    }

    const id = uuidv7();
    const number = await nextDocumentNumber(conn, 'JV', locationId);
    await conn.execute(
        `INSERT INTO journal_entries (id, number, entry_date, location_id, source_type, source_id, memo, reverses_entry_id, created_by)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [id, number, entryDate, locationId, sourceType, sourceId === null ? null : String(sourceId), memo ? String(memo).slice(0, 255) : null,
            reversesEntryId, ctx.userId || null]
    );
    for (const l of resolved) {
        await conn.execute(
            'INSERT INTO journal_lines (id, entry_id, account_id, location_id, debit, credit, memo) VALUES (?, ?, ?, ?, ?, ?, ?)',
            [uuidv7(), id, l.accountId, l.locationId, fromCents(l.debit), fromCents(l.credit), l.memo ? String(l.memo).slice(0, 255) : null]
        );
    }
    return id;
};

// Voids every posted entry of a source by posting mirror-image entries.
// Returns the number of entries reversed.
const reverseSource = async (conn, ctx, { sourceType, sourceId, reversalSourceType, memo, date }) => {
    const [entries] = await conn.execute(
        "SELECT * FROM journal_entries WHERE source_type = ? AND source_id = ? AND status = 'posted' AND reverses_entry_id IS NULL FOR UPDATE",
        [sourceType, String(sourceId)]
    );
    for (const entry of entries) {
        const [lines] = await conn.execute('SELECT * FROM journal_lines WHERE entry_id = ?', [entry.id]);
        await postEntry(conn, ctx, {
            date,
            locationId: entry.location_id,
            sourceType: reversalSourceType || sourceType,
            sourceId,
            memo: memo || `Pembatalan ${entry.number}`,
            reversesEntryId: entry.id,
            lines: lines.map((l) => ({ account: l.account_id, debit: l.credit, credit: l.debit, memo: l.memo, locationId: l.location_id })),
        });
        await conn.execute("UPDATE journal_entries SET status = 'void' WHERE id = ?", [entry.id]);
    }
    return entries.length;
};

const hasEntry = async (conn, sourceType, sourceId) => {
    const [rows] = await conn.execute('SELECT 1 FROM journal_entries WHERE source_type = ? AND source_id = ? LIMIT 1', [sourceType, String(sourceId)]);
    return rows.length > 0;
};

module.exports = { postEntry, reverseSource, hasEntry, resolveAccount, dateOnly, toCents, fromCents };
