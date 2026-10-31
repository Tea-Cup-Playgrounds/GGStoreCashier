// Company-wide settings stored as JSON in the `settings` table.
const getSetting = async (db, key, fallback = null) => {
    const [rows] = await db.execute('SELECT value FROM settings WHERE `key` = ?', [key]);
    if (rows.length === 0) return fallback;
    const value = rows[0].value;
    // mysql2 already parses JSON columns; older servers may hand back a string.
    if (typeof value === 'string') {
        try {
            return JSON.parse(value);
        } catch {
            return value;
        }
    }
    return value;
};

const setSetting = async (db, key, value) => {
    await db.execute(
        'INSERT INTO settings (`key`, `value`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `value` = VALUES(`value`)',
        [key, JSON.stringify(value)]
    );
};

module.exports = { getSetting, setSetting };
