const jwt = require('jsonwebtoken');
const express = require('express');
const pool = require('../db');

// Middleware to verify JWT token
const authenticateToken = async (req, res, next) => {
    try {
        const token = req.cookies.token || req.headers.authorization?.split(' ')[1];
        
        if (!token) {
            return res.status(401).json({ error: 'Access token required' });
        }

        const decoded = jwt.verify(token, process.env.JWT_SECRET);
        
        // Get user from database
        const [users] = await pool.execute(
            'SELECT id, name, username, role, branch_id FROM users WHERE id = ?',
            [decoded.userId]
        );

        if (users.length === 0) {
            return res.status(401).json({ error: 'User not found' });
        }

        req.user = users[0];
        next();

    } catch (error) {
        console.error('Auth middleware error:', error);
        res.status(401).json({ error: 'Invalid token' });
    }
};

// Middleware to check user role
const requireRole = (roles) => {
    return (req, res, next) => {
        if (!req.user) {
            return res.status(401).json({ error: 'Authentication required' });
        }

        if (!roles.includes(req.user.role)) {
            return res.status(403).json({ error: 'Insufficient permissions' });
        }

        next();
    };
};

// Middleware to filter data by user's branch
// Admin can only see/modify data from their branch
// Superadmin can see/modify all branches
const filterByBranch = (req, res, next) => {
    if (!req.user) {
        return res.status(401).json({ error: 'Authentication required' });
    }

    // Superadmin can access all branches
    if (req.user.role === 'superadmin') {
        return next();
    }

    // Admin and karyawan can only access their own branch
    if (req.user.role === 'admin' || req.user.role === 'karyawan') {
        // Add branch_id to query params for GET requests
        if (req.method === 'GET') {
            req.query.branch_id = req.user.branch_id;
        }
        
        // For POST/PUT requests, ensure branch_id matches user's branch
        if (req.method === 'POST' || req.method === 'PUT') {
            if (req.body.branch_id && req.body.branch_id != req.user.branch_id) {
                return res.status(403).json({ 
                    error: 'You can only manage data for your own branch' 
                });
            }
            // Force branch_id to user's branch
            req.body.branch_id = req.user.branch_id;
        }
    }

    next();
};

module.exports = {
    authenticateToken,
    requireRole,
    filterByBranch
};