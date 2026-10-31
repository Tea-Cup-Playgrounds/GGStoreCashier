// Posts journal entries for documents recorded before the accounting core existed: posted goods
// receipts, supplier payments, sales (including ones migrated from the old transactions table)
// and sale returns. Safe to run repeatedly: documents that already have an entry are skipped.
//
//   npm run accounting:backfill
require('dotenv').config({ path: require('path').resolve(__dirname, '../../.env') });
const pool = require('../src/db');
const posting = require('../src/services/posting');
const { hasEntry } = require('../src/services/journal');

const SOURCES = [
    ['goods_receipt', "SELECT id FROM goods_receipts WHERE status = 'posted' ORDER BY posted_at", posting.postGoodsReceipt],
    ['supplier_payment', 'SELECT id FROM supplier_payments ORDER BY paid_at, created_at', posting.postSupplierPayment],
    ['sale', 'SELECT id FROM sales ORDER BY occurred_at', posting.postSale],
    ['sale_return', 'SELECT id FROM sale_returns ORDER BY created_at', posting.postSaleReturn],
];

(async () => {
    const ctx = { userId: null };
    let total = 0;
    try {
        for (const [sourceType, query, post] of SOURCES) {
            const [rows] = await pool.execute(query);
            let posted = 0;
            for (const { id } of rows) {
                if (await hasEntry(pool, sourceType, id)) continue;
                const conn = await pool.getConnection();
                try {
                    await conn.beginTransaction();
                    await post(conn, ctx, id);
                    await conn.commit();
                    posted += 1;
                } catch (error) {
                    await conn.rollback();
                    console.error(`  ${sourceType} ${id}: ${error.message}`);
                } finally {
                    conn.release();
                }
            }
            console.log(`${sourceType}: ${posted} jurnal dibuat (${rows.length} dokumen diperiksa)`);
            total += posted;
        }
        // Voided sales need their reversal too.
        const [voided] = await pool.execute("SELECT * FROM sales WHERE status = 'voided'");
        for (const sale of voided) {
            if (await hasEntry(pool, 'sale_void', sale.id)) continue;
            const conn = await pool.getConnection();
            try {
                await conn.beginTransaction();
                await posting.voidSaleJournal(conn, ctx, sale, sale.void_reason || 'backfill');
                await conn.commit();
                total += 1;
            } catch (error) {
                await conn.rollback();
                console.error(`  sale_void ${sale.id}: ${error.message}`);
            } finally {
                conn.release();
            }
        }
        console.log(`Selesai: ${total} jurnal dibuat.`);
    } finally {
        await pool.end();
    }
})();
