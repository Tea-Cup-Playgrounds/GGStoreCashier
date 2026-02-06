const express = require('express');
const pool = require('../db');
const { authenticateToken, requireRole } = require('../middleware/auth');

const router = express.Router();

// Apply authentication to all routes
router.use(authenticateToken);

// Get all products
router.get('/', async (req, res) => {
    try {
        const { branch_id, category_id, search } = req.query;
        
        let query = `
            SELECT p.*, c.name as category_name, b.name as branch_name 
            FROM products p 
            LEFT JOIN categories c ON p.category_id = c.id 
            LEFT JOIN branches b ON p.branch_id = b.id 
            WHERE 1=1
        `;
        const params = [];

        if (branch_id && branch_id !== '0') {
            query += ' AND p.branch_id = ?';
            params.push(branch_id);
        }

        if (category_id) {
            query += ' AND p.category_id = ?';
            params.push(category_id);
        }

        if (search) {
            query += ' AND (p.name LIKE ? OR p.barcode LIKE ?)';
            params.push(`%${search}%`, `%${search}%`);
        }

        query += ' ORDER BY p.created_at DESC';

        const [products] = await pool.execute(query, params);
        res.json({ products });

    } catch (error) {
        console.error('Get products error:', error);
        res.status(500).json({ error: 'Failed to fetch products' });
    }
});

// Get product by ID
router.get('/:id', async (req, res) => {
    try {
        const [products] = await pool.execute(
            `SELECT p.*, c.name as category_name, b.name as branch_name 
             FROM products p 
             LEFT JOIN categories c ON p.category_id = c.id 
             LEFT JOIN branches b ON p.branch_id = b.id 
             WHERE p.id = ?`,
            [req.params.id]
        );

        if (products.length === 0) {
            return res.status(404).json({ error: 'Product not found' });
        }

        res.json({ product: products[0] });

    } catch (error) {
        console.error('Get product error:', error);
        res.status(500).json({ error: 'Failed to fetch product' });
    }
});

// Create new product (admin/superadmin only)
router.post('/', requireRole(['admin', 'superadmin']), async (req, res) => {
    try {
        const { name, barcode, category_id, sell_price, stock, branch_id } = req.body;

        if (!name || !sell_price) {
            return res.status(400).json({ 
                error: 'Name and sell price are required' 
            });
        }

        const [result] = await pool.execute(
            `INSERT INTO products (name, barcode, category_id, sell_price, stock, branch_id) 
             VALUES (?, ?, ?, ?, ?, ?)`,
            [name, barcode, category_id, sell_price, stock || 0, branch_id]
        );

        res.status(201).json({ 
            message: 'Product created successfully',
            productId: result.insertId 
        });

    } catch (error) {
        console.error('Create product error:', error);
        if (error.code === 'ER_DUP_ENTRY') {
            res.status(400).json({ error: 'Barcode already exists' });
        } else {
            res.status(500).json({ error: 'Failed to create product' });
        }
    }
});

// Update product (admin/superadmin only)
router.put('/:id', requireRole(['admin', 'superadmin']), async (req, res) => {
    try {
        const { name, barcode, category_id, sell_price, stock, branch_id } = req.body;

        const [result] = await pool.execute(
            `UPDATE products 
             SET name = ?, barcode = ?, category_id = ?, sell_price = ?, stock = ?, branch_id = ?, updated_at = NOW()
             WHERE id = ?`,
            [name, barcode, category_id, sell_price, stock, branch_id, req.params.id]
        );

        if (result.affectedRows === 0) {
            return res.status(404).json({ error: 'Product not found' });
        }

        res.json({ message: 'Product updated successfully' });

    } catch (error) {
        console.error('Update product error:', error);
        if (error.code === 'ER_DUP_ENTRY') {
            res.status(400).json({ error: 'Barcode already exists' });
        } else {
            res.status(500).json({ error: 'Failed to update product' });
        }
    }
});

// Delete product (superadmin only)
router.delete('/:id', requireRole(['superadmin']), async (req, res) => {
    try {
        const [result] = await pool.execute(
            'DELETE FROM products WHERE id = ?',
            [req.params.id]
        );

        if (result.affectedRows === 0) {
            return res.status(404).json({ error: 'Product not found' });
        }

        res.json({ message: 'Product deleted successfully' });

    } catch (error) {
        console.error('Delete product error:', error);
        res.status(500).json({ error: 'Failed to delete product' });
    }
});

module.exports = router;