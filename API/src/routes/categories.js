const express = require('express');
const pool = require('../db');
const { authenticateToken, requireRole } = require('../middleware/auth');
const { uploadCategory, deleteFile } = require('../utils/upload');

const router = express.Router();

// Apply authentication to all routes
router.use(authenticateToken);

// Get all categories
router.get('/', async (req, res) => {
    try {
        const [categories] = await pool.execute(
            'SELECT * FROM categories ORDER BY name ASC'
        );
        res.json({ categories });

    } catch (error) {
        console.error('Get categories error:', error);
        res.status(500).json({ error: 'Failed to fetch categories' });
    }
});

// Get category by ID
router.get('/:id', async (req, res) => {
    try {
        const [categories] = await pool.execute(
            'SELECT * FROM categories WHERE id = ?',
            [req.params.id]
        );

        if (categories.length === 0) {
            return res.status(404).json({ error: 'Category not found' });
        }

        res.json({ category: categories[0] });

    } catch (error) {
        console.error('Get category error:', error);
        res.status(500).json({ error: 'Failed to fetch category' });
    }
});

// Create new category (admin/superadmin only)
router.post('/', requireRole(['admin', 'superadmin']), uploadCategory.single('category_image'), async (req, res) => {
    try {
        const { name, description } = req.body;

        if (!name) {
            if (req.file) {
                deleteFile(`uploads/categories/${req.file.filename}`);
            }
            return res.status(400).json({ 
                error: 'Category name is required' 
            });
        }

        const categoryImage = req.file ? req.file.filename : null;

        const [result] = await pool.execute(
            'INSERT INTO categories (name, description, category_image) VALUES (?, ?, ?)',
            [name, description, categoryImage]
        );

        // Get the created category
        const [categories] = await pool.execute(
            'SELECT * FROM categories WHERE id = ?',
            [result.insertId]
        );

        res.status(201).json({ 
            message: 'Category created successfully',
            categoryId: result.insertId,
            category: categories[0]
        });

    } catch (error) {
        if (req.file) {
            deleteFile(`uploads/categories/${req.file.filename}`);
        }
        console.error('Create category error:', error);
        res.status(500).json({ error: 'Failed to create category' });
    }
});

// Update category (admin/superadmin only)
router.put('/:id', requireRole(['admin', 'superadmin']), uploadCategory.single('category_image'), async (req, res) => {
    try {
        const { name, description } = req.body;

        if (!name) {
            if (req.file) {
                deleteFile(`uploads/categories/${req.file.filename}`);
            }
            return res.status(400).json({ 
                error: 'Category name is required' 
            });
        }

        // Get old category data
        const [oldCategories] = await pool.execute(
            'SELECT category_image FROM categories WHERE id = ?',
            [req.params.id]
        );

        if (oldCategories.length === 0) {
            if (req.file) {
                deleteFile(`uploads/categories/${req.file.filename}`);
            }
            return res.status(404).json({ error: 'Category not found' });
        }

        const categoryImage = req.file ? req.file.filename : oldCategories[0].category_image;

        const [result] = await pool.execute(
            'UPDATE categories SET name = ?, description = ?, category_image = ?, updated_at = NOW() WHERE id = ?',
            [name, description, categoryImage, req.params.id]
        );

        if (result.affectedRows === 0) {
            if (req.file) {
                deleteFile(`uploads/categories/${req.file.filename}`);
            }
            return res.status(404).json({ error: 'Category not found' });
        }

        // Delete old image if new one was uploaded
        if (req.file && oldCategories[0].category_image) {
            deleteFile(`uploads/categories/${oldCategories[0].category_image}`);
        }

        // Get updated category
        const [categories] = await pool.execute(
            'SELECT * FROM categories WHERE id = ?',
            [req.params.id]
        );

        res.json({ 
            message: 'Category updated successfully',
            category: categories[0]
        });

    } catch (error) {
        if (req.file) {
            deleteFile(`uploads/categories/${req.file.filename}`);
        }
        console.error('Update category error:', error);
        res.status(500).json({ error: 'Failed to update category' });
    }
});

// Delete category (superadmin only)
router.delete('/:id', requireRole(['superadmin']), async (req, res) => {
    try {
        // Check if category has products
        const [products] = await pool.execute(
            'SELECT COUNT(*) as count FROM products WHERE category_id = ?',
            [req.params.id]
        );

        if (products[0].count > 0) {
            return res.status(400).json({ 
                error: 'Cannot delete category with existing products' 
            });
        }

        // Get category image before deletion
        const [categories] = await pool.execute(
            'SELECT category_image FROM categories WHERE id = ?',
            [req.params.id]
        );

        if (categories.length === 0) {
            return res.status(404).json({ error: 'Category not found' });
        }

        const [result] = await pool.execute(
            'DELETE FROM categories WHERE id = ?',
            [req.params.id]
        );

        if (result.affectedRows === 0) {
            return res.status(404).json({ error: 'Category not found' });
        }

        // Delete category image if exists
        if (categories[0].category_image) {
            deleteFile(`uploads/categories/${categories[0].category_image}`);
        }

        res.json({ message: 'Category deleted successfully' });

    } catch (error) {
        console.error('Delete category error:', error);
        res.status(500).json({ error: 'Failed to delete category' });
    }
});

module.exports = router;