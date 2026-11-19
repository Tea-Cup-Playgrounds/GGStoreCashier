// Accounting end to end against a real MySQL database: document dates, closed periods, opening
// balances and opening stock, expenses, pulsa deposit, transfers between locations, and the
// reports (trial balance, profit & loss, balance sheet, ledger) agreeing with each other.
//
// Run:  TEST_DB_NAME=gg_test_accounting npm run test:integration
// The database named by TEST_DB_NAME (it must start with "gg_test") is DROPPED and re-created,
// migrated and seeded. Connection settings come from DB_HOST / DB_PORT / DB_USER / DB_PASS.
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const { randomUUID } = require('crypto');

const DB = process.env.TEST_DB_NAME;
const skip = !DB ? 'set TEST_DB_NAME (a database name starting with gg_test) to run' : false;

const BR01 = 2;
const BR02 = 3;
const WH = 1;
const USERS = { owner: 1, admin1: 2, kasir1: 3, admin2: 4 };

let base;
let server;
let pool;
let jwt;

// Live events published by the API (services/live.js), recorded by a stand-in for Socket.IO.
const liveLog = [];
const fakeIo = {
    emit: (event, payload) => liveLog.push({ rooms: ['*'], event, payload }),
    to(room) {
        const rooms = [room];
        const chain = {
            to: (r) => (rooms.push(r), chain),
            emit: (event, payload) => liveLog.push({ rooms: [...rooms], event, payload }),
        };
        return chain;
    },
};
// Events go out when the response finishes; give that a moment after fetch resolves.
const settle = () => new Promise((resolve) => setTimeout(resolve, 50));

const call = async (method, url, user, body) => {
    const token = jwt.sign({ userId: USERS[user] }, process.env.JWT_SECRET, { expiresIn: '1h' });
    const res = await fetch(base + url, {
        method,
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
        body: body ? JSON.stringify(body) : undefined,
    });
    return { status: res.status, body: await res.json().catch(() => null) };
};
const ok = (r, status = 200) => {
    assert.equal(r.status, status, JSON.stringify(r.body));
    return r.body;
};
const q = async (sql, params = []) => (await pool.execute(sql, params))[0];
const journalOf = async (sourceType, sourceId) => q(
    `SELECT DATE_FORMAT(e.entry_date, '%Y-%m-%d') AS date, e.number, a.code, jl.location_id, jl.debit + 0 AS debit, jl.credit + 0 AS credit
     FROM journal_entries e JOIN journal_lines jl ON jl.entry_id = e.id JOIN accounts a ON a.id = jl.account_id
     WHERE e.source_type = ? AND e.source_id = ? ORDER BY e.created_at, a.code`,
    [sourceType, String(sourceId)]
);
const line = (lines, code, side) => lines.filter((l) => l.code === code).reduce((s, l) => s + Number(l[side]), 0);

const state = {};

