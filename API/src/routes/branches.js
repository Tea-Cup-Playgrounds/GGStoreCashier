const express = require('express');
const pool = require('../db');
const { authenticateToken, requireRole } = require('../middleware/auth');

const router = express.Router();

// Apply authentication to all routes
router.use(authenticateToken);

// Get all branches
router.get('/', async (req, res) => {
    try {
        const [branches] = await pool.execute(
            'SELECT * FROM branches ORDER BY name ASC'
        );
        res.json({ branches });

    } catch (error) {
        console.error('Get branches error:', error);
        res.status(500).json({ error: 'Failed to fetch branches' });
    }
});

// Get branch by ID
router.get('/:id', async (req, res) => {
    try {
        const [branches] = await pool.execute(
            'SELECT * FROM branches WHERE id = ?',
            [req.params.id]
        );

        if (branches.length === 0) {
            return res.status(404).json({ error: 'Branch not found' });
        }

        res.json({ branch: branches[0] });

    } catch (error) {
        console.error('Get branch error:', error);
        res.status(500).json({ error: 'Failed to fetch branch' });
    }
});

// Create new branch (superadmin only)
router.post('/', requireRole(['superadmin']), async (req, res) => {
    try {
        const { name, address, phone } = req.body;

        if (!name) {
            return res.status(400).json({ 
                error: 'Branch name is required' 
            });
        }

        const [result] = await pool.execute(
            'INSERT INTO branches (name, address, phone) VALUES (?, ?, ?)',
            [name, address, phone]
        );

        res.status(201).json({ 
            message: 'Branch created successfully',
            branchId: result.insertId 
        });

    } catch (error) {
        console.error('Create branch error:', error);
        res.status(500).json({ error: 'Failed to create branch' });
    }
});

// Update branch (superadmin only)
router.put('/:id', requireRole(['superadmin']), async (req, res) => {
    try {
        const { name, address, phone } = req.body;

        if (!name) {
            return res.status(400).json({ 
                error: 'Branch name is required' 
            });
        }

        const [result] = await pool.execute(
            'UPDATE branches SET name = ?, address = ?, phone = ?, updated_at = NOW() WHERE id = ?',
            [name, address, phone, req.params.id]
        );

        if (result.affectedRows === 0) {
            return res.status(404).json({ error: 'Branch not found' });
        }

        res.json({ message: 'Branch updated successfully' });

    } catch (error) {
        console.error('Update branch error:', error);
        res.status(500).json({ error: 'Failed to update branch' });
    }
});

// Delete branch (superadmin only)
router.delete('/:id', requireRole(['superadmin']), async (req, res) => {
    try {
        // Prevent deletion of "Semua Branch" (id = 0)
        if (req.params.id === '0') {
            return res.status(400).json({ 
                error: 'Cannot delete the main branch' 
            });
        }

        // Check if branch has users or products
        const [users] = await pool.execute(
            'SELECT COUNT(*) as count FROM users WHERE branch_id = ?',
            [req.params.id]
        );

        const [products] = await pool.execute(
            'SELECT COUNT(*) as count FROM products WHERE branch_id = ?',
            [req.params.id]
        );

        if (users[0].count > 0 || products[0].count > 0) {
            return res.status(400).json({ 
                error: 'Cannot delete branch with existing users or products' 
            });
        }

        const [result] = await pool.execute(
            'DELETE FROM branches WHERE id = ?',
            [req.params.id]
        );

        if (result.affectedRows === 0) {
            return res.status(404).json({ error: 'Branch not found' });
        }

        res.json({ message: 'Branch deleted successfully' });

    } catch (error) {
        console.error('Delete branch error:', error);
        res.status(500).json({ error: 'Failed to delete branch' });
    }
});

module.exports = router;