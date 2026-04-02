require('dotenv').config();

const express = require('express');
const http = require('http');
const socketIO = require('socket.io');
const helmet = require('helmet');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
const cookieParser = require('cookie-parser');
const morgan = require('morgan');
const path = require('path');
const ngrok = require('@ngrok/ngrok');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const pool = require('./db');
const { ensureUploadDirs } = require('./utils/upload');

// Track ngrok public URL
let ngrokUrl = null;

const authRoutes = require('./routes/auth');
const userRoutes = require('./routes/users');
const adminRoutes = require('./routes/admins');
const superRoutes = require('./routes/super');
const productRoutes = require('./routes/products');
const categoryRoutes = require('./routes/categories');
const branchRoutes = require('./routes/branches');
const transactionRoutes = require('./routes/transactions');
const dashboardRoutes = require('./routes/dashboard');
const voucherRoutes  = require('./routes/vouchers');

const app = express();
const server = http.createServer(app);

// Ensure upload directories exist
ensureUploadDirs();

// CORS configuration for Flutter web
const corsOrigins = process.env.CORS_ORIGIN 
  ? process.env.CORS_ORIGIN.split(',').map(origin => origin.trim())
  : ['http://localhost:3000'];

// Socket.IO setup with CORS
const io = socketIO(server, {
    cors: {
        origin: function (origin, callback) {
            // Allow requests with no origin (like mobile apps)
            if (!origin) return callback(null, true);
            
            // In development, allow all localhost and 127.0.0.1 origins
            if (process.env.NODE_ENV === 'development') {
                if (origin.includes('localhost') || origin.includes('127.0.0.1')) {
                    return callback(null, true);
                }
            }
            
            // Check against configured origins
            if (corsOrigins.includes(origin)) {
                return callback(null, true);
            }
            
            return callback(null, false);
        },
        credentials: true,
        methods: ['GET', 'POST']
    }
});

// Socket.IO connection handling
io.on('connection', (socket) => {
    console.log('Client connected:', socket.id);

    // Join branch-specific room
    socket.on('join-branch', (branchId) => {
        socket.join(`branch-${branchId}`);
        console.log(`Socket ${socket.id} joined branch-${branchId}`);
    });

    // Leave branch room
    socket.on('leave-branch', (branchId) => {
        socket.leave(`branch-${branchId}`);
        console.log(`Socket ${socket.id} left branch-${branchId}`);
    });

    socket.on('disconnect', () => {
        console.log('Client disconnected:', socket.id);
    });
});

// Make io accessible to routes
app.set('io', io);

// Middleware
app.use(helmet({
    crossOriginEmbedderPolicy: false,
    contentSecurityPolicy: {
        directives: {
            defaultSrc: ["'self'"],
            scriptSrc: ["'self'"],
            styleSrc: ["'self'", "'unsafe-inline'"],
            imgSrc: ["'self'", 'data:'],
            connectSrc: ["'self'", 'ws:', 'wss:'],
        },
    },
}));

app.use(cors({
    origin: function (origin, callback) {
        // Allow requests with no origin (like mobile apps or curl requests)
        if (!origin) return callback(null, true);
        
        // In development, allow all localhost and 127.0.0.1 origins
        if (process.env.NODE_ENV === 'development') {
            if (origin.includes('localhost') || origin.includes('127.0.0.1')) {
                return callback(null, true);
            }
        }
        
        // Check against configured origins
        if (corsOrigins.includes(origin)) {
            return callback(null, true);
        }
        
        // Log rejected origins for debugging
        console.log('CORS rejected origin:', origin);
        return callback(new Error('Not allowed by CORS'));
    },
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'Cookie', 'ngrok-skip-browser-warning'],
}));
app.use(express.json({
    limit: '10kb'
}));
app.use(cookieParser());
app.use(morgan('dev'));

// Serve static files from uploads directory (inside API folder)
app.use('/uploads', express.static(path.join(__dirname, '../uploads')));

// Serve public assets (api-docs.js, favicon, etc.)
app.use(express.static(path.join(__dirname, 'public')));

// Suppress favicon 404
app.get('/favicon.ico', (req, res) => res.status(204).end());

// Trust proxy — required when running behind ngrok or any reverse proxy
// '1' means trust the first hop (ngrok -> your server)
app.set('trust proxy', 1);

const limiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 100, // limit each IP to 100 requests per windowMs
    standardHeaders: true,
    legacyHeaders: false,
});
app.use(limiter);

// Routes
app.use('/api/auth', authRoutes);
app.use('/api/users', userRoutes);
app.use('/api/admins', adminRoutes);
app.use('/api/super', superRoutes);
app.use('/api/products', productRoutes);
app.use('/api/categories', categoryRoutes);
app.use('/api/branches', branchRoutes);
app.use('/api/transactions', transactionRoutes);
app.use('/api/dashboard', dashboardRoutes);
app.use('/api/vouchers',  voucherRoutes);

// ── Docs session middleware ───────────────────────────────────────────────────
const DOCS_SESSION_COOKIE = 'docs_session';

const docsLoginAttempts = new Map();
const DOCS_MAX_ATTEMPTS = 5;
const DOCS_LOCKOUT_MS = 15 * 60 * 1000;

function isDocsLockedOut(ip) {
    const rec = docsLoginAttempts.get(ip);
    if (!rec) return false;
    return rec.count >= DOCS_MAX_ATTEMPTS && rec.lockedUntil > Date.now();
}

