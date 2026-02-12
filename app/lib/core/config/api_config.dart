class ApiConfig {
  // API Configuration - Change these values to match your server
  static const String _host = 'localhost';
  static const int _port = 5000;
  static const String _protocol = 'http';
  
  // Computed base URL
  static String get baseUrl => '$_protocol://$_host:$_port';
  
  // Alternative configurations for different environments
  static const Map<String, String> environments = {
    'local_127': 'http://127.0.0.1:5000',
    'local': 'http://localhost:5000',
    'android_emulator': 'http://10.0.2.2:5000',
    'local_alt': 'http://127.0.0.1:5000',
    'local_3000': 'http://localhost:3000',
    'local_8080': 'http://localhost:8080',
    'development': 'http://192.168.1.100:5000',
    'production': 'https://your-domain.com',
  };
  
  // Current environment - change this to switch environments easily
  static const String currentEnvironment = 'local_127';
  
  // Get the API URL for the current environment
  static String get apiUrl {
    return environments[currentEnvironment] ?? baseUrl;
  }
  
  // API endpoints
  static String get loginEndpoint => '$apiUrl/api/auth/login';
  static String get logoutEndpoint => '$apiUrl/api/auth/logout';
  static String get meEndpoint => '$apiUrl/api/auth/me';
  static String get testEndpoint => '$apiUrl/api/test';
  static String get usersEndpoint => '$apiUrl/api/users';
  static String get productsEndpoint => '$apiUrl/api/products';
  static String get categoriesEndpoint => '$apiUrl/api/categories';
  
  // Connection settings
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 10);
  static const Duration sendTimeout = Duration(seconds: 10);
  
  // Debug settings
  static const bool enableLogging = true;
  static const bool enableNetworkLogging = true;
}