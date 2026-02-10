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
const { ensureUploadDirs } = require('./utils/upload');

const authRoutes = require('./routes/auth');
const userRoutes = require('./routes/users');
const adminRoutes = require('./routes/admins');
const superRoutes = require('./routes/super');
const productRoutes = require('./routes/products');
const categoryRoutes = require('./routes/categories');
const branchRoutes = require('./routes/branches');
const transactionRoutes = require('./routes/transactions');

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
    allowedHeaders: ['Content-Type', 'Authorization', 'Cookie'],
}));
app.use(express.json({
    limit: '10kb'
}));
app.use(cookieParser());
app.use(morgan('dev'));

// Serve static files from uploads directory
app.use('/uploads', express.static(path.join(__dirname, '../uploads')));

const limiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 100 // limit each IP to 100 requests per windowMs
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
server.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
    console.log(`Socket.IO enabled for real-time updates`);
});