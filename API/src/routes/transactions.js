const express = require('express');
const pool = require('../db');
const { authenticateToken, requireRole, filterByBranch } = require('../middleware/auth');
const stock = require('../services/stock');
const { DISPLAY_NAME_SQL, ACTIVE_VARIANT_SQL } = require('../services/catalog');
const { emitLegacyProduct } = require('../services/legacy-products');

const router = express.Router();

router.use(authenticateToken);

// GET /api/transactions — branch-enforced via filterByBranch middleware
router.get('/', filterByBranch, async (req, res) => {
    try {
        const { branch_id, user_id, payment_status, start_date, end_date } = req.query;

        let query = `
            SELECT t.*, u.name as user_name, b.name as branch_name
            FROM transactions t
            LEFT JOIN users u ON t.user_id = u.id
            LEFT JOIN branches b ON t.branch_id = b.id
            WHERE 1=1
        `;
        const params = [];

        if (branch_id && branch_id !== '0') {
            query += ' AND t.branch_id = ?';
            params.push(branch_id);
        }

        if (user_id) {
            query += ' AND t.user_id = ?';
            params.push(user_id);
        }

        if (payment_status) {
            query += ' AND t.payment_status = ?';
            params.push(payment_status);
        }

        if (start_date) {
            query += ' AND DATE(t.created_at) >= ?';
            params.push(start_date);
        }

        if (end_date) {
            query += ' AND DATE(t.created_at) <= ?';
            params.push(end_date);
        }

        query += ' ORDER BY t.created_at DESC';

        const [transactions] = await pool.execute(query, params);
        res.json({ transactions });

    } catch (error) {
        console.error('Get transactions error:', error);
        res.status(500).json({ error: 'Gagal mengambil data transaksi' });
    }
});

// GET /api/transactions/:id
router.get('/:id', async (req, res) => {
    try {
        const [transactions] = await pool.execute(
            `SELECT t.*, u.name as user_name, b.name as branch_name
             FROM transactions t
             LEFT JOIN users u ON t.user_id = u.id
             LEFT JOIN branches b ON t.branch_id = b.id
             WHERE t.id = ?`,
            [req.params.id]
        );

        if (transactions.length === 0) {
            return res.status(404).json({ error: 'Transaksi tidak ditemukan' });
        }

        // Enforce branch access for non-superadmin
        if (req.user.role !== 'superadmin' &&
            transactions[0].branch_id !== req.user.branch_id) {
            return res.status(403).json({ error: 'Akses ditolak' });
        }

        const [items] = await pool.execute(
            `SELECT ti.*, ${DISPLAY_NAME_SQL} as product_name, v.barcode
             FROM transaction_items ti
             LEFT JOIN product_variants v ON ti.product_id = v.id
             LEFT JOIN products p ON v.product_id = p.id
             WHERE ti.transaction_id = ?`,
            [req.params.id]
        );

        const [payments] = await pool.execute(
            'SELECT * FROM payments WHERE transaction_id = ?',
            [req.params.id]
        );

        res.json({ transaction: transactions[0], items, payments });

    } catch (error) {
        console.error('Get transaction error:', error);
        res.status(500).json({ error: 'Gagal mengambil data transaksi' });
    }
});

