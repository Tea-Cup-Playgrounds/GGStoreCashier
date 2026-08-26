import 'package:dio/dio.dart';
import '../config/api_config.dart';
import 'auth_service.dart';
import 'cache_manager.dart';

class AdminTrendPoint {
  final String label;
  final double revenue;
  final int txCount;
  const AdminTrendPoint({required this.label, required this.revenue, required this.txCount});

  factory AdminTrendPoint.fromJson(Map<String, dynamic> j) => AdminTrendPoint(
        label: j['label']?.toString() ?? '',
        revenue: (j['revenue'] as num?)?.toDouble() ?? 0,
        txCount: (j['tx_count'] as num?)?.toInt() ?? 0,
      );
}

class AdminDashboardData {
  final String branchName;
  final double todayRevenue;
  final int todayTxCount;
  final double targetPendapatan;
  final double cashTotal;
  final double digitalTotal;
  final String trendType;
  final List<AdminTrendPoint> trend;

  const AdminDashboardData({
    required this.branchName,
    required this.todayRevenue,
    required this.todayTxCount,
    required this.targetPendapatan,
    required this.cashTotal,
    required this.digitalTotal,
    required this.trendType,
    required this.trend,
  });

  factory AdminDashboardData.fromJson(Map<String, dynamic> j) {
    double d(dynamic v) => (v as num?)?.toDouble() ?? 0;
    int i(dynamic v) => (v as num?)?.toInt() ?? 0;
    final trendBlock = j['trend'] as Map? ?? {};
    return AdminDashboardData(
      branchName: j['branchName']?.toString() ?? '',
      todayRevenue: d(j['todayRevenue']),
      todayTxCount: i(j['todayTxCount']),
      targetPendapatan: d(j['targetPendapatan']),
      cashTotal: d(j['cashTotal']),
      digitalTotal: d(j['digitalTotal']),
      trendType: trendBlock['type']?.toString() ?? 'hourly',
      trend: ((trendBlock['data'] as List?) ?? [])
          .map((e) => AdminTrendPoint.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}

class AdminDashboardService {
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

  static Future<AdminDashboardData> get({
    String trendType = 'hourly',
    bool forceRefresh = false,
  }) async {
    lastFetchWasStale = false;
    final key = 'admin_dashboard:$trendType';
    if (!forceRefresh && CacheManager.isValid(key)) {
      final entry = CacheManager.get(key);
      if (entry != null) {
        return AdminDashboardData.fromJson(Map<String, dynamic>.from(entry.data as Map));
      }
    }
    try {
      final dio = await _dio();
      final res = await dio.get('/api/dashboard/admin', queryParameters: {'trend': trendType});
      final data = Map<String, dynamic>.from(res.data as Map);
      await CacheManager.put(key, data, ttl: const Duration(minutes: 1));
      return AdminDashboardData.fromJson(data);
    } on DioException {
      final entry = CacheManager.get(key);
      if (entry != null) {
        entry.isStale = true;
        lastFetchWasStale = true;
        return AdminDashboardData.fromJson(Map<String, dynamic>.from(entry.data as Map));
      }
      rethrow;
    }
  }
}
