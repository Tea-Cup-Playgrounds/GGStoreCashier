// Small helpers shared by the route files.

// Who is acting, for stock movements and documents.
const ctxOf = (req) => ({ userId: req.user.id, deviceId: req.deviceId || null });

// Use after requirePermission(...): rejects requests that didn't name a location.
const requireLocation = (req, res, next) => {
    if (!req.locationId) return res.status(400).json({ error: 'location_id wajib diisi' });
    next();
};

// Parses YYYY-MM-DD; returns null for empty input and undefined for invalid input.
const parseDate = (value) => {
    if (value === undefined || value === null || value === '') return null;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(String(value))) return undefined;
    const date = new Date(`${value}T00:00:00`);
    return Number.isNaN(date.getTime()) ? undefined : String(value);
};

// Positive money amount rounded to cents, or NaN.
const parseMoney = (value) => {
    const n = Number(value);
    return Number.isFinite(n) && n >= 0 ? Math.round(n * 100) / 100 : NaN;
};

module.exports = { ctxOf, requireLocation, parseDate, parseMoney };
