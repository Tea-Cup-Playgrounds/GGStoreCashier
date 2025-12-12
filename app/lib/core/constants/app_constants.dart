class AppConstants {
  // App Info
  static const String appName = 'GG Store Cashier';
  static const String appVersion = '1.0.0';
  
  // API Configuration
  static const String baseUrl = 'http://localhost:5000/api';
  
  // Storage Keys
  static const String tokenKey = 'auth_token';
  static const String userKey = 'user_data';
  static const String cartKey = 'cart_data';
  static const String settingsKey = 'app_settings';
  
  // Animation Durations
  static const Duration shortAnimation = Duration(milliseconds: 200);
  static const Duration mediumAnimation = Duration(milliseconds: 300);
  static const Duration longAnimation = Duration(milliseconds: 500);
  
  // UI Constants
  static const double defaultPadding = 16.0;
  static const double smallPadding = 8.0;
  static const double largePadding = 24.0;
  static const double borderRadius = 12.0;
  static const double cardRadius = 16.0;
  
  // Grid Constants
  static const int productsPerRow = 2;
  static const double productCardAspectRatio = 0.8;
  
  // Validation
  static const int minPasswordLength = 6;
  static const int maxProductNameLength = 100;
  
  // Pagination
  static const int defaultPageSize = 20;
  
  // Currency
  static const String currencySymbol = '\$';
  static const String currencyCode = 'USD';
  
  // Default Values
  static const String defaultStoreId = 'STORE001';
  static const String defaultPassword = 'password';
  
  // Sample Coupons
  static const List<Map<String, dynamic>> sampleCoupons = [
    {
      'code': 'GOLD20',
      'discount': 20,
      'description': 'Premium member discount',
      'expiresAt': '2024-12-31',
    },
    {
      'code': 'VIP15',
      'discount': 15,
      'description': 'VIP customer exclusive',
      'expiresAt': '2025-01-15',
    },
  ];
}