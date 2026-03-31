import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConfig {
  static String get apiUrl => dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:5000';

  // API endpoints
  static String get loginEndpoint => '$apiUrl/api/auth/login';
  static String get logoutEndpoint => '$apiUrl/api/auth/logout';
  static String get meEndpoint => '$apiUrl/api/auth/me';
  static String get testEndpoint => '$apiUrl/api/test';
  static String get usersEndpoint => '$apiUrl/api/users';
  static String get productsEndpoint => '$apiUrl/api/products';
  static String get categoriesEndpoint => '$apiUrl/api/categories';

  // Default headers for all requests (includes ngrok bypass header)
  static Map<String, String> get defaultHeaders => {
    'ngrok-skip-browser-warning': 'true',
  };

  // Connection settings
  static Duration get connectTimeout {
    final timeoutStr = dotenv.env['API_TIMEOUT'] ?? '10';
    final seconds = int.tryParse(timeoutStr) ?? 10;
    return Duration(seconds: seconds);
  }
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration sendTimeout = Duration(seconds: 30);

  // Debug settings — disabled in release
  static const bool enableLogging = bool.fromEnvironment('dart.vm.product') == false;
  static const bool enableNetworkLogging = bool.fromEnvironment('dart.vm.product') == false;
}
