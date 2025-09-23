require('dotenv').config();

const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
const cookieParser = require('cookie-parser');
const morgan = require('morgan');

const authRoutes = require('./routes/auth');
const userRoutes = require('./route/users');
const adminRoutes = require('.routes/admins');
const superRoutes = require('./routes/super');

const app = express();

app.use(helmet());
app.use(cors({
    origin: process.env.CORS_ORIGIN, credentials: true
}));
app.use(express.json({
    limit: '10kb'
}));
app.use(cookieParser());
app.use(morgan('dev'));

const limiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    max: 100
});
app.use(limiter);

app.use('/api/auth', authRoutes);
app.use('/api/users', userRoutes);
app.use('/api/admins', adminRoutes);
app.use('api/super', superRoutes);

app.use(errorHandler);

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log('server running on ${PORT}'));