import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:developer' as dev;

/// SQLite database — single source of truth for real-time data.
///
/// High-frequency data (products, vouchers, users, transactions) is stored here
/// and kept in sync via WebSocket events. UI reads from DB, not from component state.
///
/// Low-frequency data (categories, branches) uses pull-to-refresh and cache only.
class AppDatabase {
  static Database? _database;
  static const String _dbName = 'gg_cashier_local.db';
  static const int _dbVersion = 2;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    dev.log('Initializing SQLite database at: $path', name: 'APP_DATABASE');

    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    dev.log('Creating database tables (version $version)', name: 'APP_DATABASE');

    // ── Products table ──────────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        barcode TEXT,
        category TEXT,
        category_id INTEGER,
        branch_id INTEGER,
        stock INTEGER DEFAULT 0,
        sell_price REAL DEFAULT 0,
        description TEXT,
        product_image TEXT,
        is_low_stock INTEGER DEFAULT 0,
        is_out_of_stock INTEGER DEFAULT 0,
        created_at TEXT,
        updated_at TEXT,
        synced_at INTEGER NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX idx_products_branch ON products(branch_id)');
    await db.execute('CREATE INDEX idx_products_category ON products(category_id)');
    await db.execute('CREATE INDEX idx_products_barcode ON products(barcode)');

    // ── Vouchers table ──────────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE vouchers (
        id INTEGER PRIMARY KEY,
        code TEXT NOT NULL UNIQUE,
        description TEXT,
        target_type TEXT,
        target_id INTEGER,
        discount_type TEXT NOT NULL DEFAULT 'percent',
        discount_value REAL NOT NULL,
        valid_from TEXT,
        valid_to TEXT,
        is_active INTEGER DEFAULT 1,
        max_uses INTEGER,
        used_count INTEGER NOT NULL DEFAULT 0,
        synced_at INTEGER NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX idx_vouchers_code ON vouchers(code)');
    await db.execute('CREATE INDEX idx_vouchers_active ON vouchers(is_active)');

    // ── Users table ─────────────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY,
        username TEXT NOT NULL,
        name TEXT,
        role TEXT NOT NULL,
        branch_id INTEGER,
        branch_name TEXT,
        last_active_at TEXT,
        created_at TEXT,
        updated_at TEXT,
        synced_at INTEGER NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX idx_users_branch ON users(branch_id)');
    await db.execute('CREATE INDEX idx_users_role ON users(role)');

    // ── Live Transactions table ────────────────────────────────────────────
    // Stores recent transactions (last 24h) for real-time dashboard updates
    await db.execute('''
      CREATE TABLE live_transactions (
        id INTEGER PRIMARY KEY,
        branch_id INTEGER NOT NULL DEFAULT 0,
        branch_name TEXT,
        total_price REAL NOT NULL,
        payment_method TEXT,
        payment_status TEXT DEFAULT 'paid',
        item_count INTEGER DEFAULT 0,
        user_name TEXT,
        created_at TEXT NOT NULL,
        synced_at INTEGER NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX idx_live_tx_branch ON live_transactions(branch_id)');
    await db.execute('CREATE INDEX idx_live_tx_created ON live_transactions(created_at)');

    dev.log('Database tables created successfully', name: 'APP_DATABASE');
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    dev.log('Upgrading database from v$oldVersion to v$newVersion', name: 'APP_DATABASE');
    if (oldVersion < 2) {
      // v2: add max_uses and used_count to vouchers
      final cols = await db.rawQuery("PRAGMA table_info(vouchers)");
      final colNames = cols.map((c) => c['name'] as String).toSet();
      if (!colNames.contains('max_uses')) {
        await db.execute('ALTER TABLE vouchers ADD COLUMN max_uses INTEGER');
      }
      if (!colNames.contains('used_count')) {
        await db.execute('ALTER TABLE vouchers ADD COLUMN used_count INTEGER NOT NULL DEFAULT 0');
      }
      dev.log('v2 migration applied: max_uses + used_count added to vouchers', name: 'APP_DATABASE');
    }
  }

  /// Clear all data (used on logout or branch switch)
  static Future<void> clearAll() async {
    final db = await database;
    await db.delete('products');
    await db.delete('vouchers');
    await db.delete('users');
    await db.delete('live_transactions');
    dev.log('All database tables cleared', name: 'APP_DATABASE');
  }

  /// Clear old live transactions (older than 24h)
  static Future<void> pruneOldTransactions() async {
    final db = await database;
    final cutoff = DateTime.now().subtract(const Duration(hours: 24)).toIso8601String();
    final deleted = await db.delete(
      'live_transactions',
      where: 'created_at < ?',
      whereArgs: [cutoff],
    );
    if (deleted > 0) {
      dev.log('Pruned $deleted old transactions', name: 'APP_DATABASE');
    }
  }

  /// Close database connection
  static Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      dev.log('Database connection closed', name: 'APP_DATABASE');
    }
  }
}
