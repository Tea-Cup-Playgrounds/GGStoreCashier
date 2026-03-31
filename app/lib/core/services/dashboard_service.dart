import 'package:dio/dio.dart';
import '../config/api_config.dart';
import '../models/dashboard_stats.dart';
import 'auth_service.dart';

class DashboardService {
  static Future<DashboardStats> getStats() async {
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
    return DashboardStats.fromJson(response.data as Map<String, dynamic>);
  }
}
