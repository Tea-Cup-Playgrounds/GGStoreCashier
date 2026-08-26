import 'package:dio/dio.dart';
import '../config/api_config.dart';
import '../models/superadmin_dashboard.dart';
import 'auth_service.dart';
import 'cache_manager.dart';

class SuperadminDashboardService {
  static bool lastHighFreqWasStale = false;
  static bool lastLowFreqWasStale = false;

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

  // ── High-frequency data ─────────────────────────────────────────────────────
  // Called once on initial load. Subsequent updates come via socket events.
  static Future<HighFreqDashboard> getHighFreq({bool forceRefresh = false}) async {
    lastHighFreqWasStale = false;
    const key = 'sadmin:high_freq';

    if (!forceRefresh && CacheManager.isValid(key)) {
      final entry = CacheManager.get(key);
      if (entry != null) {
        return HighFreqDashboard.fromJson(Map<String, dynamic>.from(entry.data as Map));
      }
    }

    try {
      final dio = await _dio();
      final res = await dio.get('/api/superadmin-dashboard/high-freq');
      final data = Map<String, dynamic>.from(res.data as Map);
      // Short TTL — 30 s — because it's live data and socket keeps it fresh
      await CacheManager.put(key, data, ttl: const Duration(seconds: 30));
      return HighFreqDashboard.fromJson(data);
    } on DioException {
      final entry = CacheManager.get(key);
      if (entry != null) {
        entry.isStale = true;
        lastHighFreqWasStale = true;
        return HighFreqDashboard.fromJson(Map<String, dynamic>.from(entry.data as Map));
      }
      rethrow;
    }
  }

  // ── Low-frequency data ──────────────────────────────────────────────────────
  // Refreshed every 3 minutes or on pull-to-refresh.
  static Future<LowFreqDashboard> getLowFreq({
    String trendType = 'hourly',
    bool forceRefresh = false,
  }) async {
    lastLowFreqWasStale = false;
    final key = 'sadmin:low_freq_$trendType';

    if (!forceRefresh && CacheManager.isValid(key)) {
      final entry = CacheManager.get(key);
      if (entry != null) {
        return LowFreqDashboard.fromJson(Map<String, dynamic>.from(entry.data as Map));
      }
    }

    try {
      final dio = await _dio();
      final res = await dio.get(
        '/api/superadmin-dashboard/low-freq',
        queryParameters: {'trend': trendType},
      );
      final data = Map<String, dynamic>.from(res.data as Map);
      await CacheManager.put(key, data, ttl: const Duration(minutes: 2, seconds: 45));
      return LowFreqDashboard.fromJson(data);
    } on DioException {
      final entry = CacheManager.get(key);
      if (entry != null) {
        entry.isStale = true;
        lastLowFreqWasStale = true;
        return LowFreqDashboard.fromJson(Map<String, dynamic>.from(entry.data as Map));
      }
      rethrow;
    }
  }

  // ── Stock detail ─────────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getStockDetail(String type) async {
    try {
      final dio = await _dio();
      final res = await dio.get(
        '/api/superadmin-dashboard/stock-detail',
        queryParameters: {'type': type},
      );
      final list = res.data['products'] as List? ?? [];
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }
}
