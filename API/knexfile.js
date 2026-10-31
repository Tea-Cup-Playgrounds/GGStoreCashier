const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });

// Knex is only used for migrations; route handlers keep using the mysql2 pool in src/db.js.
module.exports = {
    client: 'mysql2',
    connection: {
        host: process.env.DB_HOST,
        port: process.env.DB_PORT ? Number(process.env.DB_PORT) : 3306,
        user: process.env.DB_USER,
        password: process.env.DB_PASS,
        database: process.env.DB_NAME,
        charset: 'utf8mb4',
        timezone: 'local',
    },
    migrations: {
        directory: path.resolve(__dirname, 'migrations'),
        tableName: 'knex_migrations',
    },
    seeds: {
        directory: path.resolve(__dirname, 'seeds'),
    },
};
