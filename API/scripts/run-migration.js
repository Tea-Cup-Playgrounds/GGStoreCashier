require('dotenv').config({ path: require('path').resolve(__dirname, '../../.env') });
const pool = require('../src/db');

async function runMigration() {
  try {
    console.log('Running migration: adding last_active_at to users...');
    const [columns] = await pool.query("SHOW COLUMNS FROM users LIKE 'last_active_at'");
    if (columns.length === 0) {
      await pool.query("ALTER TABLE users ADD COLUMN last_active_at DATETIME NULL DEFAULT NULL AFTER branch_id");
      console.log('Migration successful: last_active_at column added.');
    } else {
      console.log('Column last_active_at already exists.');
    }
  } catch (err) {
    console.error('Migration error:', err.message);
  } finally {
    process.exit(0);
  }
}

runMigration();
