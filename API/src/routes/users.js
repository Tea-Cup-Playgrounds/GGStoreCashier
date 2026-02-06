const express = require('express');
const bcrypt = require('bcrypt');
const pool = require('../db');
const { authenticateToken, requireRole } = require('../middleware/auth');

const router = express.Router();

// Security RegEx patterns for input validation
const SECURITY_PATTERNS = {
    // Prevent script injection and malicious code
    SCRIPT_INJECTION: /<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi,
    HTML_TAGS: /<[^>]*>/g,
    SQL_INJECTION: /(union|select|insert|update|delete|drop|create|alter|exec|execute|script|javascript|vbscript|onload|onerror|onclick)/gi,
    XSS_PATTERNS: /(javascript:|data:|vbscript:|onload=|onerror=|onclick=|onmouseover=|onfocus=|onblur=)/gi,
    
    // Valid input patterns
    NAME: /^[a-zA-Z\s\-'\.]{2,50}$/,
    USERNAME: /^[a-zA-Z0-9_\-\.]{3,30}$/,
    ROLE: /^(karyawan|admin|superadmin)$/,
};

// Password strength validation
const validatePasswordStrength = (password) => {
    const minLength = 8;
    const hasUpperCase = /[A-Z]/.test(password);
    const hasLowerCase = /[a-z]/.test(password);
    const hasNumbers = /\d/.test(password);
    const hasSpecialChar = /[!@#$%^&*(),.?":{}|<>]/.test(password);
    
    const score = [
        password.length >= minLength,
        hasUpperCase,
        hasLowerCase,
        hasNumbers,
        hasSpecialChar
    ].filter(Boolean).length;
    
    return {
        isValid: score >= 3 && password.length >= minLength,
        score,
        requirements: {
            minLength: password.length >= minLength,
            hasUpperCase,
            hasLowerCase,
            hasNumbers,
            hasSpecialChar
        }
    };
};

// Input sanitization function
const sanitizeInput = (input) => {
    if (typeof input !== 'string') return input;
    
    return input
        .replace(SECURITY_PATTERNS.SCRIPT_INJECTION, '')
        .replace(SECURITY_PATTERNS.HTML_TAGS, '')
        .trim();
};

// Validate input against malicious patterns
const validateInput = (input) => {
    if (typeof input !== 'string') return true;
    
    return !SECURITY_PATTERNS.SQL_INJECTION.test(input) &&
           !SECURITY_PATTERNS.XSS_PATTERNS.test(input) &&
           !SECURITY_PATTERNS.SCRIPT_INJECTION.test(input);
};

// Apply authentication to all routes
router.use(authenticateToken);

// Password strength check endpoint
router.post('/check-password-strength', requireRole(['admin', 'superadmin']), (req, res) => {
    try {
        const { password } = req.body;
        
        if (!password) {
            return res.status(400).json({ error: 'Password is required' });
        }
        
        const validation = validatePasswordStrength(password);
        res.json(validation);
        
    } catch (error) {
        console.error('Password strength check error:', error);
        res.status(500).json({ error: 'Failed to check password strength' });
    }
});

// Get all users (admin/superadmin only)
router.get('/', requireRole(['admin', 'superadmin']), async (req, res) => {
    try {
        const { branch_id, role, search, page = 1, limit = 10 } = req.query;
        
        let query = `
            SELECT u.id, u.name, u.username, u.role, u.branch_id, u.created_at, u.updated_at,
                   b.name as branch_name
            FROM users u 
            LEFT JOIN branches b ON u.branch_id = b.id 
            WHERE 1=1
        `;
        const params = [];

        if (branch_id && branch_id !== '0') {
            query += ' AND u.branch_id = ?';
            params.push(branch_id);
        }

        if (role && SECURITY_PATTERNS.ROLE.test(role)) {
            query += ' AND u.role = ?';
            params.push(role);
        }

        if (search) {
            const sanitizedSearch = sanitizeInput(search);
            if (validateInput(sanitizedSearch)) {
                query += ' AND (u.name LIKE ? OR u.username LIKE ?)';
                params.push(`%${sanitizedSearch}%`, `%${sanitizedSearch}%`);
            }
        }

        query += ' ORDER BY u.created_at DESC';
        
        // Add pagination
        const offset = (parseInt(page) - 1) * parseInt(limit);
        query += ' LIMIT ? OFFSET ?';
        params.push(parseInt(limit), offset);

        const [users] = await pool.execute(query, params);
        
        // Get total count for pagination
        let countQuery = `
            SELECT COUNT(*) as total
            FROM users u 
            WHERE 1=1
        `;
        const countParams = [];
        
        if (branch_id && branch_id !== '0') {
            countQuery += ' AND u.branch_id = ?';
            countParams.push(branch_id);
        }
        
        if (role && SECURITY_PATTERNS.ROLE.test(role)) {
            countQuery += ' AND u.role = ?';
            countParams.push(role);
        }
        
        if (search) {
            const sanitizedSearch = sanitizeInput(search);
            if (validateInput(sanitizedSearch)) {
                countQuery += ' AND (u.name LIKE ? OR u.username LIKE ?)';
                countParams.push(`%${sanitizedSearch}%`, `%${sanitizedSearch}%`);
            }
        }
        
        const [countResult] = await pool.execute(countQuery, countParams);
        const total = countResult[0].total;

        res.json({ 
            users,
            pagination: {
                page: parseInt(page),
                limit: parseInt(limit),
                total,
                totalPages: Math.ceil(total / parseInt(limit))
            }
        });

    } catch (error) {
        console.error('Get users error:', error);
        res.status(500).json({ error: 'Failed to fetch users' });
    }
});

// Get user by ID (admin/superadmin only)
router.get('/:id', requireRole(['admin', 'superadmin']), async (req, res) => {
    try {
        const [users] = await pool.execute(
            `SELECT u.id, u.name, u.username, u.role, u.branch_id, u.created_at, u.updated_at,
                    b.name as branch_name
             FROM users u 
             LEFT JOIN branches b ON u.branch_id = b.id 
             WHERE u.id = ?`,
            [req.params.id]
        );

        if (users.length === 0) {
            return res.status(404).json({ error: 'User not found' });
        }

        res.json({ user: users[0] });

    } catch (error) {
        console.error('Get user error:', error);
        res.status(500).json({ error: 'Failed to fetch user' });
    }
});

// Create new user (admin/superadmin only)
router.post('/', requireRole(['admin', 'superadmin']), async (req, res) => {
    try {
        const { name, username, password, role, branch_id } = req.body;

        // Input validation
        if (!name || !username || !password) {
            return res.status(400).json({ 
                error: 'Name, username, and password are required' 
            });
        }

        // Sanitize inputs
        const sanitizedName = sanitizeInput(name);
        const sanitizedUsername = sanitizeInput(username);
        const sanitizedRole = role || 'karyawan';

        // Validate inputs against malicious patterns
        if (!validateInput(sanitizedName) || !validateInput(sanitizedUsername)) {
            return res.status(400).json({ 
                error: 'Invalid characters detected in input' 
            });
        }

        // Validate input formats
        if (!SECURITY_PATTERNS.NAME.test(sanitizedName)) {
            return res.status(400).json({ 
                error: 'Name must be 2-50 characters and contain only letters, spaces, hyphens, apostrophes, and periods' 
            });
        }

        if (!SECURITY_PATTERNS.USERNAME.test(sanitizedUsername)) {
            return res.status(400).json({ 
                error: 'Username must be 3-30 characters and contain only letters, numbers, underscores, hyphens, and periods' 
            });
        }

        if (!SECURITY_PATTERNS.ROLE.test(sanitizedRole)) {
            return res.status(400).json({ 
                error: 'Invalid role specified' 
            });
        }

        // Validate password strength
        const passwordValidation = validatePasswordStrength(password);
        if (!passwordValidation.isValid) {
            return res.status(400).json({ 
                error: 'Password does not meet security requirements',
                passwordRequirements: passwordValidation.requirements
            });
        }

        // Check if username already exists
        const [existingUsers] = await pool.execute(
            'SELECT id FROM users WHERE username = ?',
            [sanitizedUsername]
        );

        if (existingUsers.length > 0) {
            return res.status(400).json({ 
                error: 'Username already exists' 
            });
        }

        // Hash password
        const saltRounds = 12;
        const hashedPassword = await bcrypt.hash(password, saltRounds);

        const [result] = await pool.execute(
            'INSERT INTO users (name, username, password, role, branch_id) VALUES (?, ?, ?, ?, ?)',
            [sanitizedName, sanitizedUsername, hashedPassword, sanitizedRole, branch_id]
        );

        res.status(201).json({ 
            message: 'User created successfully',
            userId: result.insertId 
        });

    } catch (error) {
        console.error('Create user error:', error);
        res.status(500).json({ error: 'Failed to create user' });
    }
});

// Update user (admin/superadmin only)
router.put('/:id', requireRole(['admin', 'superadmin']), async (req, res) => {
    try {
        const userId = parseInt(req.params.id);
        const { name, username, password, role, branch_id } = req.body;

        if (!userId || isNaN(userId)) {
            return res.status(400).json({ error: 'Valid user ID is required' });
        }

        // Check if user exists
        const [existingUsers] = await pool.execute(
            'SELECT id FROM users WHERE id = ?',
            [userId]
        );

        if (existingUsers.length === 0) {
            return res.status(404).json({ error: 'User not found' });
        }

        const updates = [];
        const params = [];

        // Validate and update name
        if (name !== undefined) {
            const sanitizedName = sanitizeInput(name);
            if (!validateInput(sanitizedName) || !SECURITY_PATTERNS.NAME.test(sanitizedName)) {
                return res.status(400).json({ 
                    error: 'Invalid name format' 
                });
            }
            updates.push('name = ?');
            params.push(sanitizedName);
        }

        // Validate and update username
        if (username !== undefined) {
            const sanitizedUsername = sanitizeInput(username);
            if (!validateInput(sanitizedUsername) || !SECURITY_PATTERNS.USERNAME.test(sanitizedUsername)) {
                return res.status(400).json({ 
                    error: 'Invalid username format' 
                });
            }

            // Check if new username already exists (excluding current user)
            const [duplicateUsers] = await pool.execute(
                'SELECT id FROM users WHERE username = ? AND id != ?',
                [sanitizedUsername, userId]
            );

            if (duplicateUsers.length > 0) {
                return res.status(400).json({ 
                    error: 'Username already exists' 
                });
            }

            updates.push('username = ?');
            params.push(sanitizedUsername);
        }

        // Validate and update password
        if (password !== undefined && password !== '') {
            const passwordValidation = validatePasswordStrength(password);
            if (!passwordValidation.isValid) {
                return res.status(400).json({ 
                    error: 'Password does not meet security requirements',
                    passwordRequirements: passwordValidation.requirements
                });
            }

            const saltRounds = 12;
            const hashedPassword = await bcrypt.hash(password, saltRounds);
            updates.push('password = ?');
            params.push(hashedPassword);
        }

        // Validate and update role
        if (role !== undefined) {
            if (!SECURITY_PATTERNS.ROLE.test(role)) {
                return res.status(400).json({ 
                    error: 'Invalid role specified' 
                });
            }
            updates.push('role = ?');
            params.push(role);
        }

        // Update branch_id
        if (branch_id !== undefined) {
            updates.push('branch_id = ?');
            params.push(branch_id);
        }

        if (updates.length === 0) {
            return res.status(400).json({ error: 'No valid fields to update' });
        }

        updates.push('updated_at = CURRENT_TIMESTAMP');
        params.push(userId);

        const query = `UPDATE users SET ${updates.join(', ')} WHERE id = ?`;
        await pool.execute(query, params);

        res.json({ message: 'User updated successfully' });

    } catch (error) {
        console.error('Update user error:', error);
        res.status(500).json({ error: 'Failed to update user' });
    }
});

// Delete user (admin/superadmin only)
router.delete('/:id', requireRole(['admin', 'superadmin']), async (req, res) => {
    try {
        const userId = parseInt(req.params.id);

        if (!userId || isNaN(userId)) {
            return res.status(400).json({ error: 'Valid user ID is required' });
        }

        // Prevent self-deletion
        if (userId === req.user.id) {
            return res.status(400).json({ error: 'Cannot delete your own account' });
        }

        // Check if user exists
        const [existingUsers] = await pool.execute(
            'SELECT id, role FROM users WHERE id = ?',
            [userId]
        );

        if (existingUsers.length === 0) {
            return res.status(404).json({ error: 'User not found' });
        }

        // Prevent deletion of superadmin by admin
        if (req.user.role === 'admin' && existingUsers[0].role === 'superadmin') {
            return res.status(403).json({ error: 'Cannot delete superadmin account' });
        }

        await pool.execute('DELETE FROM users WHERE id = ?', [userId]);

        res.json({ message: 'User deleted successfully' });

    } catch (error) {
        console.error('Delete user error:', error);
        res.status(500).json({ error: 'Failed to delete user' });
    }
});

module.exports = router;