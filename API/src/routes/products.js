const express = require('express');
const pool = require('../db');
const { authenticateToken, requireRole, filterByBranch } = require('../middleware/auth');
const { uploadProduct, deleteFile } = require('../utils/upload');

const router = express.Router();

// Apply authentication to all routes
router.use(authenticateToken);

// Get all products (with branch filtering)
router.get('/', filterByBranch, async (req, res) => {
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

// Create new product (admin/superadmin only, with branch filtering)
router.post('/', requireRole(['admin', 'superadmin']), filterByBranch, uploadProduct.single('product_image'), async (req, res) => {
    try {
        const { name, barcode, category_id, sell_price, stock, branch_id } = req.body;

        if (!name || !sell_price) {
            // Delete uploaded file if validation fails
            if (req.file) {
                deleteFile(`uploads/products/${req.file.filename}`);
            }
            return res.status(400).json({ 
                error: 'Name and sell price are required' 
            });
        }

        // Generate random barcode if not provided
        let productBarcode = barcode;
        if (!productBarcode || productBarcode.trim() === '') {
            productBarcode = 'GG' + Date.now() + Math.floor(Math.random() * 1000);
        }

        // Get image filename if uploaded
        const productImage = req.file ? req.file.filename : null;

        const [result] = await pool.execute(
            `INSERT INTO products (name, barcode, category_id, sell_price, stock, product_image, branch_id) 
             VALUES (?, ?, ?, ?, ?, ?, ?)`,
            [name, productBarcode, category_id || null, sell_price, stock || 0, productImage, branch_id]
        );

        // Get the created product
        const [products] = await pool.execute(
            `SELECT p.*, c.name as category_name, b.name as branch_name 
             FROM products p 
             LEFT JOIN categories c ON p.category_id = c.id 
             LEFT JOIN branches b ON p.branch_id = b.id 
             WHERE p.id = ?`,
            [result.insertId]
        );

        // Emit real-time event
        const io = req.app.get('io');
        if (io) {
            // Emit to specific branch
            io.to(`branch-${branch_id}`).emit('product-created', products[0]);
            // Emit to all branches (for superadmin)
            io.to('branch-0').emit('product-created', products[0]);
        }

        res.status(201).json({ 
            message: 'Product created successfully',
            productId: result.insertId,
            product: products[0]
        });

    } catch (error) {
        // Delete uploaded file if error occurs
        if (req.file) {
            deleteFile(`uploads/products/${req.file.filename}`);
        }
        
        console.error('Create product error:', error);
        if (error.code === 'ER_DUP_ENTRY') {
            res.status(400).json({ error: 'Barcode already exists' });
        } else {
            res.status(500).json({ error: 'Failed to create product' });
        }
    }
});

// Update product (admin/superadmin only, with branch filtering)
router.put('/:id', requireRole(['admin', 'superadmin']), filterByBranch, uploadProduct.single('product_image'), async (req, res) => {
    try {
        const { name, barcode, category_id, sell_price, stock, branch_id } = req.body;

        // Get old product data to delete old image if new one is uploaded
        const [oldProducts] = await pool.execute(
            'SELECT product_image FROM products WHERE id = ?',
            [req.params.id]
        );

        if (oldProducts.length === 0) {
            if (req.file) {
                deleteFile(`uploads/products/${req.file.filename}`);
            }
            return res.status(404).json({ error: 'Product not found' });
        }

        // Get image filename if uploaded, otherwise keep old one
        const productImage = req.file ? req.file.filename : oldProducts[0].product_image;

        const [result] = await pool.execute(
            `UPDATE products 
             SET name = ?, barcode = ?, category_id = ?, sell_price = ?, stock = ?, product_image = ?, branch_id = ?, updated_at = NOW()
             WHERE id = ?`,
            [name, barcode, category_id || null, sell_price, stock, productImage, branch_id, req.params.id]
        );

        if (result.affectedRows === 0) {
            if (req.file) {
                deleteFile(`uploads/products/${req.file.filename}`);
            }
            return res.status(404).json({ error: 'Product not found' });
        }

        // Delete old image if new one was uploaded
        if (req.file && oldProducts[0].product_image) {
            deleteFile(`uploads/products/${oldProducts[0].product_image}`);
        }

        // Get the updated product
        const [products] = await pool.execute(
            `SELECT p.*, c.name as category_name, b.name as branch_name 
             FROM products p 
             LEFT JOIN categories c ON p.category_id = c.id 
             LEFT JOIN branches b ON p.branch_id = b.id 
             WHERE p.id = ?`,
            [req.params.id]
        );

        // Emit real-time event
        const io = req.app.get('io');
        if (io && products.length > 0) {
            // Emit to specific branch
            io.to(`branch-${branch_id}`).emit('product-updated', products[0]);
            // Emit to all branches (for superadmin)
            io.to('branch-0').emit('product-updated', products[0]);
        }

        res.json({ 
            message: 'Product updated successfully',
            product: products[0]
        });

    } catch (error) {
        if (req.file) {
            deleteFile(`uploads/products/${req.file.filename}`);
        }
        
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
        // Get product info before deletion
        const [products] = await pool.execute(
            'SELECT id, branch_id, product_image FROM products WHERE id = ?',
            [req.params.id]
        );

        if (products.length === 0) {
            return res.status(404).json({ error: 'Product not found' });
        }

        const product = products[0];

        const [result] = await pool.execute(
            'DELETE FROM products WHERE id = ?',
            [req.params.id]
        );

        if (result.affectedRows === 0) {
            return res.status(404).json({ error: 'Product not found' });
        }

        // Delete product image if exists
        if (product.product_image) {
            deleteFile(`uploads/products/${product.product_image}`);
        }

        // Emit real-time event
        const io = req.app.get('io');
        if (io) {
            // Emit to specific branch
            io.to(`branch-${product.branch_id}`).emit('product-deleted', { id: req.params.id });
            // Emit to all branches (for superadmin)
            io.to('branch-0').emit('product-deleted', { id: req.params.id });
        }

        res.json({ message: 'Product deleted successfully' });

    } catch (error) {
        console.error('Delete product error:', error);
        res.status(500).json({ error: 'Failed to delete product' });
    }
});

module.exports = router;