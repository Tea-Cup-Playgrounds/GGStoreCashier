// Pricing a sale: voucher and sale-level discounts spread over the lines, then the PPN inside (or
// on top of) each line. Pure functions on the lines built by routes/sales.js (priceLines), kept
// here so they can be tested without a database.
//
// A line: { variantId, categoryId, qty, unitPrice, discount, taxRate, ... }. finalizeLines adds
// lineTotal and taxAmount and adds the voucher / sale discount to `discount`.
const { AppError } = require('../utils/errors');

// Money is handled in integer cents so totals always add up exactly.
const toCents = (n) => Math.round(Number(n) * 100);
const fromCents = (c) => c / 100;

// Spreads `cents` over lines in proportion to `weights` (cents), giving rounding leftovers to the
// largest line so the parts always add up exactly.
const allocate = (cents, weights) => {
    const total = weights.reduce((s, w) => s + w, 0);
    if (cents <= 0 || total <= 0) return weights.map(() => 0);
    const parts = weights.map((w) => Math.floor((cents * w) / total));
    const largest = weights.indexOf(Math.max(...weights));
    parts[largest] += cents - parts.reduce((s, p) => s + p, 0);
    return parts;
};

// Each line's total in cents before voucher and sale discounts (line discounts already taken off).
const grossCents = (lines) => lines.map((l) => toCents(l.qty * l.unitPrice) - toCents(l.discount));

// What a voucher takes off: { cents, eligible } where eligible is each line's share it applies to,
// or null when nothing in the cart qualifies (product / category vouchers).
const voucherShare = (voucher, lines, gross = grossCents(lines)) => {
    const eligible = lines.map((l, i) => {
        if (!voucher.target_type || voucher.target_id === null) return gross[i];
        if (voucher.target_type === 'product') return Number(voucher.target_id) === l.variantId ? gross[i] : 0;
        return Number(voucher.target_id) === l.categoryId ? gross[i] : 0;
    });
    const eligibleTotal = eligible.reduce((s, c) => s + c, 0);
    if (eligibleTotal === 0) return null;
    const cents = voucher.discount_type === 'percent'
        ? Math.round(eligibleTotal * Math.min(Number(voucher.discount_value), 100) / 100)
        : Math.min(toCents(voucher.discount_value), eligibleTotal);
    return { cents, eligible };
};

// Applies voucher / sale-level discount, then line totals and the tax inside them. Changes `lines`.
const finalizeLines = (lines, { voucher, saleDiscount, taxSettings }) => {
    const gross = grossCents(lines);

    let voucherCents = 0;
    if (voucher) {
        const share = voucherShare(voucher, lines, gross);
        if (!share) throw new AppError('Voucher tidak berlaku untuk barang di keranjang');
        voucherCents = share.cents;
        allocate(voucherCents, share.eligible).forEach((c, i) => { gross[i] -= c; lines[i].discount += fromCents(c); });
    }
    const manualCents = Math.min(toCents(saleDiscount || 0), gross.reduce((s, c) => s + c, 0));
    allocate(manualCents, [...gross]).forEach((c, i) => { gross[i] -= c; lines[i].discount += fromCents(c); });

    for (const [i, line] of lines.entries()) {
        let total = gross[i];
        let tax;
        if (taxSettings.inclusive) {
            tax = Math.round(total * line.taxRate / (100 + line.taxRate));
        } else {
            tax = Math.round(total * line.taxRate / 100);
            total += tax;
        }
        line.lineTotal = fromCents(total);
        line.taxAmount = fromCents(tax);
        line.discount = Math.round(line.discount * 100) / 100;
    }
    return { voucherDiscount: fromCents(voucherCents), manualDiscount: fromCents(manualCents) };
};

const grandCentsOf = (lines) => lines.reduce((s, l) => s + toCents(l.lineTotal), 0);

// Finalizes copies of `priced` with `extraCents` more sale-level discount; `priced` is untouched.
const finalizeCopy = (priced, opts, extraCents = 0) => {
    const lines = priced.map((l) => ({ ...l, unitIds: [...(l.unitIds || [])] }));
    finalizeLines(lines, { ...opts, saleDiscount: (opts.saleDiscount || 0) + fromCents(extraCents) });
    return lines;
};

// For a sale that already happened (offline): when the customer paid less than the cart now
// comes to (a price went up, a voucher no longer gives as much), the difference is recorded as an
// extra discount, so the books show what was really received. Returns the finalized lines and the
// smallest extra discount (cents) that brings the total down to `paidCents`.
const fitToPaid = (priced, opts, paidCents) => {
    const lines = finalizeCopy(priced, opts);
    const grand = grandCentsOf(lines);
    if (grand <= paidCents) return { lines, extraCents: 0 };
    // Discounting the whole total always fits; search for the smallest discount that does.
    let lo = 0;
    let hi = grand;
    while (lo < hi) {
        const mid = Math.floor((lo + hi) / 2);
        if (grandCentsOf(finalizeCopy(priced, opts, mid)) <= paidCents) hi = mid;
        else lo = mid + 1;
    }
    return { lines: finalizeCopy(priced, opts, lo), extraCents: lo };
};

module.exports = { toCents, fromCents, allocate, grossCents, voucherShare, finalizeLines, finalizeCopy, fitToPaid, grandCentsOf };