test('accounting module', { skip }, async (t) => {
    t.before(async () => {
        if (!/^gg_test/.test(DB)) throw new Error('TEST_DB_NAME must start with gg_test (the database is dropped)');
        Object.assign(process.env, {
            DB_HOST: process.env.DB_HOST || '127.0.0.1', DB_USER: process.env.DB_USER || 'root', DB_PASS: process.env.DB_PASS || '',
            DB_NAME: DB, JWT_SECRET: 'integration-test', NODE_ENV: 'test',
        });
        const root = path.join(__dirname, '..', '..', '..');
        const mysql = require(path.join(root, 'node_modules', 'mysql2/promise'));
        const admin = await mysql.createConnection({
            host: process.env.DB_HOST, port: Number(process.env.DB_PORT || 3306), user: process.env.DB_USER, password: process.env.DB_PASS,
        });
        await admin.query(`DROP DATABASE IF EXISTS \`${DB}\``);
        await admin.query(`CREATE DATABASE \`${DB}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci`);
        await admin.end();

        const knex = require(path.join(root, 'node_modules', 'knex'))(require('../../knexfile'));
        await knex.migrate.latest();
        await knex.seed.run();
        await knex.destroy();

        const express = require(path.join(root, 'node_modules', 'express'));
        const cookieParser = require(path.join(root, 'node_modules', 'cookie-parser'));
        jwt = require(path.join(root, 'node_modules', 'jsonwebtoken'));
        pool = require('../../src/db');
        const app = express();
        app.use(express.json());
        app.use(cookieParser());
        app.use(require('../../src/services/live').liveEvents(fakeIo));
        for (const [prefix, file] of [['catalog', 'catalog'], ['stock', 'stock'], ['purchasing', 'purchasing'], ['transfers', 'transfers'],
            ['opnames', 'opnames'], ['sales', 'sales'], ['accounting', 'accounting'], ['expenses', 'expenses'], ['pulsa-deposit', 'pulsa_deposit'], ['reports', 'reports']]) {
            app.use(`/api/${prefix}`, require(`../../src/routes/${file}`));
        }
        server = app.listen(0);
        base = `http://127.0.0.1:${server.address().port}`;

        const product = async (body) => ok(await call('POST', '/api/catalog/products', 'owner', body), 201).product.variants[0].id;
        state.charger = await product({ name: 'Charger 20W', kind: 'goods', variants: [{ sku: 'T-CHG', base_price: 85000 }] });
        state.pulsa = await product({ name: 'Pulsa 10rb', kind: 'digital', variants: [{ sku: 'T-PLS10', base_price: 12000, cost_price: 10150 }] });
        state.supplier = ok(await call('POST', '/api/purchasing/suppliers', 'owner', { name: 'PT Uji' }), 201).supplier.id;
    });
    t.after(async () => {
        server?.close();
        await pool?.end();
    });

    await t.test('opening balances: difference to Ekuitas Saldo Awal; stock and P&L accounts refused', async () => {
        const r = ok(await call('POST', '/api/accounting/opening-balances', 'owner', {
            date: '2026-01-01',
            lines: [
                { account_code: '1-1100', debit: 10_000_000 },
                { account_code: '1-1200', debit: 100_000_000 },
                { account_code: '2-1100', credit: 5_000_000 },
                { account_code: '3-1000', credit: 50_000_000 },
            ],
        }), 201);
        assert.equal(r.journal.entry_date, '2026-01-01');
        assert.match(r.journal.number, /^JV-HQ-260101-/);
        const equity = r.journal.lines.find((l) => l.account_code === '3-3000');
        assert.equal(Number(equity.credit), 55_000_000);

        const stock = await call('POST', '/api/accounting/opening-balances', 'owner', { date: '2026-01-01', lines: [{ account_code: '1-1400', debit: 1 }] });
        assert.equal(stock.status, 400);
        assert.match(stock.body.error, /stok awal/i);
        const income = await call('POST', '/api/accounting/opening-balances', 'owner', { date: '2026-01-01', lines: [{ account_code: '4-1000', credit: 1 }] });
        assert.match(income.body.error, /bukan akun neraca/);
    });

    await t.test('opening stock books against Ekuitas Saldo Awal, dated', async () => {
        const r = ok(await call('POST', '/api/stock/adjust', 'owner', {
            location_id: BR01, variant_id: state.charger, qty_change: 10, unit_cost: 50000, note: 'Stok awal', date: '2026-01-01', opening: true,
        }));
        const lines = await journalOf('stock_adjustment', r.movementId);
        assert.equal(lines[0].date, '2026-01-01');
        assert.equal(line(lines, '1-1400', 'debit'), 500000);
        assert.equal(line(lines, '3-3000', 'credit'), 500000);
        assert.equal(line(lines, '5-2000', 'credit'), 0, 'not a stock-difference gain');
        const [move] = await q("SELECT reason, DATE_FORMAT(created_at, '%Y-%m-%d') AS d FROM stock_movements WHERE id = ?", [r.movementId]);
        assert.deepEqual(move, { reason: 'opening', d: '2026-01-01' });
        ok(await call('POST', '/api/stock/adjust', 'owner', {
            location_id: WH, variant_id: state.charger, qty_change: 30, unit_cost: 50000, note: 'Stok awal', date: '2026-01-01', opening: true,
        }));
        const noCost = await call('POST', '/api/stock/adjust', 'owner', { location_id: BR01, variant_id: state.charger, qty_change: 1, note: 'x', opening: true });
        assert.equal(noCost.status, 400);
    });

    await t.test('goods receipt: received date sets number, stock movements and journal', async () => {
        const receipt = ok(await call('POST', '/api/purchasing/receipts', 'owner', {
            location_id: BR01, supplier_id: state.supplier, received_date: '2026-02-10',
            items: [{ variant_id: state.charger, qty: 20, unit_cost: 50000, tax_rate: 11 }],
        }), 201).receipt;
        assert.match(receipt.number, /^GR-BR01-260210-/);
        assert.equal(receipt.received_date, '2026-02-10');
        state.receipt = receipt.id;
        // A second draft dated in February, posted after February is closed (below).
        state.lateDraft = ok(await call('POST', '/api/purchasing/receipts', 'owner', {
            location_id: BR01, supplier_id: state.supplier, received_date: '2026-02-12',
            items: [{ variant_id: state.charger, qty: 1, unit_cost: 50000 }],
        }), 201).receipt.id;
        ok(await call('POST', `/api/purchasing/receipts/${receipt.id}/post`, 'owner'));
        const lines = await journalOf('goods_receipt', receipt.id);
        assert.equal(lines[0].date, '2026-02-10');
        assert.equal(line(lines, '2-1100', 'credit'), 1_110_000);
        const moves = await q("SELECT DISTINCT DATE_FORMAT(created_at, '%Y-%m-%d') AS d FROM stock_movements WHERE ref_id = ?", [receipt.id]);
        assert.deepEqual(moves.map((m) => m.d), ['2026-02-10']);
        const future = await call('POST', '/api/purchasing/receipts', 'owner', {
            location_id: BR01, supplier_id: state.supplier, received_date: '2099-01-01', items: [{ variant_id: state.charger, qty: 1, unit_cost: 1 }],
        });
        assert.match(future.body.error, /masa depan/);
    });

    await t.test('a closed month refuses new documents dated in it', async () => {
        ok(await call('POST', '/api/accounting/periods/2026/2/close', 'owner'));
        const draft = await call('POST', '/api/purchasing/receipts', 'owner', {
            location_id: BR01, supplier_id: state.supplier, received_date: '2026-02-15', items: [{ variant_id: state.charger, qty: 1, unit_cost: 1 }],
        });
        assert.match(draft.body.error, /Periode 2026-02 sudah ditutup/);
        const post = await call('POST', `/api/purchasing/receipts/${state.lateDraft}/post`, 'owner');
        assert.match(post.body.error, /Periode 2026-02 sudah ditutup/);
        const pay = await call('POST', '/api/purchasing/payments', 'owner', { receipt_id: state.receipt, amount: 500000, method: 'transfer', paid_at: '2026-02-20' });
        assert.match(pay.body.error, /Periode 2026-02/);
        const paid = ok(await call('POST', '/api/purchasing/payments', 'owner', { receipt_id: state.receipt, amount: 500000, method: 'transfer', paid_at: '2026-03-10' }), 201);
        assert.equal((await journalOf('supplier_payment', paid.paymentId))[0].date, '2026-03-10');
    });

    await t.test('sale numbered by its date; return dated, not before the sale', async () => {
        const sale = ok(await call('POST', '/api/sales', 'kasir1', {
            id: randomUUID(), location_id: BR01, occurred_at: '2026-03-05T03:00:00.000Z',
            lines: [{ variant_id: state.charger, qty: 2 }], payments: [{ payment_method_id: 1, amount: 170000 }],
        }), 201).sale;
        assert.match(sale.number, /^INV-BR01-260305-/);
        assert.equal((await journalOf('sale', sale.id))[0].date, '2026-03-05');
        const future = await call('POST', '/api/sales', 'kasir1', {
            id: randomUUID(), location_id: BR01, occurred_at: '2099-01-01T00:00:00Z',
            lines: [{ variant_id: state.charger, qty: 1 }], payments: [{ payment_method_id: 1, amount: 85000 }],
        });
        assert.equal(future.status, 400);

        const early = await call('POST', `/api/sales/${sale.id}/returns`, 'admin1', {
            date: '2026-03-01', lines: [{ sale_line_id: sale.lines[0].id, qty: 1 }], refund_method_id: 1, reason: 'Rusak',
        });
        assert.match(early.body.error, /sebelum tanggal penjualan/);
        const ret = ok(await call('POST', `/api/sales/${sale.id}/returns`, 'admin1', {
            date: '2026-03-07', lines: [{ sale_line_id: sale.lines[0].id, qty: 1 }], refund_method_id: 1, reason: 'Tidak cocok',
        }), 201);
        assert.match(ret.number, /^RT-BR01-260307-/);
        assert.equal((await journalOf('sale_return', ret.returnId))[0].date, '2026-03-07');
    });

    await t.test('pulsa: top-up, cost of each sale from the deposit, refund back to it', async () => {
        const denied = await call('POST', '/api/pulsa-deposit/top-ups', 'kasir1', { location_id: BR01, date: '2026-03-01', amount: 1_000_000, paid_from: 'bank' });
        assert.equal(denied.status, 403);
        ok(await call('POST', '/api/pulsa-deposit/top-ups', 'admin1', { location_id: BR01, date: '2026-03-01', amount: 1_000_000, paid_from: 'bank' }), 201);

        const sale = ok(await call('POST', '/api/sales', 'kasir1', {
            id: randomUUID(), location_id: BR01, occurred_at: '2026-03-06T03:00:00.000Z',
            lines: [{ variant_id: state.pulsa, qty: 3 }], payments: [{ payment_method_id: 1, amount: 36000 }],
        }), 201).sale;
        const lines = await journalOf('sale', sale.id);
        assert.equal(line(lines, '5-1000', 'debit'), 30450, '3 × 10.150');
        assert.equal(line(lines, '1-1600', 'credit'), 30450);
        let deposit = ok(await call('GET', `/api/pulsa-deposit?location_id=${BR01}`, 'admin1'));
        assert.equal(deposit.balance, 969550);
        assert.equal(deposit.top_ups.length, 1);
        assert.deepEqual(deposit.usage.map((u) => [u.month, u.used]), [['2026-03', 30450]]);

        ok(await call('POST', `/api/sales/${sale.id}/returns`, 'admin1', {
            date: '2026-03-08', lines: [{ sale_line_id: sale.lines[0].id, qty: 1 }], refund_method_id: 1, reason: 'Gagal terkirim',
        }), 201);
        deposit = ok(await call('GET', `/api/pulsa-deposit?location_id=${BR01}`, 'admin1'));
        assert.equal(deposit.balance, 979700, 'one pulsa back in the deposit');
    });

    await t.test('expenses: categories, location rules, journal, void', async () => {
        const { categories } = ok(await call('GET', '/api/expenses/categories', 'admin1'));
        const codes = categories.map((c) => c.code);
        assert.ok(codes.includes('6-1000') && codes.includes('6-2000'));
        for (const system of ['5-1000', '5-2000', '6-9100']) assert.ok(!codes.includes(system), `${system} is booked by the system`);

        const body = { date: '2026-03-31', account_code: '6-1000', amount: 5_000_000, paid_from: 'bank', payee: 'Pemilik ruko' };
        assert.equal((await call('POST', '/api/expenses', 'admin1', { ...body, location_id: BR02 })).status, 403, 'other branch');
        assert.equal((await call('POST', '/api/expenses', 'kasir1', { ...body, location_id: BR01 })).status, 403, 'cashier');
        assert.equal((await call('POST', '/api/expenses', 'admin1', body)).status, 403, 'company-wide needs every location');

        const rent = ok(await call('POST', '/api/expenses', 'admin1', { ...body, location_id: BR01 }), 201).expense;
        assert.match(rent.number, /^EXP-BR01-260331-/);
        const lines = await journalOf('expense', rent.id);
        assert.equal(lines[0].date, '2026-03-31');
        assert.equal(line(lines, '6-1000', 'debit'), 5_000_000);
        assert.equal(line(lines, '1-1200', 'credit'), 5_000_000);
        const salary = ok(await call('POST', '/api/expenses', 'owner', { date: '2026-03-31', account_code: '6-2000', amount: 20_000_000, paid_from: 'bank' }), 201).expense;
        assert.match(salary.number, /^EXP-HQ-260331-/);
        const internet = ok(await call('POST', '/api/expenses', 'admin1', { ...body, account_code: '6-3000', amount: 750_000, location_id: BR01 }), 201).expense;

        ok(await call('POST', `/api/expenses/${internet.id}/void`, 'admin1', { reason: 'Salah input' }));
        assert.equal((await call('POST', `/api/expenses/${internet.id}/void`, 'admin1', { reason: 'lagi' })).status, 400);
        const reversal = await journalOf('expense_void', internet.id);
        assert.equal(line(reversal, '6-3000', 'credit'), 750_000);
        const list = ok(await call('GET', `/api/expenses?location_id=${BR01}`, 'admin1'));
        assert.equal(list.total, 5_000_000, 'void expense not counted');
        assert.equal(list.expenses.length, 2);
    });

    await t.test('transfer: value moves between locations through the inter-location account', async () => {
        const transfer = ok(await call('POST', '/api/transfers', 'owner', {
            from_location_id: WH, to_location_id: BR02, items: [{ variant_id: state.charger, qty: 10 }],
        }), 201).transfer;
        ok(await call('POST', `/api/transfers/${transfer.id}/send`, 'owner', { date: '2026-04-01' }));
        const early = await call('POST', `/api/transfers/${transfer.id}/receive`, 'owner', { date: '2026-03-31' });
        assert.match(early.body.error, /sebelum tanggal kirim/);
        ok(await call('POST', `/api/transfers/${transfer.id}/receive`, 'owner', {
            date: '2026-04-02', items: [{ item_id: transfer.items[0].id, qty_received: 8 }],
        }));
        const lines = await journalOf('transfer', transfer.id);
        assert.equal(lines[0].date, '2026-04-02');
        const at = (code, loc, side) => lines.filter((l) => l.code === code && l.location_id === loc).reduce((s, l) => s + Number(l[side]), 0);
        assert.equal(at('1-1400', BR02, 'debit'), 400000, '8 × 50.000 into BR02');
        assert.equal(at('1-1400', WH, 'credit'), 400000);
        assert.equal(at('1-1700', BR02, 'credit'), 400000);
        assert.equal(at('1-1700', WH, 'debit'), 400000);
    });

    await t.test('reports agree: trial balance, P&L, balance sheet (company and each location), ledger', async () => {
        const tb = ok(await call('GET', '/api/accounting/trial-balance', 'owner'));
        assert.equal(tb.totals.debit, tb.totals.credit);

        const bs = ok(await call('GET', '/api/accounting/balance-sheet?to=2026-12-31', 'owner'));
        assert.equal(bs.totals.difference, 0, JSON.stringify(bs.totals));
        const pl = ok(await call('GET', '/api/accounting/profit-loss?from=2026-01-01&to=2026-12-31', 'owner'));
        assert.equal(bs.equity.find((e) => e.name.startsWith('Laba tahun berjalan')).balance, pl.totals.net_profit);
        assert.equal(bs.assets.find((a) => a.code === '1-1700'), undefined, 'inter-location nets to zero company-wide');

        for (const location of [WH, BR01, BR02]) {
            const own = ok(await call('GET', `/api/accounting/balance-sheet?to=2026-12-31&location_id=${location}`, 'owner'));
            assert.equal(own.totals.difference, 0, `location ${location}: ${JSON.stringify(own.totals)}`);
        }

        const march = ok(await call('GET', `/api/accounting/balance-sheet?to=2026-03-31`, 'owner'));
        const kas = ok(await call('GET', '/api/accounting/ledger?account_id=' +
            (await q("SELECT id FROM accounts WHERE code = '1-1100'"))[0].id + '&from=2026-03-01&to=2026-03-31', 'owner'));
        assert.equal(kas.opening, 10_000_000, 'opening balance from January');
        assert.ok(kas.entries.length >= 4);
        assert.equal(kas.entries.at(-1).balance, kas.closing);
        assert.equal(kas.closing, march.assets.find((a) => a.code === '1-1100').balance, 'ledger closing = balance sheet');
    });

    await t.test('branch manager: own branch Laba Rugi and Neraca only; detailed books stay closed', async () => {
        const range = 'from=2026-01-01&to=2026-12-31';
        const ownerPl = ok(await call('GET', `/api/accounting/profit-loss?${range}&location_id=${BR01}`, 'owner'));
        const pl = ok(await call('GET', `/api/accounting/profit-loss?${range}&location_id=${BR01}`, 'admin1'));
        assert.deepEqual(pl.totals, ownerPl.totals);
        const scoped = ok(await call('GET', `/api/accounting/profit-loss?${range}`, 'admin1'));
        assert.deepEqual(scoped.totals, ownerPl.totals, 'no location = their own branch, not the company');

        const ownerBs = ok(await call('GET', `/api/accounting/balance-sheet?to=2026-12-31&location_id=${BR01}`, 'owner'));
        const bs = ok(await call('GET', '/api/accounting/balance-sheet?to=2026-12-31', 'admin1'));
        assert.deepEqual(bs.totals, ownerBs.totals);
        assert.equal(bs.totals.difference, 0);

        assert.equal((await call('GET', `/api/accounting/profit-loss?${range}&location_id=${BR02}`, 'admin1')).status, 403, 'other branch');
        assert.equal((await call('GET', `/api/accounting/balance-sheet?location_id=${BR02}`, 'admin1')).status, 403, 'other branch');
        for (const url of ['/api/accounting/journals', '/api/accounting/trial-balance', '/api/accounting/accounts']) {
            assert.equal((await call('GET', url, 'admin1')).status, 403, url);
        }
        assert.equal((await call('GET', `/api/accounting/profit-loss?${range}`, 'kasir1')).status, 403, 'cashier');
    });

    await t.test('monthly recap: spreadsheet formulas, payments add up, branch managers see their branch only', async () => {
        const recap = ok(await call('GET', '/api/reports/monthly-recap?month=2026-03', 'owner'));
        const o = recap.omset;
        const near = (a, b, msg) => assert.ok(Math.abs(a - b) < 0.01, `${msg}: ${a} vs ${b}`);
        near(o.net, o.gross - o.expenses - o.refund - o.discounts, 'omset bersih = sistem − pengeluaran − refund − komplimen');
        near(o.cash + o.qris_debit + o.transfer + o.ewallet, o.gross - o.discounts, 'payments = what customers paid');
        assert.ok(o.refund >= 85000, 'the March return is in March');
        const a = recap.allocation;
        assert.ok(a, 'owner sees the allocation');
        near(a.remaining, a.net_revenue - a.operational - a.stock_purchases - a.debt_payments - a.assets, 'sisa uang');
        near(a.stock_purchases, a.stock_goods + a.stock_pulsa, 'pembelian stok = goods + pulsa');

        const branch = ok(await call('GET', '/api/reports/monthly-recap?month=2026-03', 'admin1'));
        assert.equal(branch.allocation, null, 'branch managers get the store recap only');
        const ownerBr01 = ok(await call('GET', `/api/reports/monthly-recap?month=2026-03&location_id=${BR01}`, 'owner'));
        assert.deepEqual(branch.omset, ownerBr01.omset, 'no location = their own branch');
        assert.equal((await call('GET', `/api/reports/monthly-recap?month=2026-03&location_id=${BR02}`, 'admin1')).status, 403);
        assert.equal((await call('GET', '/api/reports/monthly-recap?month=2026-03', 'kasir1')).status, 403);
        assert.equal((await call('GET', '/api/reports/monthly-recap?month=2026-3', 'owner')).status, 400);
    });

    await t.test('live events: announced after success, to the right rooms, never for refused requests', async () => {
        const changed = () => liveLog.filter((e) => e.event === 'changed');
        const branchRooms = (id) => [`branch-${id}`, 'branch-0'];

        liveLog.length = 0;
        const body = { date: '2026-04-30', account_code: '6-1000', amount: 150_000, paid_from: 'cash' };
        assert.equal((await call('POST', '/api/expenses', 'admin1', { ...body, location_id: BR02 })).status, 403);
        await settle();
        assert.equal(changed().length, 0, 'a refused request announces nothing');

        const expense = ok(await call('POST', '/api/expenses', 'admin1', { ...body, location_id: BR01 }), 201).expense;
        await settle();
        let events = changed();
        assert.equal(events.length, 1);
        assert.deepEqual(events[0].rooms, branchRooms(BR01));
        assert.equal(events[0].payload.entity, 'expense');
        assert.equal(events[0].payload.action, 'create');
        assert.equal(events[0].payload.location_id, BR01);
        assert.deepEqual(events[0].payload.ids, [String(expense.id)]);
        assert.ok(events[0].payload.topics.includes('expenses') && events[0].payload.topics.includes('reports'));

        // A transfer concerns both locations.
        liveLog.length = 0;
        const transfer = ok(await call('POST', '/api/transfers', 'owner', {
            from_location_id: WH, to_location_id: BR02, items: [{ variant_id: state.charger, qty: 1 }],
        }), 201).transfer;
        ok(await call('POST', `/api/transfers/${transfer.id}/send`, 'owner', { date: '2026-04-30' }));
        await settle();
        events = changed().filter((e) => e.payload.action === 'send');
        assert.deepEqual(events.map((e) => e.payload.location_id).sort(), [WH, BR02].sort(), 'sender and receiver both told');
        assert.ok(events.every((e) => e.payload.topics.includes('stock')));

        // A sale at BR01.
        liveLog.length = 0;
        ok(await call('POST', '/api/sales', 'kasir1', {
            id: randomUUID(), location_id: BR01, occurred_at: '2026-04-30T03:00:00.000Z',
            lines: [{ variant_id: state.charger, qty: 1 }], payments: [{ payment_method_id: 1, amount: 85000 }],
        }), 201);
        await settle();
        events = changed().filter((e) => e.payload.entity === 'sale');
        assert.equal(events.length, 1);
        assert.deepEqual(events[0].rooms, branchRooms(BR01));
        assert.ok(['sales', 'stock', 'shifts'].every((t) => events[0].payload.topics.includes(t)));

        // No location (catalog): every connected device.
        liveLog.length = 0;
        ok(await call('POST', '/api/catalog/products', 'owner', { name: 'Kabel Uji Live', kind: 'goods', variants: [{ sku: 'T-LIVE', base_price: 10000 }] }), 201);
        await settle();
        events = changed().filter((e) => e.payload.entity === 'product');
        assert.equal(events.length, 1);
        assert.deepEqual(events[0].rooms, ['*']);
        assert.equal(events[0].payload.location_id, null);
    });

    await t.test('stock count approved with a date before it started is refused', async () => {
        const opname = ok(await call('POST', '/api/opnames', 'owner', { location_id: BR01 }), 201).opname;
        const r = await call('POST', `/api/opnames/${opname.id}/approve`, 'owner', { date: '2026-04-30' });
        assert.match(r.body.error, /sebelum tanggal mulai opname/);
        const approved = ok(await call('POST', `/api/opnames/${opname.id}/approve`, 'owner', {}));
        assert.ok(approved.opname.adjustment_date);
    });
});
