import 'package:dio/dio.dart';
import '../config/api_config.dart';
import 'auth_service.dart';

class AnalyticsService {
  static Future<Dio> _dio() async {
    final token = await AuthService.getToken();
    return Dio(BaseOptions(
      baseUrl: ApiConfig.apiUrl,
      headers: {'Authorization': 'Bearer $token', ...ApiConfig.defaultHeaders},
      connectTimeout: ApiConfig.connectTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
    ));
  }

  static Future<Map<String, dynamic>> getSummary() async {
    final dio = await _dio();
    final res = await dio.get('/api/analytics/summary');
    return res.data as Map<String, dynamic>;
  }

  static Future<List<Map<String, dynamic>>> getRevenueTrend(int days) async {
    final dio = await _dio();
    final res = await dio.get('/api/analytics/revenue-trend', queryParameters: {'days': days});
    return List<Map<String, dynamic>>.from(res.data['data']);
  }

  static Future<List<Map<String, dynamic>>> getBranchRevenue(String date) async {
    final dio = await _dio();
    final res = await dio.get('/api/analytics/branch-revenue', queryParameters: {'date': date});
    return List<Map<String, dynamic>>.from(res.data['data']);
  }

  static Future<List<Map<String, dynamic>>> getCategorySales(int days) async {
    final dio = await _dio();
    final res = await dio.get('/api/analytics/category-sales', queryParameters: {'days': days});
    return List<Map<String, dynamic>>.from(res.data['data']);
  }

  static Future<List<Map<String, dynamic>>> getTopProducts(int days) async {
    final dio = await _dio();
    final res = await dio.get('/api/analytics/top-products', queryParameters: {'days': days});
    return List<Map<String, dynamic>>.from(res.data['data']);
  }
}
