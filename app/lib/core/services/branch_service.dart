import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import '../config/api_config.dart';
import '../models/branch.dart';
import 'auth_service.dart';
import 'cache_manager.dart';
import 'connectivity_monitor.dart';
import 'pending_operations_queue.dart';

class BranchService {
  static bool lastFetchWasStale = false;

  static Future<Dio> _dio() async {
    final token = await AuthService.getToken();
    return Dio(BaseOptions(
      baseUrl: ApiConfig.apiUrl,
      headers: {
        'Authorization': 'Bearer $token',
        ...ApiConfig.defaultHeaders,
      },
      connectTimeout: ApiConfig.connectTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
    ));
  }

  /// Fetch a single branch by id. Returns cached data when offline.
  static Future<Branch> getBranch(int id, {bool forceRefresh = false}) async {
    lastFetchWasStale = false;
    final key = 'branch:$id';

    if (!forceRefresh && CacheManager.isValid(key)) {
      final entry = CacheManager.get(key);
      if (entry != null) {
        return Branch.fromJson(Map<String, dynamic>.from(entry.data as Map));
      }
    }

    try {
      final dio = await _dio();
      final response = await dio.get('/api/branches/$id');
      await CacheManager.put(key, response.data['branch'],
          ttl: const Duration(minutes: 10));
      return Branch.fromJson(response.data['branch']);
    } on DioException {
      final entry = CacheManager.get(key);
      if (entry != null) {
        entry.isStale = true;
        lastFetchWasStale = true;
        return Branch.fromJson(Map<String, dynamic>.from(entry.data as Map));
      }
      final isOffline =
          ConnectivityMonitor.instance.currentStatus == ConnectivityStatus.offline;
      throw Exception(isOffline
          ? 'Kamu sedang offline dan belum ada data tersimpan untuk cabang ini.'
          : 'Gagal memuat data cabang. Coba lagi.');
    }
  }

  /// Fetch all branches (superadmin).
  static Future<List<Branch>> getBranches() async {
    final dio = await _dio();
    final response = await dio.get('/api/branches');
    final list = response.data['branches'] as List;
    return list.map((e) => Branch.fromJson(e)).toList();
  }

  /// Update branch fields.
  /// When offline: queues the operation and updates the local cache optimistically.
  /// Returns true if saved online, false if queued for later sync.
  static Future<bool> updateBranch(
      int id, String name, String? address, String? phone) async {
    final body = <String, dynamic>{
      'name': name,
      if (address != null) 'address': address,
      if (phone != null) 'phone': phone,
    };

    final isOffline =
        ConnectivityMonitor.instance.currentStatus == ConnectivityStatus.offline;

    if (isOffline) {
      // Optimistically update the local cache so the page reflects the change.
      final cacheKey = 'branch:$id';
      final existing = CacheManager.get(cacheKey);
      final currentData = existing != null
          ? Map<String, dynamic>.from(existing.data as Map)
          : <String, dynamic>{'id': id};
      currentData['name'] = name;
      currentData['address'] = address;
      currentData['phone'] = phone;
      await CacheManager.put(cacheKey, currentData,
          ttl: const Duration(minutes: 10));

      // Queue for sync when back online.
      final op = PendingOperation()
        ..id = const Uuid().v4()
        ..method = 'PUT'
        ..path = '/api/branches/$id'
        ..body = body
        ..createdAt = DateTime.now()
        ..retryCount = 0
        ..status = 'pending'
        ..description = 'Perubahan cabang';
      await PendingOperationsQueue.enqueue(op);
      return false; // queued
    }

    final dio = await _dio();
    await dio.put('/api/branches/$id', data: body);
    // Invalidate cache so next load fetches fresh data.
    await CacheManager.invalidate('branch:$id');
    return true; // saved online
  }
}
