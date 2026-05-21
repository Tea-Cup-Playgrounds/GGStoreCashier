import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

part 'offline_queue.g.dart';

@HiveType(typeId: 10)
class OfflineTransactionEntry extends HiveObject {
  @HiveField(0)
  late String uuid;

  @HiveField(1)
  late Map<dynamic, dynamic> payload;

  @HiveField(2)
  late DateTime createdAt;

  @HiveField(3)
  late int retryCount;

  @HiveField(4)
  late String status;
}

class OfflineQueue {
  static const String _boxName = 'offline_queue_box';

  static Box<OfflineTransactionEntry> get _box =>
      Hive.box<OfflineTransactionEntry>(_boxName);

  /// Adds an entry to the box using its uuid as the key.
  static Future<void> enqueue(OfflineTransactionEntry entry) async {
    await _box.put(entry.uuid, entry);
  }

  /// Returns all entries with status == 'pending', sorted by createdAt ascending (FIFO).
  static List<OfflineTransactionEntry> getPending() {
    final pending = _box.values
        .where((e) => e.status == 'pending')
        .toList();
    pending.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return pending;
  }

  /// Deletes the entry with the given uuid from the box.
  static Future<void> remove(String uuid) async {
    await _box.delete(uuid);
  }

  /// Sets status = 'failed' on the entry with the given uuid (does NOT remove it).
  static Future<void> markFailed(String uuid) async {
    final entry = _box.get(uuid);
    if (entry != null) {
      entry.status = 'failed';
      await entry.save();
    }
  }

  /// Counts entries with status == 'pending'.
  static int get pendingCount =>
      _box.values.where((e) => e.status == 'pending').length;

  /// Stream that emits the current pending count whenever the Hive box changes.
  static Stream<int> get pendingCountStream =>
      _box.watch().map((_) => pendingCount);
}

/// Reactive provider for the number of pending offline transactions.
/// Listens to Hive box changes so the UI updates automatically.
final pendingOfflineCountProvider = StreamProvider<int>((ref) async* {
  // Emit the current count immediately.
  yield OfflineQueue.pendingCount;
  // Then emit on every box change.
  yield* OfflineQueue.pendingCountStream;
});
