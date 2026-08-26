import 'package:sqflite/sqflite.dart';
import 'dart:developer' as dev;
import '../models/voucher.dart';
import 'app_database.dart';

/// Data Access Object for vouchers — SQLite as the single source of truth.
class VoucherDao {
  static Future<void> upsert(Voucher voucher) async {
    final db = await AppDatabase.database;
    await db.insert(
      'vouchers',
      {
        'id': voucher.id,
        'code': voucher.code,
        'description': voucher.description,
        'target_type': voucher.targetType,
        'target_id': voucher.targetId,
        'discount_type': voucher.discountType,
        'discount_value': voucher.discountValue,
        'valid_from': voucher.validFrom,
        'valid_to': voucher.validTo,
        'is_active': voucher.isActive ? 1 : 0,
        'max_uses': voucher.maxUses,
        'used_count': voucher.usedCount,
        'synced_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    dev.log('Voucher upserted: ${voucher.code}', name: 'VOUCHER_DAO');
  }

  static Future<void> upsertBatch(List<Voucher> vouchers) async {
    final db = await AppDatabase.database;
    final batch = db.batch();
    for (final v in vouchers) {
      batch.insert(
        'vouchers',
        {
          'id': v.id,
          'code': v.code,
          'description': v.description,
          'target_type': v.targetType,
          'target_id': v.targetId,
          'discount_type': v.discountType,
          'discount_value': v.discountValue,
          'valid_from': v.validFrom,
          'valid_to': v.validTo,
          'is_active': v.isActive ? 1 : 0,
          'max_uses': v.maxUses,
          'used_count': v.usedCount,
          'synced_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    dev.log('Batch upserted ${vouchers.length} vouchers', name: 'VOUCHER_DAO');
  }

  static Future<void> delete(int voucherId) async {
    final db = await AppDatabase.database;
    await db.delete('vouchers', where: 'id = ?', whereArgs: [voucherId]);
    dev.log('Voucher deleted: $voucherId', name: 'VOUCHER_DAO');
  }

  static Future<List<Voucher>> getAll({bool? activeOnly}) async {
    final db = await AppDatabase.database;
    final maps = activeOnly == true
        ? await db.query('vouchers', where: 'is_active = ?', whereArgs: [1], orderBy: 'valid_to DESC')
        : await db.query('vouchers', orderBy: 'id DESC');
    return maps.map(_mapToVoucher).toList();
  }

  static Future<Voucher?> getByCode(String code) async {
    final db = await AppDatabase.database;
    final maps = await db.query('vouchers', where: 'code = ?', whereArgs: [code], limit: 1);
    if (maps.isEmpty) return null;
    return _mapToVoucher(maps.first);
  }

  static Voucher _mapToVoucher(Map<String, dynamic> m) => Voucher(
        id: m['id'] as int,
        code: m['code'] as String,
        description: m['description'] as String?,
        targetType: m['target_type'] as String?,
        targetId: m['target_id'] as int?,
        discountType: m['discount_type'] as String? ?? 'percent',
        discountValue: (m['discount_value'] as num).toDouble(),
        validFrom: m['valid_from'] as String?,
        validTo: m['valid_to'] as String?,
        isActive: (m['is_active'] as int) == 1,
        maxUses: m['max_uses'] as int?,
        usedCount: (m['used_count'] as int?) ?? 0,
      );
}
