// Offline queue: older app versions stored 5 fields per sale; the queue must still read those after
// the update (a phone may have unsent sales when it is updated). Run: flutter test test/offline_queue_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gg_store_cashier/core/models/cart_item.dart';
import 'package:gg_store_cashier/core/models/product.dart';
import 'package:gg_store_cashier/core/services/offline_queue.dart';
import 'package:hive/hive.dart';
// ignore: implementation_imports
import 'package:hive/src/hive_impl.dart';

/// The queue entry as the previous app version stored it (fields 0–4 only).
class _LegacyEntry {
  final String uuid;
  final Map<dynamic, dynamic> payload;
  final DateTime createdAt;
  final int retryCount;
  final String status;
  _LegacyEntry(this.uuid, this.payload, this.createdAt, this.retryCount, this.status);
}

class _LegacyAdapter extends TypeAdapter<_LegacyEntry> {
  @override
  final int typeId = 10;

  @override
  _LegacyEntry read(BinaryReader reader) => throw UnimplementedError();

  @override
  void write(BinaryWriter writer, _LegacyEntry obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.uuid)
      ..writeByte(1)
      ..write(obj.payload)
      ..writeByte(2)
      ..write(obj.createdAt)
      ..writeByte(3)
      ..write(obj.retryCount)
      ..writeByte(4)
      ..write(obj.status);
  }
}

Map<String, dynamic> _sale({String? shift, double? total, List<Map<String, dynamic>>? lines}) => {
      'id': 'x',
      'location_id': 2,
      if (shift != null) 'cash_session_id': shift,
      if (total != null) 'charged_total': total,
      'lines': lines ?? [
        {'variant_id': 1, 'qty': 2},
        {'variant_id': 7, 'unit_ids': ['u1', 'u2', 'u3']},
        {'variant_id': 9, 'unit_price': 50000},
      ],
    };

OfflineTransactionEntry _entry(String uuid, Map<String, dynamic> payload, {String status = 'pending'}) =>
    OfflineTransactionEntry()
      ..uuid = uuid
      ..payload = payload
      ..createdAt = DateTime(2026, 11, 14, 10)
      ..retryCount = 0
      ..status = status;

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('gg_queue_test'));
  tearDown(() async {
    await Hive.close();
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('sales saved by the previous app version still load', () async {
    final legacy = HiveImpl()..init(dir.path);
    legacy.registerAdapter(_LegacyAdapter());
    final oldBox = await legacy.openBox<_LegacyEntry>('offline_queue_box');
    await oldBox.put('sale-1', _LegacyEntry('sale-1', _sale(), DateTime(2026, 11, 1), 1, 'pending'));
    await legacy.close();

    final current = HiveImpl()..init(dir.path);
    current.registerAdapter(OfflineTransactionEntryAdapter());
    final box = await current.openBox<OfflineTransactionEntry>('offline_queue_box');
    final entry = box.get('sale-1')!;
    expect(entry.uuid, 'sale-1');
    expect(entry.retryCount, 1);
    expect(entry.status, 'pending');
    expect(entry.lastError, isNull);
    expect(entry.lastAttemptAt, isNull);
    expect(entry.chargedTotal, isNull);
    expect(entry.itemCount, 6);
    await current.close();
  });

  test('error message and last attempt are kept', () async {
    final hive = HiveImpl()..init(dir.path);
    hive.registerAdapter(OfflineTransactionEntryAdapter());
    var box = await hive.openBox<OfflineTransactionEntry>('offline_queue_box');
    final when = DateTime(2026, 11, 14, 12, 30);
    await box.put('s', _entry('s', _sale(total: 85000))
      ..lastError = 'Penjualan offline hanya bisa dibayar tunai'
      ..lastAttemptAt = when
      ..status = 'failed');
    await box.close();
    box = await hive.openBox<OfflineTransactionEntry>('offline_queue_box');
    final entry = box.get('s')!;
    expect(entry.isFailed, isTrue);
    expect(entry.lastError, 'Penjualan offline hanya bisa dibayar tunai');
    expect(entry.lastAttemptAt, when);
    expect(entry.chargedTotal, 85000);
    await hive.close();
  });

  test('queue counts, retry, and unsent sales per shift', () async {
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(10)) Hive.registerAdapter(OfflineTransactionEntryAdapter());
    await Hive.openBox<OfflineTransactionEntry>('offline_queue_box');

    await OfflineQueue.enqueue(_entry('a', _sale(shift: 'shift-1')));
    await OfflineQueue.enqueue(_entry('b', _sale(shift: 'shift-1'), status: 'failed'));
    await OfflineQueue.enqueue(_entry('c', _sale(shift: 'shift-2')));

    expect(OfflineQueue.pendingCount, 2);
    expect(OfflineQueue.failedCount, 1);
    expect(OfflineQueue.unsyncedCount, 3);
    expect(OfflineQueue.unsyncedForShift('shift-1'), 2, reason: 'a failed sale still blocks closing its shift');
    expect(OfflineQueue.getPending().map((e) => e.uuid), ['a', 'c']);

    await OfflineQueue.retry('b');
    expect(OfflineQueue.failedCount, 0);
    expect(OfflineQueue.box.get('b')!.retryCount, 0);

    await OfflineQueue.remove('a');
    expect(OfflineQueue.unsyncedForShift('shift-1'), 1);
  });

  test('a cart line sends its price only when asked (offline sale priced on the device)', () {
    final now = DateTime(2026);
    final charger = Product(id: '12', name: 'Charger', costPrice: 0, sellPrice: 85000, stock: 3, createdAt: now, updatedAt: now);
    final pulsa = Product(id: '20', name: 'Pulsa', costPrice: 0, sellPrice: 0, stock: 0, createdAt: now, updatedAt: now, kind: 'digital');
    final line = CartItem.fromProduct(charger, quantity: 2);
    expect(line.toSaleLine(), {'variant_id': 12, 'qty': 2});
    expect(line.toSaleLine(withPrice: true), {'variant_id': 12, 'qty': 2, 'unit_price': 85000.0});
    final topUp = CartItem(id: '20-x', product: pulsa, quantity: 1, price: 25000, note: '0812');
    expect(topUp.toSaleLine(), {'variant_id': 20, 'qty': 1, 'unit_price': 25000.0, 'description': '0812'});
  });
}
