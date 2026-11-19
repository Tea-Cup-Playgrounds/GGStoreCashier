const express = require('express');
const pool = require('../db');
const { authenticateToken } = require('../middleware/auth');
const { AppError } = require('../utils/transaction');

// Rekap Bulanan: the monthly recap the store used to keep in a spreadsheet, rebuilt from the
// system's own records. Two parts:
//
//   omset       (branch managers, owner, accountant) — what the store sold and took in:
//                 Total omset sistem   sales before discounts (tax included), voided sales excluded
//                 Cash / QRIS + Debit / Transfer / E-wallet   what was paid, by method (cash net of change)
//                 Pengeluaran          expenses paid from the store's cash drawer (paid_from = cash)
//                 Refund               money returned to customers (returns made that month)
//                 Komplimen            discounts and vouchers given
//                 Omset bersih         omset sistem − pengeluaran − refund − komplimen
//               plus per category: net sales, cost of goods sold and gross profit.
//
//   allocation  (owner, accountant: accounting.view) — where the net takings went:
//                 Operasional          expenses paid from the bank, per expense category
//                 Pembelian stok       stock paid on receipt (supplier payments no later than the
//                                      receipt date) + pulsa deposit top-ups
//                 Pembayaran hutang    other supplier payments (paying off earlier receipts)
//                 Aset                 put into fixed-asset accounts (1-2xxx) via journals
//                 Sisa uang            omset bersih − all of the above
//                 Sisa uang pulsa      pulsa deposit balance at month end
//
// Every figure is limited to the requested location, or to the locations the user may read.
const router = express.Router();
router.use(authenticateToken);

const RECAP_PERMISSIONS = ['reports.view_location', 'reports.view_all', 'accounting.view'];
const round2 = (n) => Math.round(Number(n || 0) * 100) / 100;