function recordDocsFailure(ip) {
    const rec = docsLoginAttempts.get(ip) || { count: 0, lockedUntil: 0 };
    rec.count += 1;
    if (rec.count >= DOCS_MAX_ATTEMPTS) rec.lockedUntil = Date.now() + DOCS_LOCKOUT_MS;
    docsLoginAttempts.set(ip, rec);
}

function requireDocsSession(req, res, next) {
    const token = req.cookies[DOCS_SESSION_COOKIE];
    if (!token) return res.redirect('/api/docs/login');
    try {
        const decoded = jwt.verify(token, process.env.JWT_SECRET);
        if (decoded.role !== 'superadmin' || decoded.purpose !== 'docs') {
            res.clearCookie(DOCS_SESSION_COOKIE);
            return res.redirect('/api/docs/login');
        }
        next();
    } catch {
        res.clearCookie(DOCS_SESSION_COOKIE);
        return res.redirect('/api/docs/login');
    }
}

// Docs login page
app.get('/api/docs/login', (req, res) => {
    res.sendFile(path.join(__dirname, 'views', 'docs-login.html'));
});

// Docs login POST
app.post('/api/docs/login', async (req, res) => {
    const clientIP = req.ip;
    if (isDocsLockedOut(clientIP)) {
        const rec = docsLoginAttempts.get(clientIP);
        const mins = Math.ceil((rec.lockedUntil - Date.now()) / 60000);
        return res.status(429).json({ error: `Too many attempts. Try again in ${mins} minute(s).` });
    }

    const { username, password, remember } = req.body;
    if (!username || !password) {
        return res.status(400).json({ error: 'Username and password are required' });
    }

    try {
        const [users] = await pool.execute(
            'SELECT id, username, password, role FROM users WHERE username = ?',
            [username]
        );

        const user = users[0];
        const valid = user && await bcrypt.compare(password, user.password);

        if (!valid || user.role !== 'superadmin') {
            recordDocsFailure(clientIP);
            return res.status(401).json({ error: 'Invalid credentials or insufficient permissions' });
        }

        docsLoginAttempts.delete(clientIP);

        const maxAge = remember ? 24 * 60 * 60 * 1000 : undefined; // 1 day or session
        const expiresIn = remember ? '1d' : '8h';

        const token = jwt.sign(
            { userId: user.id, username: user.username, role: user.role, purpose: 'docs' },
            process.env.JWT_SECRET,
            { expiresIn }
        );

        res.cookie(DOCS_SESSION_COOKIE, token, {
            httpOnly: true,
            secure: process.env.NODE_ENV === 'production',
            sameSite: 'strict',
            ...(maxAge ? { maxAge } : {}),
        });

        res.json({ ok: true });
    } catch (err) {
        console.error('Docs login error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
});

// Docs logout
app.post('/api/docs/logout', (req, res) => {
    res.clearCookie(DOCS_SESSION_COOKIE);
    res.redirect('/api/docs/login');
});

// API Docs - HTML page (protected)
app.get('/api/docs', requireDocsSession, (req, res) => {
    res.sendFile(path.join(__dirname, 'views', 'api-docs.html'));
});

// API Docs - JSON info for the docs page (protected)
app.get('/api/docs/info', requireDocsSession, (req, res) => {
    res.json({
        status: 'OK',
        env: process.env.NODE_ENV || 'development',
        uptime: process.uptime(),
        ngrokUrl,
        timestamp: new Date().toISOString(),
    });
});

// Health check endpoint
app.get('/api/health', (req, res) => {
    res.json({ status: 'OK', message: 'Server is running' });
});

// Test endpoint for Flutter connectivity
app.get('/api/test', (req, res) => {
    console.log('Test endpoint hit from:', req.ip);
    res.json({ 
        status: 'OK', 
        message: 'Connection successful',
        timestamp: new Date().toISOString(),
        ip: req.ip
    });
});

// Error handling middleware
const errorHandler = (err, req, res, next) => {
    console.error(err.stack);
    res.status(500).json({ 
        error: 'Something went wrong!',
        message: process.env.NODE_ENV === 'development' ? err.message : 'Internal server error'
    });
};

app.use(errorHandler);

const PORT = process.env.PORT || 3000;
server.listen(PORT, async () => {
    console.log(`Server running on port ${PORT}`);
    console.log(`Socket.IO enabled for real-time updates`);
    console.log(`API Docs: http://localhost:${PORT}/api/docs`);

    // Broadcast server-info to docs clients every 10 seconds via Socket.IO
    setInterval(() => {
        io.emit('server-info', {
            status: 'OK',
            env: process.env.NODE_ENV || 'development',
            uptime: process.uptime(),
            ngrokUrl,
            timestamp: new Date().toISOString(),
        });
    }, 10000);

    // Start ngrok if auth token is provided
    if (process.env.NGROK_AUTHTOKEN) {
        try {
            const listener = await ngrok.forward({
                addr: PORT,
                authtoken: process.env.NGROK_AUTHTOKEN,
            });
            ngrokUrl = listener.url();
            console.log(`\nngrok public URL : ${ngrokUrl}`);
            console.log(`API Docs           : ${ngrokUrl}/api/docs\n`);
        } catch (err) {
            console.warn('⚠️  ngrok failed to start:', err.message);
        }
    } else {
        console.warn('⚠️  NGROK_AUTHTOKEN not set — skipping ngrok tunnel');
    }
});