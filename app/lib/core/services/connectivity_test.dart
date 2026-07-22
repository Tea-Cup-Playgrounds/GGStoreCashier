import 'package:dio/dio.dart';
import 'dart:developer' as dev;
import '../config/api_config.dart';

class ConnectivityTest {
  static final _dio = Dio(BaseOptions(
    baseUrl: ApiConfig.apiUrl,
    connectTimeout: ApiConfig.connectTimeout,
    receiveTimeout: ApiConfig.receiveTimeout,
    headers: ApiConfig.defaultHeaders,
  ));

  static Future<bool> testConnection() async {
    try {
      if (ApiConfig.enableLogging) {
        dev.log('=== CONNECTIVITY TEST ===');
        dev.log('Testing connection to: ${ApiConfig.testEndpoint}');
      }

      final response = await _dio.get(
        '/api/test',
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
        ),
      );

      if (ApiConfig.enableLogging) {
        dev.log('Test response status: ${response.statusCode}');
        dev.log('Test response data: ${response.data}');
      }

      return response.statusCode == 200;
    } catch (e) {
      if (ApiConfig.enableLogging) {
        dev.log('=== CONNECTIVITY TEST FAILED ===');
        dev.log('Error: $e');
        dev.log('Current API URL: ${ApiConfig.apiUrl}');
        dev.log('Try changing the environment in ApiConfig.currentEnvironment');
      }

      if (e is DioException) {
        if (ApiConfig.enableLogging) {
          dev.log('DioException type: ${e.type}');
          dev.log('DioException message: ${e.message}');
          dev.log('Response: ${e.response?.data}');
        }
      }
      return false;
    }
  }
}
