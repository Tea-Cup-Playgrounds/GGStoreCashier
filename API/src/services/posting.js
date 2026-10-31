const { postEntry, reverseSource, fromCents, toCents } = require('./journal');

// Posting rules: which accounts each business document debits and credits. Accounts are
// mapping keys (see account_mappings) or, for payment methods, the method's own account.
//
//   sale            Dr payment accounts (cash net of change)   Cr sales_* revenue (excl. PPN), ppn_output
//                   Dr cogs                                     Cr inventory            (goods at unit cost)
//   sale_return     the reverse of the returned part, refunded through one payment method;
//                   defective goods go to inventory_adjustment instead of back to inventory
//   goods_receipt   Dr inventory, ppn_input                     Cr accounts_payable
//   supplier_payment Dr accounts_payable                        Cr cash | bank
//   stock value     Dr/Cr inventory  vs  inventory_adjustment  (adjustments, opname, write-offs)
//   cash_session    cash over/short against cash_over_short

const REVENUE_KEY = { goods: 'sales_goods', service: 'sales_service', digital: 'sales_digital', fee: 'sales_service' };

const sumCents = (rows, pick) => rows.reduce((s, r) => s + toCents(pick(r)), 0);

const postSale = async (conn, ctx, saleId) => {
    const [[sale]] = await conn.execute('SELECT * FROM sales WHERE id = ?', [saleId]);
    const [lines] = await conn.execute('SELECT line_type, qty, line_total, tax_amount, unit_cost FROM sale_lines WHERE sale_id = ?', [saleId]);
    const [payments] = await conn.execute(
        `SELECT sp.amount, pm.type, pm.account_id FROM sale_payments sp JOIN payment_methods pm ON pm.id = sp.payment_method_id
         WHERE sp.sale_id = ?`,
        [saleId]
    );

    // Change is handed back from the cash drawer, so it reduces the cash received.
    let changeLeft = toCents(sale.change_total);
    const debitLines = payments.map((p) => {
        let cents = toCents(p.amount);
        if (p.type === 'cash' && changeLeft > 0) {
            const used = Math.min(changeLeft, cents);
            cents -= used;
            changeLeft -= used;
        }
        return { account: p.account_id, debit: fromCents(cents), memo: 'Pembayaran' };
    });

    const revenueByKey = {};
    for (const l of lines) {
        const key = REVENUE_KEY[l.line_type] || 'sales_goods';
        revenueByKey[key] = (revenueByKey[key] || 0) + toCents(l.line_total) - toCents(l.tax_amount);
    }
    const taxCents = sumCents(lines, (l) => l.tax_amount);
    const costCents = lines.filter((l) => l.line_type === 'goods').reduce((s, l) => s + Math.round(toCents(l.unit_cost) * l.qty), 0);

    return postEntry(conn, ctx, {
        date: sale.occurred_at,
        locationId: sale.location_id,
        sourceType: 'sale',
        sourceId: sale.id,
        memo: `Penjualan ${sale.number}`,
        lines: [
            ...debitLines,
            ...Object.entries(revenueByKey).map(([key, cents]) => ({ account: key, credit: fromCents(cents) })),
            { account: 'ppn_output', credit: fromCents(taxCents) },
            { account: 'cogs', debit: fromCents(costCents) },
            { account: 'inventory', credit: fromCents(costCents) },
        ],
    });
};

const voidSaleJournal = (conn, ctx, sale, reason) =>
    reverseSource(conn, ctx, { sourceType: 'sale', sourceId: sale.id, reversalSourceType: 'sale_void', memo: `Pembatalan ${sale.number}: ${reason}` });

