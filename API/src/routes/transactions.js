const express = require('express');
const pool = require('../db');
const { authenticateToken, requireRole } = require('../middleware/auth');

const router = express.Router();

// Apply authentication to all routes
router.use(authenticateToken);

// Get all transactions
router.get('/', async (req, res) => {
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
        res.status(500).json({ error: 'Failed to fetch transactions' });
    }
});

// Get transaction by ID with items
router.get('/:id', async (req, res) => {
    try {
        // Get transaction details
        const [transactions] = await pool.execute(
            `SELECT t.*, u.name as user_name, b.name as branch_name
             FROM transactions t 
             LEFT JOIN users u ON t.user_id = u.id 
             LEFT JOIN branches b ON t.branch_id = b.id 
             WHERE t.id = ?`,
            [req.params.id]
        );

        if (transactions.length === 0) {
            return res.status(404).json({ error: 'Transaction not found' });
        }

        // Get transaction items
        const [items] = await pool.execute(
            `SELECT ti.*, p.name as product_name, p.barcode
             FROM transaction_items ti 
             LEFT JOIN products p ON ti.product_id = p.id 
             WHERE ti.transaction_id = ?`,
            [req.params.id]
        );

        // Get payments
        const [payments] = await pool.execute(
            'SELECT * FROM payments WHERE transaction_id = ?',
            [req.params.id]
        );

        res.json({ 
            transaction: transactions[0],
            items,
            payments
        });

    } catch (error) {
        console.error('Get transaction error:', error);
        res.status(500).json({ error: 'Failed to fetch transaction' });
    }
});

// Create new transaction
router.post('/', async (req, res) => {
    const connection = await pool.getConnection();
    
    try {
        await connection.beginTransaction();

        const { items, discount = 0, payment_method, payment_amount } = req.body;

        if (!items || items.length === 0) {
            return res.status(400).json({ 
                error: 'Transaction items are required' 
            });
        }

        // Calculate total amount
        let total_amount = 0;
        for (const item of items) {
            total_amount += item.qty * item.price;
        }

        const final_amount = total_amount - discount;

        // Create transaction
        const [transactionResult] = await connection.execute(
            `INSERT INTO transactions (user_id, branch_id, total_amount, discount, final_amount, payment_status) 
             VALUES (?, ?, ?, ?, ?, ?)`,
            [req.user.id, req.user.branch_id, total_amount, discount, final_amount, 'paid']
        );

        const transactionId = transactionResult.insertId;

        // Add transaction items and update stock
        const updatedProducts = [];
        for (const item of items) {
            // Add transaction item
            await connection.execute(
                `INSERT INTO transaction_items (transaction_id, product_id, qty, price, subtotal) 
                 VALUES (?, ?, ?, ?, ?)`,
                [transactionId, item.product_id, item.qty, item.price, item.qty * item.price]
            );

            // Update product stock
            await connection.execute(
                'UPDATE products SET stock = stock - ? WHERE id = ?',
                [item.qty, item.product_id]
            );

            // Get updated product info
            const [products] = await connection.execute(
                `SELECT p.*, c.name as category_name, b.name as branch_name 
                 FROM products p 
                 LEFT JOIN categories c ON p.category_id = c.id 
                 LEFT JOIN branches b ON p.branch_id = b.id 
                 WHERE p.id = ?`,
                [item.product_id]
            );
            
            if (products.length > 0) {
                updatedProducts.push(products[0]);
            }

            // Add stock movement record
            await connection.execute(
                `INSERT INTO stock_movements (product_id, branch_id, type, qty, note) 
                 VALUES (?, ?, 'out', ?, ?)`,
                [item.product_id, req.user.branch_id, item.qty, `Sale - Transaction #${transactionId}`]
            );
        }

        // Add payment record
        if (payment_method && payment_amount) {
            await connection.execute(
                'INSERT INTO payments (transaction_id, method, amount) VALUES (?, ?, ?)',
                [transactionId, payment_method, payment_amount]
            );
        }

        // Get complete transaction data
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
            // Emit transaction created event
            io.to(`branch-${req.user.branch_id}`).emit('transaction-created', transactions[0]);
            io.to('branch-0').emit('transaction-created', transactions[0]);

            // Emit stock updates for each product
            updatedProducts.forEach(product => {
                io.to(`branch-${product.branch_id}`).emit('product-updated', product);
                io.to('branch-0').emit('product-updated', product);
            });

            // Emit payment event
            io.to(`branch-${req.user.branch_id}`).emit('payment-completed', {
                transactionId,
                method: payment_method,
                amount: payment_amount,
                branchId: req.user.branch_id
            });
            io.to('branch-0').emit('payment-completed', {
                transactionId,
                method: payment_method,
                amount: payment_amount,
                branchId: req.user.branch_id
            });
        }

        res.status(201).json({ 
            message: 'Transaction created successfully',
            transactionId,
            transaction: transactions[0]
        });

    } catch (error) {
        await connection.rollback();
        console.error('Create transaction error:', error);
        res.status(500).json({ error: 'Failed to create transaction' });
    } finally {
        connection.release();
    }
});

module.exports = router;