const express = require('express');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const pool = require('../db');

const router = express.Router();

// In-memory store for login attempts (in production, use Redis or database)
const loginAttempts = new Map();
const MAX_ATTEMPTS = 5;
const LOCKOUT_TIME = 15 * 60 * 1000; // 15 minutes

// Helper function to get client IP
const getClientIP = (req) => {
    return req.ip || req.connection.remoteAddress || req.socket.remoteAddress || 
           (req.connection.socket ? req.connection.socket.remoteAddress : null);
};

// Helper function to check if user is locked out
const isLockedOut = (identifier) => {
    const attempts = loginAttempts.get(identifier);
    if (!attempts) return false;
    
    if (attempts.count >= MAX_ATTEMPTS) {
        const timeLeft = attempts.lockedUntil - Date.now();
        return timeLeft > 0;
    }
    return false;
};

// Helper function to record failed attempt
const recordFailedAttempt = (identifier) => {
    const attempts = loginAttempts.get(identifier) || { count: 0, lockedUntil: 0 };
    attempts.count += 1;
    
    if (attempts.count >= MAX_ATTEMPTS) {
        attempts.lockedUntil = Date.now() + LOCKOUT_TIME;
    }
    
    loginAttempts.set(identifier, attempts);
    return attempts;
};

// Helper function to clear attempts on successful login
const clearAttempts = (identifier) => {
    loginAttempts.delete(identifier);
};

// Login endpoint
router.post('/login', async (req, res) => {
    try {
        console.log('Login attempt received:', { 
            username: req.body.username, 
            ip: req.ip,
            userAgent: req.get('User-Agent')
        });
        
        const { username, password } = req.body;
        const clientIP = getClientIP(req);
        const identifier = `${username}_${clientIP}`;

        if (!username || !password) {
            console.log('Login failed: Missing credentials');
            return res.status(400).json({ 
                error: 'Username and password are required' 
            });
        }

        // Check if user is locked out
        if (isLockedOut(identifier)) {
            const attempts = loginAttempts.get(identifier);
            const timeLeft = Math.ceil((attempts.lockedUntil - Date.now()) / 1000 / 60);
            console.log(`Login blocked: User ${username} is locked out for ${timeLeft} minutes`);
            return res.status(429).json({ 
                error: `Too many failed attempts. Try again in ${timeLeft} minutes.`,
                lockedUntil: attempts.lockedUntil
            });
        }

        // Find user by username
        console.log('Looking up user:', username);
        const [users] = await pool.execute(
            'SELECT * FROM users WHERE username = ?',
            [username]
        );

        if (users.length === 0) {
            console.log('Login failed: User not found:', username);
            recordFailedAttempt(identifier);
            const attempts = loginAttempts.get(identifier);
            const remainingAttempts = MAX_ATTEMPTS - attempts.count;
            
            return res.status(401).json({ 
                error: 'Invalid credentials',
                remainingAttempts: remainingAttempts > 0 ? remainingAttempts : 0
            });
        }

        const user = users[0];
        console.log('User found:', { id: user.id, username: user.username, role: user.role });

        // Compare hashed password
        const isValidPassword = await bcrypt.compare(password, user.password);
        if (!isValidPassword) {
            console.log('Login failed: Invalid password for user:', username);
            recordFailedAttempt(identifier);
            const attempts = loginAttempts.get(identifier);
            const remainingAttempts = MAX_ATTEMPTS - attempts.count;
            
            return res.status(401).json({ 
                error: 'Invalid credentials',
                remainingAttempts: remainingAttempts > 0 ? remainingAttempts : 0
            });
        }

        // Clear failed attempts on successful login
        clearAttempts(identifier);
        console.log('Login successful for user:', username);

        // Generate JWT token
        const token = jwt.sign(
            { 
                userId: user.id, 
                username: user.username, 
                role: user.role,
                branchId: user.branch_id 
            },
            process.env.JWT_SECRET,
            { expiresIn: '24h' }
        );

        // Set cookie
        res.cookie('token', token, {
            httpOnly: true,
            secure: process.env.NODE_ENV === 'production',
            maxAge: 24 * 60 * 60 * 1000 // 24 hours
        });

        res.json({
            message: 'Login successful',
            user: {
                id: user.id,
                name: user.name,
                username: user.username,
                role: user.role,
                branchId: user.branch_id
            },
            token // Include token for Flutter app
        });

    } catch (error) {
        console.error('Login error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Logout endpoint
router.post('/logout', (req, res) => {
    res.clearCookie('token');
    res.json({ message: 'Logged out successfully' });
});

// Get current user endpoint
router.get('/me', async (req, res) => {
    try {
        const token = req.cookies.token || req.headers.authorization?.split(' ')[1];
        
        if (!token) {
            return res.status(401).json({ error: 'No token provided' });
        }

        const decoded = jwt.verify(token, process.env.JWT_SECRET);
        
        const [users] = await pool.execute(
            'SELECT id, name, username, role, branch_id FROM users WHERE id = ?',
            [decoded.userId]
        );

        if (users.length === 0) {
            return res.status(401).json({ error: 'User not found' });
        }

        res.json({ user: users[0] });

    } catch (error) {
        console.error('Get user error:', error);
        res.status(401).json({ error: 'Invalid token' });
    }
});

module.exports = router;