const jwt = require('jsonwebtoken');
const express = require('express');
const pool = require('../db');
const { loadAccess } = require('../services/access');

// Middleware to verify JWT token
const authenticateToken = async (req, res, next) => {
    try {
        const token = req.cookies.token || req.headers.authorization?.split(' ')[1];
        
        if (!token) {
            return res.status(401).json({ error: 'Token akses diperlukan' });
        }

        const decoded = jwt.verify(token, process.env.JWT_SECRET);
        
        // Get user from database
        const [users] = await pool.execute(
            'SELECT id, name, username, role, branch_id, is_active FROM users WHERE id = ?',
            [decoded.userId]
        );

        if (users.length === 0) {
            return res.status(401).json({ error: 'Pengguna tidak ditemukan' });
        }

        if (!users[0].is_active) {
            return res.status(401).json({ error: 'Akun dinonaktifkan' });
        }

        req.user = users[0];
        req.access = await loadAccess(pool, req.user.id);

        // Update last active timestamp asynchronously
        pool.execute(
            'UPDATE users SET last_active_at = NOW() WHERE id = ?',
            [req.user.id]
        ).catch(err => console.error('Error updating last_active_at:', err.message));

        next();

    } catch (error) {
        console.error('Auth middleware error:', error);
        res.status(401).json({ error: 'Token tidak valid' });
    }
};

// Middleware to check user role
const requireRole = (roles) => {
    return (req, res, next) => {
        if (!req.user) {
            return res.status(401).json({ error: 'Autentikasi diperlukan' });
        }

        if (!roles.includes(req.user.role)) {
            return res.status(403).json({ error: 'Akses tidak diizinkan' });
        }

        next();
    };
};

// Middleware to filter data by user's branch
// Admin can only see/modify data from their branch
// Superadmin can see/modify all branches
const filterByBranch = (req, res, next) => {
    if (!req.user) {
        return res.status(401).json({ error: 'Autentikasi diperlukan' });
    }

    // Superadmin can access all branches
    if (req.user.role === 'superadmin') {
        return next();
    }

    // Admin and karyawan can only access their own branch
    if (req.user.role === 'admin' || req.user.role === 'karyawan') {
        // Add branch_id to query params for GET requests. In Express 5 req.query is a getter that
        // re-parses the URL on every access, so assigning a property on it is silently lost;
        // replace the property instead.
        if (req.method === 'GET') {
            Object.defineProperty(req, 'query', {
                value: { ...req.query, branch_id: String(req.user.branch_id) },
                writable: true,
                configurable: true,
                enumerable: true,
            });
        }
        
        // For POST/PUT requests, ensure branch_id matches user's branch
        if (req.method === 'POST' || req.method === 'PUT') {
            // req.body may be undefined for multipart/form-data before multer runs.
            // Attach the user's branch_id so route handlers can enforce it after parsing.
            req.userBranchId = req.user.branch_id;

            if (req.body && req.body.branch_id && req.body.branch_id != req.user.branch_id) {
                return res.status(403).json({ 
                    error: 'Anda hanya dapat mengelola data cabang Anda sendiri' 
                });
            }
            // Only force branch_id on JSON bodies; multipart bodies are handled in the route
            if (req.body) {
                req.body.branch_id = req.user.branch_id;
            }
        }
    }

    next();
};

// The location a request acts on: route param, query, JSON body, or X-Location-Id header.
const requestLocationId = (req) => {
    const value = req.params.locationId ?? req.query.location_id ?? req.body?.location_id ?? req.get('X-Location-Id');
    return value === undefined || value === null || value === '' ? undefined : value;
};

// Middleware to check a permission (see auth/permissions.js).
// - If the request names a location, the user must hold the permission there; the parsed id
//   is put on req.locationId.
// - Otherwise the user must hold it somewhere; handlers that list data should then scope
//   results with req.access.locationsFor(permission).
// Pass { location: (req) => id } when the location comes from somewhere else (e.g. a loaded record).
const requirePermission = (permission, { location } = {}) => {
    return async (req, res, next) => {
        if (!req.user || !req.access) {
            return res.status(401).json({ error: 'Autentikasi diperlukan' });
        }

        try {
            const locationId = location ? await location(req) : requestLocationId(req);

            if (locationId !== undefined && locationId !== null) {
                const parsed = Number(locationId);
                if (!Number.isInteger(parsed) || parsed <= 0) {
                    return res.status(400).json({ error: 'location_id tidak valid' });
                }
                if (!req.access.can(permission, parsed)) {
                    return res.status(403).json({ error: 'Akses tidak diizinkan' });
                }
                req.locationId = parsed;
            } else if (!req.access.can(permission)) {
                return res.status(403).json({ error: 'Akses tidak diizinkan' });
            }

            next();
        } catch (error) {
            next(error);
        }
    };
};

module.exports = {
    authenticateToken,
    requireRole,
    requirePermission,
    filterByBranch
};