// POST /api/transactions
router.post('/', async (req, res) => {
    // Superadmin must supply a real branch_id in the body
    const branchId = Number(req.user.role === 'superadmin'
        ? req.body.branch_id
        : req.user.branch_id);

    if (!Number.isInteger(branchId) || branchId <= 0) {
        return res.status(400).json({
            error: 'branch_id wajib diisi untuk transaksi ini'
        });
    }

    const { items, discount = 0, payment_method, payment_amount } = req.body;

    if (!Array.isArray(items) || items.length === 0) {
        return res.status(400).json({ error: 'Item transaksi wajib diisi' });
    }

    // Validate all product_ids and quantities are positive integers
    for (const item of items) {
        item.product_id = Number(item.product_id);
        item.qty = Number(item.qty);
        if (!Number.isInteger(item.product_id) || item.product_id <= 0) {
            return res.status(400).json({ error: `ID produk tidak valid: ${item.product_id}` });
        }
        if (!Number.isInteger(item.qty) || item.qty <= 0) {
            return res.status(400).json({ error: `Jumlah tidak valid untuk produk ${item.product_id}` });
        }
    }

    const connection = await pool.getConnection();

    try {
        await connection.beginTransaction();

        if (!req.access.can('sales.create', branchId)) {
            await connection.rollback();
            return res.status(403).json({ error: 'Anda tidak memiliki izin berjualan di cabang ini' });
        }

        // product_id is a variant id (see services/legacy-products.js). Prices come from the
        // catalog at this branch, not from the client.
        for (const item of items) {
            const [rows] = await connection.execute(
                `SELECT v.id, ${DISPLAY_NAME_SQL} AS name, p.is_serialized, p.kind,
                        COALESCE(sl.sell_price, v.base_price) AS price
                 FROM product_variants v
                 JOIN products p ON p.id = v.product_id
                 LEFT JOIN stock_levels sl ON sl.variant_id = v.id AND sl.location_id = ?
                 WHERE v.id = ? AND ${ACTIVE_VARIANT_SQL}`,
                [branchId, item.product_id]
            );
            if (rows.length === 0) {
                await connection.rollback();
                return res.status(404).json({ error: `Produk dengan ID ${item.product_id} tidak ditemukan` });
            }
            if (rows[0].is_serialized) {
                await connection.rollback();
                return res.status(400).json({
                    error: `"${rows[0].name}" memakai IMEI/serial dan belum dapat dijual dari kasir ini`
                });
            }
            item.name = rows[0].name;
            item.price = Number(rows[0].price);
        }

        // Calculate totals
        let total_amount = 0;
        for (const item of items) {
            total_amount += item.qty * item.price;
        }
        const appliedDiscount = Math.min(Math.max(Number(discount) || 0, 0), total_amount);
        const final_amount = total_amount - appliedDiscount;

        // Insert transaction
        const [transactionResult] = await connection.execute(
            `INSERT INTO transactions (user_id, branch_id, total_amount, discount, final_amount, payment_status)
             VALUES (?, ?, ?, ?, ?, 'paid')`,
            [req.user.id, branchId, total_amount, appliedDiscount, final_amount]
        );
        const transactionId = transactionResult.insertId;

        // Insert items and deduct stock (StockService writes the movement)
        for (const item of items) {
            await connection.execute(
                `INSERT INTO transaction_items (transaction_id, product_id, qty, price, subtotal)
                 VALUES (?, ?, ?, ?, ?)`,
                [transactionId, item.product_id, item.qty, item.price, item.qty * item.price]
            );

            try {
                await stock.adjustQuantity(connection, { userId: req.user.id }, {
                    locationId: branchId, variantId: Number(item.product_id), qtyChange: -item.qty,
                    reason: 'sale', refType: 'transaction', refId: transactionId,
                });
            } catch (error) {
                if (!(error instanceof stock.StockError)) throw error;
                await connection.rollback();
                return res.status(error.status).json({ error: `"${item.name}": ${error.message}` });
            }
        }

        // Insert payment record
        if (payment_method && payment_amount) {
            await connection.execute(
                'INSERT INTO payments (transaction_id, method, amount) VALUES (?, ?, ?)',
                [transactionId, payment_method, payment_amount]
            );
        }

        // Fetch completed transaction for response + socket
        const [transactions] = await connection.execute(
            `SELECT t.*, u.name as user_name, b.name as branch_name
             FROM transactions t
             LEFT JOIN users u ON t.user_id = u.id
             LEFT JOIN branches b ON t.branch_id = b.id
             WHERE t.id = ?`,
            [transactionId]
        );

        await connection.commit();

        // Emit real-time events
        const io = req.app.get('io');
        if (io) {
            io.to(`branch-${branchId}`).emit('transaction-created', transactions[0]);
            io.to('branch-0').emit('transaction-created', transactions[0]);

            for (const item of items) {
                await emitLegacyProduct(req, 'product-updated', item.product_id, [branchId]);
            }

            io.to(`branch-${branchId}`).emit('payment-completed', {
                transactionId, method: payment_method, amount: payment_amount, branchId
            });
            io.to('branch-0').emit('payment-completed', {
                transactionId, method: payment_method, amount: payment_amount, branchId
            });
        }

        res.status(201).json({
            message: 'Transaksi berhasil dibuat',
            transactionId,
            transaction: transactions[0]
        });

    } catch (error) {
        await connection.rollback();
        console.error('Create transaction error:', error);
        res.status(500).json({ error: 'Gagal membuat transaksi' });
    } finally {
        connection.release();
    }
});

module.exports = router;
