import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

part 'offline_queue.g.dart';

/// A sale made on this device that the server doesn't have yet. [payload] is the full
/// POST /api/sales body, including its own id, so sending it twice can't create two sales.
@HiveType(typeId: 10)
class OfflineTransactionEntry extends HiveObject {
  @HiveField(0)
  late String uuid;

  @HiveField(1)
  late Map<dynamic, dynamic> payload;

  @HiveField(2)
  late DateTime createdAt;

  /// Times the server refused it (not counting attempts that couldn't reach the server).
  @HiveField(3)
  late int retryCount;

  /// 'pending' (will be sent) | 'failed' (the server refused it; needs a person to look at it).
  @HiveField(4)
  late String status;

  /// The server's message the last time it refused the sale.
  @HiveField(5)
  String? lastError;

  /// The last time the server was reached for this sale.
  @HiveField(6)
  DateTime? lastAttemptAt;

  bool get isFailed => status == 'failed';

  /// Total the customer was charged (sent by newer app versions; older entries don't have it).
  double? get chargedTotal => (payload['charged_total'] as num?)?.toDouble();

  int? get locationId => (payload['location_id'] as num?)?.toInt();

  String? get cashSessionId => payload['cash_session_id']?.toString();

  String? get cashierName => payload['cashier_name']?.toString();

  /// Number of items in the sale.
  int get itemCount => ((payload['lines'] as List?) ?? const []).fold<int>(0, (sum, line) {
        final l = line as Map;
        final units = l['unit_ids'] as List?;
        return sum + (units?.length ?? (l['qty'] as num?)?.toInt() ?? 1);
      });
}

class OfflineQueue {
  static const String _boxName = 'offline_queue_box';

  static Box<OfflineTransactionEntry> get box => Hive.box<OfflineTransactionEntry>(_boxName);

  /// Adds an entry to the box using its uuid as the key.
  static Future<void> enqueue(OfflineTransactionEntry entry) async {
    await box.put(entry.uuid, entry);
  }

  /// Returns all entries with status == 'pending', sorted by createdAt ascending (FIFO).
  static List<OfflineTransactionEntry> getPending() {
    final pending = box.values.where((e) => e.status == 'pending').toList();
    pending.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return pending;
  }

  /// Every sale not on the server yet (waiting and failed), oldest first.
  static List<OfflineTransactionEntry> getAll() {
    final all = box.values.toList();
    all.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return all;
  }

  /// Deletes the entry with the given uuid from the box.
  static Future<void> remove(String uuid) async {
    await box.delete(uuid);
  }

  /// Sets status = 'failed' on the entry with the given uuid (does NOT remove it).
  static Future<void> markFailed(String uuid) async {
    final entry = box.get(uuid);
    if (entry != null) {
      entry.status = 'failed';
      await entry.save();
    }
  }

  /// Puts a failed sale back in line to be sent again.
  static Future<void> retry(String uuid) async {
    final entry = box.get(uuid);
    if (entry != null) {
      entry
        ..status = 'pending'
        ..retryCount = 0;
      await entry.save();
    }
  }

  /// Counts entries with status == 'pending'.
  static int get pendingCount => box.values.where((e) => e.status == 'pending').length;

  /// Counts entries the server refused.
  static int get failedCount => box.values.where((e) => e.isFailed).length;

  /// Every sale on this device that the server doesn't have yet, failed ones included.
  static int get unsyncedCount => box.length;

  /// Unsent sales that belong to a cash shift. The shift can't be closed until they are sent,
  /// or the cash count would miss them.
  static int unsyncedForShift(String cashSessionId) =>
      box.values.where((e) => e.cashSessionId == cashSessionId).length;

  /// Stream that emits the number of unsent sales whenever the Hive box changes.
  static Stream<int> get unsyncedCountStream => box.watch().map((_) => unsyncedCount);
}

/// Number of sales on this device the server doesn't have yet (waiting or failed). Shown as a
/// badge on the cashier tab; it updates by itself as the Hive box changes.
final pendingOfflineCountProvider = StreamProvider<int>((ref) async* {
  yield OfflineQueue.unsyncedCount;
  yield* OfflineQueue.unsyncedCountStream;
});
