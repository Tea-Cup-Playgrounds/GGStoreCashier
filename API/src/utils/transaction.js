const pool = require('../db');

// An error whose message is meant for the user (Indonesian) and maps to an HTTP status.
class AppError extends Error {
    constructor(message, status = 400) {
        super(message);
        this.status = status;
    }
}

// Runs fn(conn) in a transaction and returns its result. On failure it rolls back, sends the
// response itself (AppError -> its status and message, anything else -> 500) and returns undefined,
// so callers only respond when they get a result back.
const withTransaction = async (res, fallbackMessage, fn) => {
    const conn = await pool.getConnection();
    try {
        await conn.beginTransaction();
        const result = await fn(conn);
        await conn.commit();
        return result;
    } catch (error) {
        await conn.rollback();
        if (error instanceof AppError) {
            res.status(error.status).json({ error: error.message });
        } else {
            console.error(`${fallbackMessage}:`, error);
            res.status(500).json({ error: fallbackMessage });
        }
        return undefined;
    } finally {
        conn.release();
    }
};

module.exports = { AppError, withTransaction };
