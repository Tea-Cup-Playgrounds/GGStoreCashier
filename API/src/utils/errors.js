// An error whose message is meant for the user (Indonesian) and maps to an HTTP status.
// Kept apart from utils/transaction.js so pure code (services/pricing.js) can use it without
// opening a database pool.
class AppError extends Error {
    constructor(message, status = 400) {
        super(message);
        this.status = status;
    }
}

module.exports = { AppError };