const postSaleReturn = async (conn, ctx, returnId) => {
    const [[ret]] = await conn.execute(
        `SELECT r.*, pm.account_id AS refund_account, s.number AS sale_number
         FROM sale_returns r JOIN payment_methods pm ON pm.id = r.refund_method_id JOIN sales s ON s.id = r.sale_id
         WHERE r.id = ?`,
        [returnId]
    );
    const [lines] = await conn.execute(
        `SELECT rl.qty, rl.amount, rl.tax_amount, rl.unit_cost, rl.restock, sl.line_type
         FROM sale_return_lines rl JOIN sale_lines sl ON sl.id = rl.sale_line_id WHERE rl.return_id = ?`,
        [returnId]
    );

    const revenueByKey = {};
    for (const l of lines) {
        const key = REVENUE_KEY[l.line_type] || 'sales_goods';
        revenueByKey[key] = (revenueByKey[key] || 0) + toCents(l.amount) - toCents(l.tax_amount);
    }
    const goods = lines.filter((l) => l.line_type === 'goods');
    const restockCents = goods.filter((l) => l.restock).reduce((s, l) => s + Math.round(toCents(l.unit_cost) * l.qty), 0);
    const defectiveCents = goods.filter((l) => !l.restock).reduce((s, l) => s + Math.round(toCents(l.unit_cost) * l.qty), 0);

    return postEntry(conn, ctx, {
        date: ret.created_at,
        locationId: ret.location_id,
        sourceType: 'sale_return',
        sourceId: ret.id,
        memo: `Retur ${ret.number} atas ${ret.sale_number}`,
        lines: [
            ...Object.entries(revenueByKey).map(([key, cents]) => ({ account: key, debit: fromCents(cents) })),
            { account: 'ppn_output', debit: ret.tax_total },
            { account: ret.refund_account, credit: ret.refund_total, memo: 'Pengembalian dana' },
            { account: 'inventory', debit: fromCents(restockCents) },
            { account: 'inventory_adjustment', debit: fromCents(defectiveCents), memo: 'Barang retur rusak' },
            { account: 'cogs', credit: fromCents(restockCents + defectiveCents) },
        ],
    });
};

const postGoodsReceipt = async (conn, ctx, receiptId) => {
    const [[r]] = await conn.execute('SELECT * FROM goods_receipts WHERE id = ?', [receiptId]);
    return postEntry(conn, ctx, {
        date: r.posted_at || r.created_at,
        locationId: r.location_id,
        sourceType: 'goods_receipt',
        sourceId: r.id,
        memo: `Penerimaan ${r.number}${r.invoice_no ? ` (faktur ${r.invoice_no})` : ''}`,
        lines: [
            { account: 'inventory', debit: r.subtotal },
            { account: 'ppn_input', debit: r.tax_total },
            { account: 'accounts_payable', credit: r.grand_total },
        ],
    });
};

const postSupplierPayment = async (conn, ctx, paymentId) => {
    const [[p]] = await conn.execute(
        `SELECT sp.*, r.location_id, r.number AS receipt_number FROM supplier_payments sp
         LEFT JOIN goods_receipts r ON r.id = sp.receipt_id WHERE sp.id = ?`,
        [paymentId]
    );
    return postEntry(conn, ctx, {
        date: p.paid_at,
        locationId: p.location_id,
        sourceType: 'supplier_payment',
        sourceId: p.id,
        memo: `Pembayaran supplier${p.receipt_number ? ` untuk ${p.receipt_number}` : ''}`,
        lines: [
            { account: 'accounts_payable', debit: p.amount },
            { account: p.method === 'cash' ? 'cash' : 'bank', credit: p.amount },
        ],
    });
};

// A change in stock value not caused by buying or selling. value > 0 adds inventory.
const postStockValue = async (conn, ctx, { sourceType, sourceId, locationId, value, memo }) => {
    const cents = toCents(value);
    if (cents === 0) return null;
    const amount = fromCents(Math.abs(cents));
    return postEntry(conn, ctx, {
        locationId,
        sourceType,
        sourceId,
        memo,
        lines: cents > 0
            ? [{ account: 'inventory', debit: amount }, { account: 'inventory_adjustment', credit: amount }]
            : [{ account: 'inventory_adjustment', debit: amount }, { account: 'inventory', credit: amount }],
    });
};

// Value of the stock movements written for a document (sum of qty_change * unit_cost).
const movementValue = async (conn, refType, refId) => {
    const [[row]] = await conn.execute(
        'SELECT COALESCE(SUM(qty_change * unit_cost), 0) AS value FROM stock_movements WHERE ref_type = ? AND ref_id = ?',
        [refType, String(refId)]
    );
    return Number(row.value);
};

const postCashSessionClose = async (conn, ctx, sessionId) => {
    const [[s]] = await conn.execute('SELECT * FROM cash_sessions WHERE id = ?', [sessionId]);
    const cents = toCents(s.difference || 0);
    if (cents === 0) return null;
    const amount = fromCents(Math.abs(cents));
    return postEntry(conn, ctx, {
        date: s.closed_at,
        locationId: s.location_id,
        sourceType: 'cash_session',
        sourceId: s.id,
        memo: cents > 0 ? 'Kelebihan kas saat tutup shift' : 'Kekurangan kas saat tutup shift',
        lines: cents > 0
            ? [{ account: 'cash', debit: amount }, { account: 'cash_over_short', credit: amount }]
            : [{ account: 'cash_over_short', debit: amount }, { account: 'cash', credit: amount }],
    });
};

module.exports = {
    postSale,
    voidSaleJournal,
    postSaleReturn,
    postGoodsReceipt,
    postSupplierPayment,
    postStockValue,
    movementValue,
    postCashSessionClose,
};
