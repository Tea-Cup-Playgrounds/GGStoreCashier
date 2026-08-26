import 'package:sqflite/sqflite.dart';
import 'dart:developer' as dev;
import '../models/superadmin_dashboard.dart' show LiveTransaction;
import 'app_database.dart';

/// Data Access Object for live transactions.
///
/// Uses the same [LiveTransaction] model that the superadmin dashboard widgets
/// already consume — no parallel class needed. SQLite stores only the fields
/// we receive from socket payloads and that the UI needs.
class LiveTransactionDao {
  /// Insert or replace a [LiveTransaction] from a socket payload.
  static Future<void> upsert(LiveTransaction tx) async {
    final db = await AppDatabase.database;
    await db.insert(
      'live_transactions',
      {
        'id': tx.id,
        'branch_id': 0, // enriched from branchName or defaults to 0
        'branch_name': tx.branchName,
        'total_price': tx.finalAmount,
        'payment_method': tx.paymentMethod,
        'item_count': tx.itemCount,
        'user_name': tx.userName,
        'payment_status': tx.paymentStatus,
        'created_at': tx.createdAt.toIso8601String(),
        'synced_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    dev.log('LiveTransaction upserted: ${tx.id}', name: 'LIVE_TX_DAO');
  }

  /// Insert or replace from a raw socket JSON map.
  /// Accepts the full transaction payload from the server.
  static Future<void> upsertFromJson(Map<String, dynamic> json) async {
    final tx = LiveTransaction.fromJson(json);
    await upsert(tx);
  }

  /// Get recent transactions, newest first, optionally filtered by branch name.
  /// [limit] caps at 20 for the live feed.
  static Future<List<LiveTransaction>> getRecent({
    String? branchName,
    int limit = 20,
  }) async {
    final db = await AppDatabase.database;
    final cutoff = DateTime.now().subtract(const Duration(hours: 24)).toIso8601String();

    String where = 'created_at >= ?';
    List<dynamic> args = [cutoff];

    if (branchName != null) {
      where = '$where AND branch_name = ?';
      args.add(branchName);
    }

    final maps = await db.query(
      'live_transactions',
      where: where,
      whereArgs: args,
      orderBy: 'created_at DESC',
      limit: limit,
    );

    return maps.map(_mapToTx).toList();
  }

  /// Get today's total revenue across all branches (or a specific branch).
  static Future<double> getTodayRevenue({String? branchName}) async {
    final db = await AppDatabase.database;
    final todayStart = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day).toIso8601String();

    String where = 'created_at >= ?';
    List<dynamic> args = [todayStart];
    if (branchName != null) {
      where = '$where AND branch_name = ?';
      args.add(branchName);
    }

    final result = await db.rawQuery(
      'SELECT SUM(total_price) as total FROM live_transactions WHERE $where',
      args,
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  /// Get today's transaction count.
  static Future<int> getTodayCount({String? branchName}) async {
    final db = await AppDatabase.database;
    final todayStart = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day).toIso8601String();

    String where = 'created_at >= ?';
    List<dynamic> args = [todayStart];
    if (branchName != null) {
      where = '$where AND branch_name = ?';
      args.add(branchName);
    }

    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM live_transactions WHERE $where',
      args,
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Remove transactions older than 24 h to keep the table lean.
  static Future<void> prune() async {
    final db = await AppDatabase.database;
    final cutoff = DateTime.now().subtract(const Duration(hours: 24)).toIso8601String();
    final n = await db.delete(
      'live_transactions',
      where: 'created_at < ?',
      whereArgs: [cutoff],
    );
    if (n > 0) dev.log('Pruned $n old live_transactions', name: 'LIVE_TX_DAO');
  }

  static LiveTransaction _mapToTx(Map<String, dynamic> m) => LiveTransaction(
        id: m['id'] as int,
        finalAmount: (m['total_price'] as num).toDouble(),
        paymentStatus: m['payment_status'] as String? ?? 'paid',
        paymentMethod: m['payment_method'] as String?,
        itemCount: m['item_count'] as int? ?? 0,
        userName: m['user_name'] as String?,
        branchName: m['branch_name'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}
