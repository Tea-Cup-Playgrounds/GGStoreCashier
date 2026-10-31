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
            'SELECT id, name, username, is_active FROM users WHERE id = ?',
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
    requirePermission,
};