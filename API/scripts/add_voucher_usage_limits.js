require('dotenv').config({ path: require('path').resolve(__dirname, '../../.env') });
const pool = require('../src/db');

async function runMigration() {
  try {
    console.log('Running migration: adding max_uses and used_count to vouchers...');

    const [maxUsesCol] = await pool.query("SHOW COLUMNS FROM vouchers LIKE 'max_uses'");
    if (maxUsesCol.length === 0) {
      await pool.query(
        "ALTER TABLE vouchers ADD COLUMN max_uses INT NULL DEFAULT NULL COMMENT 'NULL = unlimited uses' AFTER is_active"
      );
      console.log('Migration: max_uses column added to vouchers.');
    } else {
      console.log('Column max_uses already exists, skipping.');
    }

    const [usedCountCol] = await pool.query("SHOW COLUMNS FROM vouchers LIKE 'used_count'");
    if (usedCountCol.length === 0) {
      await pool.query(
        "ALTER TABLE vouchers ADD COLUMN used_count INT NOT NULL DEFAULT 0 COMMENT 'Incremented on each successful transaction' AFTER max_uses"
      );
      console.log('Migration: used_count column added to vouchers.');
    } else {
      console.log('Column used_count already exists, skipping.');
    }

    console.log('Voucher usage limits migration complete.');
  } catch (err) {
    console.error('Migration error:', err.message);
  } finally {
    process.exit(0);
  }
}

runMigration();
