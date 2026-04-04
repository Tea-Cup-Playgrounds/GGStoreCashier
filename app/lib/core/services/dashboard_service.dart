import 'package:dio/dio.dart';
import '../config/api_config.dart';
import '../models/dashboard_stats.dart';
import 'auth_service.dart';
import 'cache_manager.dart';

class DashboardService {
  static const String _cacheKey = 'dashboard:stats';

  static bool lastFetchWasStale = false;

  static Future<DashboardStats> getStats({bool forceRefresh = false}) async {
    // Check cache if not forcing refresh
    if (!forceRefresh && CacheManager.isValid(_cacheKey)) {
      final entry = CacheManager.get(_cacheKey);
      if (entry != null) {
        lastFetchWasStale = false;
        return DashboardStats.fromJson(
            Map<String, dynamic>.from(entry.data as Map));
      }
    }

    // Fetch from API
    try {
      final token = await AuthService.getToken();
      final dio = Dio(BaseOptions(
        baseUrl: ApiConfig.apiUrl,
        headers: {
          'Authorization': 'Bearer $token',
          ...ApiConfig.defaultHeaders,
        },
        connectTimeout: ApiConfig.connectTimeout,
        receiveTimeout: ApiConfig.receiveTimeout,
      ));

      final response = await dio.get('/api/dashboard');
      final data = response.data as Map<String, dynamic>;

      await CacheManager.put(_cacheKey, data);
      lastFetchWasStale = false;
      return DashboardStats.fromJson(data);
    } catch (e) {
      // On network failure, try stale cache
      final entry = CacheManager.get(_cacheKey);
      if (entry != null) {
        entry.isStale = true;
        lastFetchWasStale = true;
        return DashboardStats.fromJson(
            Map<String, dynamic>.from(entry.data as Map));
      }
      rethrow;
    }
  }
}
