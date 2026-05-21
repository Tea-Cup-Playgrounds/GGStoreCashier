import 'package:dio/dio.dart';
import '../config/api_config.dart';
import 'auth_service.dart';
import 'cache_manager.dart';

Map<String, dynamic> _castMap(dynamic m) =>
    Map<String, dynamic>.from(m as Map);

List<Map<String, dynamic>> _castList(dynamic l) =>
    (l as List).map(_castMap).toList();

class AnalyticsService {
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

  static Future<Map<String, dynamic>> getSummary({bool forceRefresh = false}) async {
    lastFetchWasStale = false;
    const key = 'analytics:summary';

    if (!forceRefresh && CacheManager.isValid(key)) {
      final entry = CacheManager.get(key);
      if (entry != null) {
        return _castMap(entry.data);
      }
    }

    try {
      final dio = await _dio();
      final res = await dio.get('/api/analytics/summary');
      await CacheManager.put(key, res.data);
      return _castMap(res.data);
    } on DioException {
      final entry = CacheManager.get(key);
      if (entry != null) {
        entry.isStale = true;
        lastFetchWasStale = true;
        return _castMap(entry.data);
      }
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getRevenueTrend(int days, {bool forceRefresh = false}) async {
    lastFetchWasStale = false;
    final key = 'analytics:trend_$days';

    if (!forceRefresh && CacheManager.isValid(key)) {
      final entry = CacheManager.get(key);
      if (entry != null) {
        return _castList((_castMap(entry.data))['data']);
      }
    }

    try {
      final dio = await _dio();
      final res = await dio.get('/api/analytics/revenue-trend', queryParameters: {'days': days});
      await CacheManager.put(key, res.data);
      return _castList(res.data['data']);
    } on DioException {
      final entry = CacheManager.get(key);
      if (entry != null) {
        entry.isStale = true;
        lastFetchWasStale = true;
        return _castList((_castMap(entry.data))['data']);
      }
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getBranchRevenue(String date, {bool forceRefresh = false}) async {
    lastFetchWasStale = false;
    final key = 'analytics:branch_$date';

    if (!forceRefresh && CacheManager.isValid(key)) {
      final entry = CacheManager.get(key);
      if (entry != null) {
        return _castList((_castMap(entry.data))['data']);
      }
    }

    try {
      final dio = await _dio();
      final res = await dio.get('/api/analytics/branch-revenue', queryParameters: {'date': date});
      await CacheManager.put(key, res.data);
      return _castList(res.data['data']);
    } on DioException {
      final entry = CacheManager.get(key);
      if (entry != null) {
        entry.isStale = true;
        lastFetchWasStale = true;
        return _castList((_castMap(entry.data))['data']);
      }
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getCategorySales(int days, {bool forceRefresh = false}) async {
    lastFetchWasStale = false;
    final key = 'analytics:category_$days';

    if (!forceRefresh && CacheManager.isValid(key)) {
      final entry = CacheManager.get(key);
      if (entry != null) {
        return _castList((_castMap(entry.data))['data']);
      }
    }

    try {
      final dio = await _dio();
      final res = await dio.get('/api/analytics/category-sales', queryParameters: {'days': days});
      await CacheManager.put(key, res.data);
      return _castList(res.data['data']);
    } on DioException {
      final entry = CacheManager.get(key);
      if (entry != null) {
        entry.isStale = true;
        lastFetchWasStale = true;
        return _castList((_castMap(entry.data))['data']);
      }
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getTopProducts(int days, {bool forceRefresh = false}) async {
    lastFetchWasStale = false;
    final key = 'analytics:top_$days';

    if (!forceRefresh && CacheManager.isValid(key)) {
      final entry = CacheManager.get(key);
      if (entry != null) {
        return _castList((_castMap(entry.data))['data']);
      }
    }

    try {
      final dio = await _dio();
      final res = await dio.get('/api/analytics/top-products', queryParameters: {'days': days});
      await CacheManager.put(key, res.data);
      return _castList(res.data['data']);
    } on DioException {
      final entry = CacheManager.get(key);
      if (entry != null) {
        entry.isStale = true;
        lastFetchWasStale = true;
        return _castList((_castMap(entry.data))['data']);
      }
      rethrow;
    }
  }
}
