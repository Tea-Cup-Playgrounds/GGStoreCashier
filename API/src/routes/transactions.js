const express = require('express');
const pool = require('../db');
const { authenticateToken, requireRole, filterByBranch } = require('../middleware/auth');

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
            `SELECT ti.*, p.name as product_name, p.barcode
             FROM transaction_items ti
             LEFT JOIN products p ON ti.product_id = p.id
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
    const branchId = req.user.role === 'superadmin'
        ? req.body.branch_id
        : req.user.branch_id;

    if (!branchId || branchId === 0) {
        return res.status(400).json({
            error: 'branch_id wajib diisi untuk transaksi ini'
        });
    }

    const connection = await pool.getConnection();

    try {
        await connection.beginTransaction();

        const { items, discount = 0, payment_method, payment_amount } = req.body;

        if (!items || items.length === 0) {
            return res.status(400).json({ error: 'Item transaksi wajib diisi' });
        }

        // Validate all product_ids are positive integers
        for (const item of items) {
            if (!item.product_id || item.product_id <= 0) {
                return res.status(400).json({ error: `ID produk tidak valid: ${item.product_id}` });
            }
            if (!item.qty || item.qty <= 0) {
                return res.status(400).json({ error: `Jumlah tidak valid untuk produk ${item.product_id}` });
            }
        }

        // Check stock availability for all items before touching anything
        for (const item of items) {
            const [rows] = await connection.execute(
                'SELECT stock, name FROM products WHERE id = ?',
                [item.product_id]
            );
            if (rows.length === 0) {
                await connection.rollback();
                return res.status(404).json({ error: `Produk dengan ID ${item.product_id} tidak ditemukan` });
            }
            if (rows[0].stock < item.qty) {
                await connection.rollback();
                return res.status(400).json({
                    error: `Stok "${rows[0].name}" tidak mencukupi. Tersedia: ${rows[0].stock}, diminta: ${item.qty}`
                });
            }
        }

        // Calculate totals
        let total_amount = 0;
        for (const item of items) {
            total_amount += item.qty * item.price;
        }
        const final_amount = total_amount - discount;

        // Insert transaction
        const [transactionResult] = await connection.execute(
            `INSERT INTO transactions (user_id, branch_id, total_amount, discount, final_amount, payment_status)
             VALUES (?, ?, ?, ?, ?, 'paid')`,
            [req.user.id, branchId, total_amount, discount, final_amount]
        );
        const transactionId = transactionResult.insertId;

        // Insert items, deduct stock, record movements
        const updatedProducts = [];
        for (const item of items) {
            await connection.execute(
                `INSERT INTO transaction_items (transaction_id, product_id, qty, price, subtotal)
                 VALUES (?, ?, ?, ?, ?)`,
                [transactionId, item.product_id, item.qty, item.price, item.qty * item.price]
            );

            await connection.execute(
                'UPDATE products SET stock = stock - ? WHERE id = ?',
                [item.qty, item.product_id]
            );

            const [products] = await connection.execute(
                `SELECT p.*, c.name as category_name, b.name as branch_name
                 FROM products p
                 LEFT JOIN categories c ON p.category_id = c.id
                 LEFT JOIN branches b ON p.branch_id = b.id
                 WHERE p.id = ?`,
                [item.product_id]
            );
            if (products.length > 0) updatedProducts.push(products[0]);

            await connection.execute(
                `INSERT INTO stock_movements (product_id, branch_id, type, qty, note)
                 VALUES (?, ?, 'out', ?, ?)`,
                [item.product_id, branchId, item.qty, `Sale - Transaction #${transactionId}`]
            );
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

            updatedProducts.forEach(product => {
                io.to(`branch-${product.branch_id}`).emit('product-updated', product);
                io.to('branch-0').emit('product-updated', product);
            });

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
