const express = require('express');
const pool = require('../db');
const { authenticateToken, requireRole, filterByBranch } = require('../middleware/auth');
const { uploadProduct, deleteFile, validateUploadedImage } = require('../utils/upload');
const { broadcastToRoom, broadcastToEntity } = require('../utils/socket_broadcast');

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
            WHERE p.is_deleted = 0
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
        res.status(500).json({ error: 'Gagal mengambil data produk' });
    }
});

// Get product by ID (with branch validation)
router.get('/:id', async (req, res) => {
    try {
        const [products] = await pool.execute(
            `SELECT p.*, c.name as category_name, b.name as branch_name 
             FROM products p 
             LEFT JOIN categories c ON p.category_id = c.id 
             LEFT JOIN branches b ON p.branch_id = b.id 
             WHERE p.id = ? AND p.is_deleted = 0`,
            [req.params.id]
        );

        if (products.length === 0) {
            return res.status(404).json({ error: 'Produk tidak ditemukan' });
        }

        // Check branch ownership for non-superadmin users
        if (req.user.role !== 'superadmin') {
            if (products[0].branch_id !== req.user.branch_id) {
                return res.status(403).json({ 
                    error: 'Anda hanya dapat melihat produk dari cabang Anda sendiri' 
                });
            }
        }

        res.json({ product: products[0] });

    } catch (error) {
        console.error('Get product error:', error);
        res.status(500).json({ error: 'Gagal mengambil data produk' });
    }
});

