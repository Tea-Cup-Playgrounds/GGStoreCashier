require('dotenv').config({ path: require('path').resolve(__dirname, '../../.env') });
const pool = require('../src/db');

async function runMigration() {
  try {
    console.log('Running migration: adding is_deleted to products...');
    const [columns] = await pool.query("SHOW COLUMNS FROM products LIKE 'is_deleted'");
    if (columns.length === 0) {
      await pool.query(
        "ALTER TABLE products ADD COLUMN is_deleted TINYINT(1) NOT NULL DEFAULT 0 AFTER updated_at"
      );
      console.log('Migration successful: is_deleted column added to products.');
    } else {
      console.log('Column is_deleted already exists, skipping.');
    }
  } catch (err) {
    console.error('Migration error:', err.message);
  } finally {
    process.exit(0);
  }
}

runMigration();
