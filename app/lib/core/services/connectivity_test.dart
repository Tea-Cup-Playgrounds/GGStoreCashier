import 'package:dio/dio.dart';
import '../config/api_config.dart';

class ConnectivityTest {
  static final _dio = Dio(BaseOptions(
    baseUrl: ApiConfig.apiUrl,
    connectTimeout: ApiConfig.connectTimeout,
    receiveTimeout: ApiConfig.receiveTimeout,
  ));

  static Future<bool> testConnection() async {
    try {
      if (ApiConfig.enableLogging) {
        print('=== CONNECTIVITY TEST ===');
        print('Testing connection to: ${ApiConfig.testEndpoint}');
        print('Current environment: ${ApiConfig.currentEnvironment}');
        print('Available environments: ${ApiConfig.environments.keys.join(', ')}');
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
        print('Test response status: ${response.statusCode}');
        print('Test response data: ${response.data}');
      }

      return response.statusCode == 200;
    } catch (e) {
      if (ApiConfig.enableLogging) {
        print('=== CONNECTIVITY TEST FAILED ===');
        print('Error: $e');
        print('Current API URL: ${ApiConfig.apiUrl}');
        print('Try changing the environment in ApiConfig.currentEnvironment');
        print('Available options: ${ApiConfig.environments.keys.join(', ')}');
      }
      
      if (e is DioException) {
        if (ApiConfig.enableLogging) {
          print('DioException type: ${e.type}');
          print('DioException message: ${e.message}');
          print('Response: ${e.response?.data}');
        }
      }
      return false;
    }
  }
}