// Create new product (admin/superadmin only, with branch filtering)
router.post('/', requireRole(['admin', 'superadmin']), filterByBranch, uploadProduct.single('product_image'), async (req, res) => {
    try {
        console.log('[POST /api/products] body:', req.body);
        console.log('[POST /api/products] file:', req.file ? {
            fieldname: req.file.fieldname,
            originalname: req.file.originalname,
            mimetype: req.file.mimetype,
            size: req.file.size,
            path: req.file.path,
            filename: req.file.filename,
        } : 'no file');

        const { name, barcode, category_id, sell_price, stock } = req.body;
        // For multipart requests, filterByBranch can't inject branch_id before multer runs.
        // Fall back to req.userBranchId (set by filterByBranch for non-superadmin users).
        const branch_id = req.body.branch_id || req.userBranchId;

        if (!name || !sell_price) {
            // Delete uploaded file if validation fails
            if (req.file) {
                deleteFile(`API/uploads/products/${req.file.filename}`);
            }
            return res.status(400).json({ 
                error: 'Nama produk dan harga jual wajib diisi' 
            });
        }

        // Validate uploaded image (magic number check)
        if (req.file) {
            try {
                const filePath = req.file.path;
                console.log('[POST /api/products] validating image at path:', filePath);
                validateUploadedImage(filePath, req.file.mimetype);
                console.log('[POST /api/products] image validation passed');
            } catch (error) {
                console.error('[POST /api/products] image validation failed:', error.message);
                return res.status(400).json({ 
                    error: error.message || 'File gambar tidak valid' 
                });
            }
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

        // Emit real-time event — branch room + entity-products subscribers
        const io = req.app.get('io');
        broadcastToRoom(io, branch_id, 'product-created', products[0]);
        broadcastToEntity(io, 'products', 'product-created', products[0], branch_id);

        res.status(201).json({ 
            message: 'Produk berhasil ditambahkan',
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
            res.status(400).json({ error: 'Barcode sudah digunakan' });
        } else {
            res.status(500).json({ error: 'Gagal menambahkan produk' });
        }
    }
});

// Update product (admin/superadmin only, with branch filtering and ownership validation)
router.put('/:id', requireRole(['admin', 'superadmin']), filterByBranch, uploadProduct.single('product_image'), async (req, res) => {
    try {
        const { name, barcode, category_id, sell_price, stock } = req.body;
        const branch_id = req.body.branch_id || req.userBranchId;

        // Get old product data to verify ownership and delete old image if new one is uploaded
        const [oldProducts] = await pool.execute(
            'SELECT branch_id, product_image FROM products WHERE id = ? AND is_deleted = 0',
            [req.params.id]
        );

        if (oldProducts.length === 0) {
            if (req.file) {
                deleteFile(`API/uploads/products/${req.file.filename}`);
            }
            return res.status(404).json({ error: 'Produk tidak ditemukan' });
        }

        // Check branch ownership for non-superadmin users
        if (req.user.role !== 'superadmin') {
            if (oldProducts[0].branch_id !== req.user.branch_id) {
                if (req.file) {
                    deleteFile(`API/uploads/products/${req.file.filename}`);
                }
                return res.status(403).json({ 
                    error: 'Anda hanya dapat mengubah produk dari cabang Anda sendiri' 
                });
            }
        }

        // Validate uploaded image (magic number check)
        if (req.file) {
            try {
                const filePath = `API/uploads/products/${req.file.filename}`;
                validateUploadedImage(filePath, req.file.mimetype);
            } catch (error) {
                return res.status(400).json({ 
                    error: error.message || 'File gambar tidak valid' 
                });
            }
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
            return res.status(404).json({ error: 'Produk tidak ditemukan' });
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

        // Emit real-time event — branch room + entity-products subscribers
        const io = req.app.get('io');
        if (products.length > 0) {
            broadcastToRoom(io, branch_id, 'product-updated', products[0]);
            broadcastToEntity(io, 'products', 'product-updated', products[0], branch_id);
        }

        res.json({ 
            message: 'Produk berhasil diperbarui',
            product: products[0]
        });

    } catch (error) {
        if (req.file) {
            deleteFile(`uploads/products/${req.file.filename}`);
        }
        
        console.error('Update product error:', error);
        if (error.code === 'ER_DUP_ENTRY') {
            res.status(400).json({ error: 'Barcode sudah digunakan' });
        } else {
            res.status(500).json({ error: 'Gagal memperbarui produk' });
        }
    }
});

// Delete product (superadmin only)
// Uses soft-delete (is_deleted=1) to preserve transaction history integrity.
// Falls back to hard-delete only when the product has no transaction history.
router.delete('/:id', requireRole(['superadmin']), async (req, res) => {
    try {
        // Get product info before deletion
        const [products] = await pool.execute(
            'SELECT id, branch_id, product_image FROM products WHERE id = ? AND is_deleted = 0',
            [req.params.id]
        );

        if (products.length === 0) {
            return res.status(404).json({ error: 'Produk tidak ditemukan' });
        }

        const product = products[0];

        // Check if product has any transaction history
        const [[{ txCount }]] = await pool.execute(
            'SELECT COUNT(*) AS txCount FROM transaction_items WHERE product_id = ?',
            [req.params.id]
        );

        if (parseInt(txCount) > 0) {
            // Soft delete — preserve transaction history
            await pool.execute(
                'UPDATE products SET is_deleted = 1, updated_at = NOW() WHERE id = ?',
                [req.params.id]
            );
        } else {
            // No transaction history — safe to hard delete
            await pool.execute('DELETE FROM products WHERE id = ?', [req.params.id]);

            // Delete product image only on hard delete
            if (product.product_image) {
                deleteFile(`uploads/products/${product.product_image}`);
            }
        }

        // Emit real-time event — branch room + entity-products subscribers
        const io = req.app.get('io');
        broadcastToRoom(io, product.branch_id, 'product-deleted', { id: req.params.id, branch_id: product.branch_id });
        broadcastToEntity(io, 'products', 'product-deleted', { id: req.params.id, branch_id: product.branch_id }, product.branch_id);

        res.json({ message: 'Produk berhasil dihapus' });

    } catch (error) {
        console.error('Delete product error:', error);
        res.status(500).json({ error: 'Gagal menghapus produk' });
    }
});

module.exports = router;