const monthBounds = (value) => {
    const now = new Date();
    const month = value || `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
    const match = /^(\d{4})-(0[1-9]|1[0-2])$/.exec(month);
    if (!match) throw new AppError('Format bulan harus YYYY-MM');
    const year = Number(match[1]);
    const m = Number(match[2]);
    const next = m === 12 ? `${year + 1}-01-01` : `${year}-${String(m + 1).padStart(2, '0')}-01`;
    const last = new Date(Date.UTC(year, m, 0)).toISOString().slice(0, 10);
    return { month, from: `${month}-01`, to: last, next };
};

// Location filter: { ids: null } = every location (company-wide rows too), else a list.
const locationScope = (req) => {
    const allowed = req.access.locationsForAny(...RECAP_PERMISSIONS);
    const requested = req.query.location_id ? Number(req.query.location_id) : null;
    if (requested) {
        if (!Number.isInteger(requested) || requested <= 0) throw new AppError('location_id tidak valid');
        if (allowed !== null && !allowed.includes(requested)) throw new AppError('Akses tidak diizinkan', 403);
        return [requested];
    }
    if (allowed === null) return null;
    if (allowed.length === 0) throw new AppError('Akses tidak diizinkan', 403);
    return allowed;
};

const inScope = (ids, column) =>
    ids === null ? { sql: '', params: [] } : { sql: ` AND ${column} IN (${ids.map(() => '?').join(', ')})`, params: ids };

// GET /api/reports/monthly-recap?month=YYYY-MM&location_id=
router.get('/monthly-recap', async (req, res) => {
    try {
        if (!RECAP_PERMISSIONS.some((p) => req.access.can(p))) return res.status(403).json({ error: 'Akses tidak diizinkan' });
        const { month, from, to, next } = monthBounds(req.query.month);
        const ids = locationScope(req);
        const sales = inScope(ids, 's.location_id');
        const salesRange = [from, next];

        const [[totals]] = await pool.execute(
            `SELECT COALESCE(SUM(s.subtotal), 0) AS gross, COALESCE(SUM(s.discount_total), 0) AS discounts,
                    COALESCE(SUM(s.change_total), 0) AS change_given, COUNT(*) AS transactions
             FROM sales s WHERE s.status <> 'voided' AND s.occurred_at >= ? AND s.occurred_at < ?${sales.sql}`,
            [...salesRange, ...sales.params]
        );
        const [payments] = await pool.execute(
            `SELECT pm.type, COALESCE(SUM(sp.amount), 0) AS amount
             FROM sale_payments sp JOIN sales s ON s.id = sp.sale_id JOIN payment_methods pm ON pm.id = sp.payment_method_id
             WHERE s.status <> 'voided' AND s.occurred_at >= ? AND s.occurred_at < ?${sales.sql}
             GROUP BY pm.type`,
            [...salesRange, ...sales.params]
        );
        const returns = inScope(ids, 'r.location_id');
        const [[refund]] = await pool.execute(
            `SELECT COALESCE(SUM(r.refund_total), 0) AS total FROM sale_returns r
             WHERE r.created_at >= ? AND r.created_at < ?${returns.sql}`,
            [...salesRange, ...returns.params]
        );
        // Expenses without a location belong to head office: only in the company-wide view.
        const expenses = ids === null ? { sql: '', params: [] } : inScope(ids, 'x.location_id');
        const [expenseRows] = await pool.execute(
            `SELECT x.paid_from, a.code, a.name, COALESCE(SUM(x.amount), 0) AS amount, COUNT(*) AS count
             FROM expenses x JOIN accounts a ON a.id = x.account_id
             WHERE x.status = 'posted' AND x.expense_date >= ? AND x.expense_date <= ?${expenses.sql}
             GROUP BY x.paid_from, a.code, a.name ORDER BY a.code`,
            [from, to, ...expenses.params]
        );
        const [categoryRows] = await pool.execute(
            `SELECT c.id, COALESCE(c.name, 'Tanpa kategori') AS name,
                    COALESCE(SUM(sl.line_total * (sl.qty - sl.returned_qty) / sl.qty), 0) AS revenue,
                    COALESCE(SUM(sl.unit_cost * (sl.qty - sl.returned_qty)), 0) AS cost,
                    COALESCE(SUM(sl.qty - sl.returned_qty), 0) AS qty
             FROM sale_lines sl
             JOIN sales s ON s.id = sl.sale_id
             LEFT JOIN product_variants v ON v.id = sl.variant_id
             LEFT JOIN products p ON p.id = v.product_id
             LEFT JOIN categories c ON c.id = p.category_id
             WHERE s.status <> 'voided' AND sl.qty > 0 AND s.occurred_at >= ? AND s.occurred_at < ?${sales.sql}
             GROUP BY c.id, c.name ORDER BY revenue DESC`,
            [...salesRange, ...sales.params]
        );

        const paid = Object.fromEntries(payments.map((p) => [p.type, Number(p.amount)]));
        const cashExpenses = expenseRows.filter((e) => e.paid_from === 'cash');
        const sum = (rows) => round2(rows.reduce((s, r) => s + Number(r.amount), 0));
        const gross = round2(totals.gross);
        const discounts = round2(totals.discounts);
        const pengeluaran = sum(cashExpenses);
        const refundTotal = round2(refund.total);
        const netRevenue = round2(gross - pengeluaran - round2(refundTotal) - discounts);

        const omset = {
            gross,
            transactions: Number(totals.transactions),
            cash: round2((paid.cash || 0) - Number(totals.change_given)),
            qris_debit: round2((paid.qris || 0) + (paid.card || 0)),
            transfer: round2(paid.transfer || 0),
            ewallet: round2(paid.ewallet || 0),
            expenses: pengeluaran,
            expense_lines: cashExpenses.map((e) => ({ code: e.code, name: e.name, amount: round2(e.amount), count: Number(e.count) })),
            refund: refundTotal,
            discounts,
            net: netRevenue,
        };
        const categories = categoryRows.map((c) => {
            // Whole rupiah: returned items are pro-rated, which leaves fractions of a rupiah.
            const revenue = Math.round(Number(c.revenue));
            const cost = Math.round(Number(c.cost));
            return { id: c.id, name: c.name, qty: Number(c.qty), revenue, cost, gross_profit: round2(revenue - cost) };
        });

        let allocation = null;
        if (req.access.can('accounting.view')) {
            const bankExpenses = expenseRows.filter((e) => e.paid_from === 'bank');
            const receipts = inScope(ids, 'gr.location_id');
            const [[supplier]] = await pool.execute(
                `SELECT COALESCE(SUM(CASE WHEN gr.due_date IS NULL OR sp.paid_at <= gr.received_date THEN sp.amount ELSE 0 END), 0) AS on_receipt,
                        COALESCE(SUM(CASE WHEN gr.due_date IS NULL OR sp.paid_at <= gr.received_date THEN 0 ELSE sp.amount END), 0) AS debt
                 FROM supplier_payments sp JOIN goods_receipts gr ON gr.id = sp.receipt_id
                 WHERE sp.paid_at >= ? AND sp.paid_at <= ?${receipts.sql}`,
                [from, to, ...receipts.params]
            );
            const lines = ids === null ? { sql: '', params: [] } : inScope(ids, 'jl.location_id');
            const [[journals]] = await pool.execute(
                `SELECT
                    COALESCE(SUM(CASE WHEN a.code LIKE '1-2%' THEN jl.debit - jl.credit ELSE 0 END), 0) AS assets,
                    COALESCE(SUM(CASE WHEN a.code = '1-1600' AND e.source_type = 'pulsa_deposit' THEN jl.debit - jl.credit ELSE 0 END), 0) AS pulsa_top_ups
                 FROM journal_lines jl JOIN journal_entries e ON e.id = jl.entry_id JOIN accounts a ON a.id = jl.account_id
                 WHERE e.status IN ('posted', 'void') AND e.entry_date >= ? AND e.entry_date <= ?${lines.sql}`,
                [from, to, ...lines.params]
            );
            const [[pulsa]] = await pool.execute(
                `SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS balance
                 FROM journal_lines jl JOIN journal_entries e ON e.id = jl.entry_id JOIN accounts a ON a.id = jl.account_id
                 WHERE a.code = '1-1600' AND e.status IN ('posted', 'void') AND e.entry_date <= ?${lines.sql}`,
                [to, ...lines.params]
            );
            const operational = sum(bankExpenses);
            const stockGoods = round2(supplier.on_receipt);
            const stockPulsa = round2(journals.pulsa_top_ups);
            const stock = round2(stockGoods + stockPulsa);
            const debt = round2(supplier.debt);
            const assets = round2(journals.assets);
            allocation = {
                net_revenue: netRevenue,
                operational,
                operational_lines: bankExpenses.map((e) => ({ code: e.code, name: e.name, amount: round2(e.amount), count: Number(e.count) })),
                stock_purchases: stock,
                stock_goods: stockGoods,
                stock_pulsa: stockPulsa,
                debt_payments: debt,
                assets,
                remaining: round2(netRevenue - operational - stock - debt - assets),
                pulsa_balance: round2(pulsa.balance),
            };
        }

        res.json({ month, from, to, location_id: req.query.location_id ? Number(req.query.location_id) : null, omset, categories, allocation });
    } catch (error) {
        if (error instanceof AppError) return res.status(error.status).json({ error: error.message });
        console.error('monthly-recap error:', error);
        res.status(500).json({ error: 'Gagal menyusun rekap bulanan' });
    }
});

module.exports = router;
