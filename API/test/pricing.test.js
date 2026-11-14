// Run with: npm test  (node's built-in test runner, no database needed)
const test = require('node:test');
const assert = require('node:assert/strict');
const {
    toCents, allocate, voucherShare, finalizeLines, finalizeCopy, fitToPaid, grandCentsOf,
} = require('../src/services/pricing');

const inclusive = { inclusive: true, defaultRate: 11 };
const exclusive = { inclusive: false, defaultRate: 11 };

const line = (overrides) => ({
    variantId: 1, categoryId: 10, qty: 1, unitPrice: 10000, discount: 0, taxRate: 11, unitIds: [], ...overrides,
});

test('allocate splits cents exactly, leftovers to the largest line', () => {
    const parts = allocate(1000, [3333, 3333, 3334]);
    assert.equal(parts.reduce((s, p) => s + p, 0), 1000);
    assert.deepEqual(parts, [333, 333, 334]);
    assert.deepEqual(allocate(0, [5, 5]), [0, 0]);
});

test('a product voucher only discounts that product', () => {
    const lines = [line({ variantId: 1, unitPrice: 50000 }), line({ variantId: 2, unitPrice: 30000 })];
    const voucher = { target_type: 'product', target_id: 2, discount_type: 'percent', discount_value: 10 };
    const share = voucherShare(voucher, lines);
    assert.equal(share.cents, toCents(3000));
    finalizeLines(lines, { voucher, saleDiscount: 0, taxSettings: inclusive });
    assert.equal(lines[0].discount, 0);
    assert.equal(lines[1].discount, 3000);
    assert.equal(lines[1].lineTotal, 27000);
});

test('a voucher for something not in the cart has no share and is refused by finalizeLines', () => {
    const lines = [line({ categoryId: 10 })];
    const voucher = { target_type: 'categories', target_id: 99, discount_type: 'fixed', discount_value: 5000 };
    assert.equal(voucherShare(voucher, lines), null);
    assert.throws(() => finalizeLines(lines, { voucher, saleDiscount: 0, taxSettings: inclusive }), /Voucher tidak berlaku/);
});

test('PPN inside the price when prices include tax', () => {
    const lines = [line({ unitPrice: 11100 })];
    finalizeLines(lines, { voucher: null, saleDiscount: 0, taxSettings: inclusive });
    assert.equal(lines[0].lineTotal, 11100);
    assert.equal(lines[0].taxAmount, 1100);
});

test('finalizeCopy leaves the priced lines untouched', () => {
    const priced = [line({ unitPrice: 20000 })];
    const copy = finalizeCopy(priced, { voucher: null, saleDiscount: 5000, taxSettings: inclusive });
    assert.equal(copy[0].lineTotal, 15000);
    assert.equal(priced[0].discount, 0);
    assert.equal(priced[0].lineTotal, undefined);
});

test('fitToPaid adds nothing when the customer paid enough', () => {
    const priced = [line({ unitPrice: 25000, qty: 2 })];
    const { lines, extraCents } = fitToPaid(priced, { voucher: null, saleDiscount: 0, taxSettings: inclusive }, toCents(60000));
    assert.equal(extraCents, 0);
    assert.equal(grandCentsOf(lines), toCents(50000));
});

test('fitToPaid records a price rise after an offline sale as discount (tax included)', () => {
    // Sold offline for 2 x 25.000 = 50.000; the price is 27.500 by the time it syncs.
    const priced = [line({ unitPrice: 27500, qty: 2 }), line({ variantId: 2, unitPrice: 9000 })];
    const paid = toCents(59000);
    const { lines, extraCents } = fitToPaid(priced, { voucher: null, saleDiscount: 0, taxSettings: inclusive }, paid);
    assert.equal(extraCents, toCents(5000));
    assert.equal(grandCentsOf(lines), paid);
    const discounts = lines.reduce((s, l) => s + toCents(l.discount), 0);
    assert.equal(discounts, toCents(5000));
});

test('fitToPaid finds the smallest discount when tax is added on top', () => {
    const priced = [line({ unitPrice: 33333, qty: 3 }), line({ variantId: 2, unitPrice: 12345, taxRate: 0 })];
    const opts = { voucher: null, saleDiscount: 0, taxSettings: exclusive };
    const paid = toCents(100000);
    const { lines, extraCents } = fitToPaid(priced, opts, paid);
    assert.ok(extraCents > 0);
    assert.ok(grandCentsOf(lines) <= paid, 'total fits what was paid');
    assert.ok(grandCentsOf(finalizeCopy(priced, opts, extraCents - 1)) > paid, 'one cent less discount would not fit');
});

test('fitToPaid keeps a voucher and adds to it', () => {
    const priced = [line({ unitPrice: 40000 })];
    const voucher = { target_type: null, target_id: null, discount_type: 'fixed', discount_value: 5000 };
    const { lines, extraCents } = fitToPaid(priced, { voucher, saleDiscount: 0, taxSettings: inclusive }, toCents(30000));
    assert.equal(extraCents, toCents(5000));
    assert.equal(lines[0].discount, 10000);
    assert.equal(lines[0].lineTotal, 30000);
});
