import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
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
      headers: {'Authorization': 'Bearer $token', ...ApiConfig.defaultHeaders},
      connectTimeout: ApiConfig.connectTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
    ));
  }

  static Future<Branch> getBranch(int id, {bool forceRefresh = false}) async {
    lastFetchWasStale = false;
    final key = 'branch:$id';
    if (!forceRefresh && CacheManager.isValid(key)) {
      final entry = CacheManager.get(key);
      if (entry != null) return Branch.fromJson(Map<String, dynamic>.from(entry.data as Map));
    }
    try {
      final dio = await _dio();
      final res = await dio.get('/api/branches/$id');
      await CacheManager.put(key, res.data['branch'], ttl: const Duration(minutes: 10));
      return Branch.fromJson(res.data['branch']);
    } on DioException {
      final entry = CacheManager.get(key);
      if (entry != null) {
        entry.isStale = true;
        lastFetchWasStale = true;
        return Branch.fromJson(Map<String, dynamic>.from(entry.data as Map));
      }
      final offline = ConnectivityMonitor.instance.currentStatus == ConnectivityStatus.offline;
      throw Exception(
          offline ? 'Kamu sedang offline dan belum ada data tersimpan.' : 'Gagal memuat data cabang. Coba lagi.');
    }
  }

  static Future<List<Branch>> getBranches() async {
    final dio = await _dio();
    final res = await dio.get('/api/branches');
    final list = res.data['branches'] as List;
    return list.map((e) => Branch.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  /// Update branch. Returns true if saved online, false if queued offline.
  static Future<bool> updateBranch(
    int id,
    String name,
    String? address,
    String? phone, {
    double? targetPendapatan,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'address': address,
      'phone': phone,
      'target_pendapatan': targetPendapatan,
    };

    final isOffline = ConnectivityMonitor.instance.currentStatus == ConnectivityStatus.offline;
    if (isOffline) {
      final cacheKey = 'branch:$id';
      final existing = CacheManager.get(cacheKey);
      final data = existing != null ? Map<String, dynamic>.from(existing.data as Map) : <String, dynamic>{'id': id};
      data['name'] = name;
      data['address'] = address;
      data['phone'] = phone;
      data['target_pendapatan'] = targetPendapatan;
      await CacheManager.put(cacheKey, data, ttl: const Duration(minutes: 10));
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
      return false;
    }
    final dio = await _dio();
    await dio.put('/api/branches/$id', data: body);
    await CacheManager.invalidate('branch:$id');
    return true;
  }

  /// Delete a branch (superadmin only).
  static Future<void> deleteBranch(int id) async {
    final dio = await _dio();
    await dio.delete('/api/branches/$id');
    await CacheManager.invalidate('branch:$id');
  }

  /// Create branch + admin user atomically.
  static Future<Map<String, dynamic>> createBranchWithAdmin({
    required String name,
    String? address,
    String? phone,
    double? targetPendapatan,
    required String adminName,
    required String adminUsername,
    required String adminPassword,
  }) async {
    final dio = await _dio();
    final res = await dio.post('/api/branches/with-admin', data: {
      'name': name,
      'address': address,
      'phone': phone,
      'target_pendapatan': targetPendapatan,
      'admin': {
        'name': adminName,
        'username': adminUsername,
        'password': adminPassword,
      },
    });
    return Map<String, dynamic>.from(res.data as Map);
  }
}
