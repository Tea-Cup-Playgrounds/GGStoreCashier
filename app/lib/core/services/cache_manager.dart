import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

part 'cache_manager.g.dart';

@HiveType(typeId: 8)
class CacheEntry extends HiveObject {
  @HiveField(0)
  String key;

  @HiveField(1)
  dynamic data;

  @HiveField(2)
  DateTime storedAt;

  @HiveField(3)
  int ttlSeconds;

  @HiveField(4)
  bool isStale;

  CacheEntry({
    required this.key,
    required this.data,
    required this.storedAt,
    required this.ttlSeconds,
    this.isStale = false,
  });

  bool get isExpired =>
      DateTime.now().isAfter(storedAt.add(Duration(seconds: ttlSeconds)));
}

class CacheManager {
  static const String _boxName = 'cache_box';
  static const Duration defaultTtl = Duration(minutes: 5);

  static Box<CacheEntry> get _box => Hive.box<CacheEntry>(_boxName);

  static Future<void> put(
    String key,
    dynamic data, {
    Duration ttl = defaultTtl,
  }) async {
    final entry = CacheEntry(
      key: key,
      data: data,
      storedAt: DateTime.now(),
      ttlSeconds: ttl.inSeconds,
    );
    await _box.put(key, entry);
  }

  static CacheEntry? get(String key) {
    return _box.get(key);
  }

  static bool isValid(String key) {
    final entry = _box.get(key);
    return entry != null && !entry.isExpired;
  }

  static Future<void> invalidate(String key) async {
    await _box.delete(key);
  }

  static Future<void> clear() async {
    await _box.clear();
  }
}
