const jwt = require('jsonwebtoken');
const { rateLimit, ipKeyGenerator } = require('express-rate-limit');

// General API rate limit. A shop's devices usually share one public IP, so requests are counted
// per signed-in user (from the API token); only requests without a valid token are counted per IP.
// Login attempts have their own lockout in routes/auth.js. Limits can be tuned with env vars.
const WINDOW_MS = Number(process.env.RATE_LIMIT_WINDOW_MS) || 60 * 1000;
const USER_MAX = Number(process.env.RATE_LIMIT_USER_MAX) || 300;
const ANON_MAX = Number(process.env.RATE_LIMIT_ANON_MAX) || 60;

// Connectivity probes: cheap, no database, and a 429 here would make the app think it is offline.
const UNLIMITED_PATHS = new Set(['/api/health', '/api/test']);

// Only the signature is checked here (no database lookup); routes still authenticate properly.
const tokenUserId = (req) => {
    const token = req.cookies?.token || req.headers.authorization?.split(' ')[1];
    if (!token) return null;
    try {
        const { userId } = jwt.verify(token, process.env.JWT_SECRET);
        return Number.isInteger(userId) ? userId : null;
    } catch {
        return null;
    }
};

const limiter = rateLimit({
    windowMs: WINDOW_MS,
    limit: (req) => (req.rateLimitUserId ? USER_MAX : ANON_MAX),
    keyGenerator: (req) => (req.rateLimitUserId ? `user:${req.rateLimitUserId}` : `ip:${ipKeyGenerator(req.ip)}`),
    skip: (req) => UNLIMITED_PATHS.has(req.path),
    standardHeaders: 'draft-7',
    legacyHeaders: false,
    message: { error: 'Terlalu banyak permintaan. Coba lagi sebentar lagi.' },
});

const apiRateLimit = [
    (req, res, next) => {
        req.rateLimitUserId = tokenUserId(req);
        next();
    },
    limiter,
];

module.exports = { apiRateLimit };
