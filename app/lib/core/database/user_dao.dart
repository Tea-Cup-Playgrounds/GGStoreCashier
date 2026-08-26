import 'package:sqflite/sqflite.dart';
import 'dart:developer' as dev;
import '../models/user.dart';
import 'app_database.dart';

/// Data Access Object for users — SQLite as the single source of truth.
class UserDao {
  static Future<void> upsert(User user) async {
    final db = await AppDatabase.database;
    await db.insert(
      'users',
      {
        'id': user.id,
        'username': user.username,
        'name': user.name,
        'role': user.role,
        'branch_id': user.branchId,
        'branch_name': null, // populated via JOIN on server; not in model
        'last_active_at': user.lastActiveAt?.toIso8601String(),
        'created_at': user.createdAt.toIso8601String(),
        'updated_at': user.updatedAt.toIso8601String(),
        'synced_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    dev.log('User upserted: ${user.username} (${user.role})', name: 'USER_DAO');
  }

  static Future<void> upsertBatch(List<User> users) async {
    final db = await AppDatabase.database;
    final batch = db.batch();
    for (final u in users) {
      batch.insert(
        'users',
        {
          'id': u.id,
          'username': u.username,
          'name': u.name,
          'role': u.role,
          'branch_id': u.branchId,
          'branch_name': null,
          'last_active_at': u.lastActiveAt?.toIso8601String(),
          'created_at': u.createdAt.toIso8601String(),
          'updated_at': u.updatedAt.toIso8601String(),
          'synced_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    dev.log('Batch upserted ${users.length} users', name: 'USER_DAO');
  }

  static Future<void> delete(int userId) async {
    final db = await AppDatabase.database;
    await db.delete('users', where: 'id = ?', whereArgs: [userId]);
    dev.log('User deleted: $userId', name: 'USER_DAO');
  }

  static Future<List<User>> getAll({int? branchId, String? role}) async {
    final db = await AppDatabase.database;
    String? where;
    List<dynamic>? args;

    if (branchId != null && role != null) {
      where = 'branch_id = ? AND role = ?';
      args = [branchId, role];
    } else if (branchId != null) {
      where = 'branch_id = ?';
      args = [branchId];
    } else if (role != null) {
      where = 'role = ?';
      args = [role];
    }

    final maps = await db.query(
      'users',
      where: where,
      whereArgs: args,
      orderBy: 'last_active_at DESC, name ASC',
    );
    return maps.map(_mapToUser).toList();
  }

  static Future<User?> getById(int userId) async {
    final db = await AppDatabase.database;
    final maps = await db.query('users', where: 'id = ?', whereArgs: [userId], limit: 1);
    if (maps.isEmpty) return null;
    return _mapToUser(maps.first);
  }

  static Future<List<User>> search(String query, {int? branchId}) async {
    final db = await AppDatabase.database;
    final p = '%${query.toLowerCase()}%';
    String where = '(LOWER(name) LIKE ? OR LOWER(username) LIKE ?)';
    List<dynamic> args = [p, p];
    if (branchId != null) {
      where = '$where AND branch_id = ?';
      args.add(branchId);
    }
    final maps = await db.query('users', where: where, whereArgs: args, orderBy: 'name ASC');
    return maps.map(_mapToUser).toList();
  }

  static User _mapToUser(Map<String, dynamic> m) => User(
        id: m['id'] as int,
        name: m['name'] as String? ?? 'Unknown',
        username: m['username'] as String,
        role: m['role'] as String,
        branchId: m['branch_id'] as int?,
        lastActiveAt: m['last_active_at'] != null ? DateTime.parse(m['last_active_at'] as String) : null,
        createdAt: m['created_at'] != null ? DateTime.parse(m['created_at'] as String) : DateTime.now(),
        updatedAt: m['updated_at'] != null ? DateTime.parse(m['updated_at'] as String) : DateTime.now(),
      );
}
