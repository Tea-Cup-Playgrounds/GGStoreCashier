import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

part 'pending_operations_queue.g.dart';

/// A generic pending API operation stored for offline sync.
@HiveType(typeId: 11)
class PendingOperation extends HiveObject {
  /// Unique ID for this operation.
  @HiveField(0)
  late String id;

  /// HTTP method: 'PUT', 'POST', 'DELETE'.
  @HiveField(1)
  late String method;

  /// Relative API path, e.g. '/api/branches/1'.
  @HiveField(2)
  late String path;

  /// Request body (may be empty for DELETE).
  @HiveField(3)
  late Map<dynamic, dynamic> body;

  /// When the operation was queued.
  @HiveField(4)
  late DateTime createdAt;

  /// Retry count (0–3).
  @HiveField(5)
  late int retryCount;

  /// 'pending' | 'failed'
  @HiveField(6)
  late String status;

  /// Human-readable description shown in snackbars.
  @HiveField(7)
  late String description;
}

class PendingOperationsQueue {
  static const String _boxName = 'pending_ops_box';

  static Box<PendingOperation> get _box =>
      Hive.box<PendingOperation>(_boxName);

  static Future<void> enqueue(PendingOperation op) async {
    await _box.put(op.id, op);
  }

  static List<PendingOperation> getPending() {
    final list = _box.values.where((e) => e.status == 'pending').toList();
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  static Future<void> remove(String id) async {
    await _box.delete(id);
  }

  static Future<void> markFailed(String id) async {
    final op = _box.get(id);
    if (op != null) {
      op.status = 'failed';
      await op.save();
    }
  }

  static int get pendingCount =>
      _box.values.where((e) => e.status == 'pending').length;
}
