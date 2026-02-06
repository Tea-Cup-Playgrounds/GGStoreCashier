import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/user.dart';

class AuthService {
  static final _dio = Dio(BaseOptions(
    baseUrl: ApiConfig.apiUrl,
    connectTimeout: ApiConfig.connectTimeout,
    receiveTimeout: ApiConfig.receiveTimeout,
    sendTimeout: ApiConfig.sendTimeout,
  ));

  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'user_data';

  // Initialize dio with interceptors for logging
  static void _initializeDio() {
    if (ApiConfig.enableNetworkLogging) {
      _dio.interceptors.add(LogInterceptor(
        requestBody: true,
        responseBody: true,
        requestHeader: true,
        responseHeader: false,
        error: true,
        logPrint: (obj) {
          if (ApiConfig.enableLogging) {
            print('[DIO] $obj');
          }
        },
      ));
    }
  }

  // Login method
  static Future<AuthResult> login(String username, String password) async {
    _initializeDio(); // Initialize logging
    
    try {
      if (ApiConfig.enableLogging) {
        print('=== LOGIN ATTEMPT ===');
        print('Username: $username');
        print('API URL: ${ApiConfig.apiUrl}');
        print('Login Endpoint: ${ApiConfig.loginEndpoint}');
        print('Current Environment: ${ApiConfig.currentEnvironment}');
      }
      
      final response = await _dio.post(
        '/api/auth/login',
        data: {
          'username': username,
          'password': password,
        },
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
          validateStatus: (status) {
            // Accept all status codes to handle them manually
            return status != null && status < 500;
          },
        ),
      );

      if (ApiConfig.enableLogging) {
        print('Response status: ${response.statusCode}');
        print('Response data: ${response.data}');
      }

      if (response.statusCode == 200) {
        final data = response.data;
        final user = User.fromJson(data['user']);
        final token = data['token'];

        // Store token and user data
        await _storeAuthData(token, user);

        if (ApiConfig.enableLogging) {
          print('Login successful for user: ${user.username}');
        }

        return AuthResult.success(user);
      } else {
        final errorData = response.data;
        return AuthResult.failure(errorData?['error'] ?? 'Login failed');
      }
    } catch (e) {
      if (ApiConfig.enableLogging) {
        print('=== LOGIN ERROR ===');
        print('Error: $e');
      }
      
      if (e is DioException) {
        if (ApiConfig.enableLogging) {
          print('DioException type: ${e.type}');
          print('DioException message: ${e.message}');
          print('Response: ${e.response?.data}');
        }
        
        if (e.response?.statusCode == 401) {
          final errorData = e.response?.data;
          final remainingAttempts = errorData?['remainingAttempts'];
          return AuthResult.failure(
            errorData?['error'] ?? 'Invalid credentials',
            remainingAttempts: remainingAttempts,
          );
        } else if (e.response?.statusCode == 429) {
          final errorData = e.response?.data;
          return AuthResult.failure(
            errorData?['error'] ?? 'Too many attempts',
            isLockedOut: true,
            lockedUntil: errorData?['lockedUntil'],
          );
        }
      }
      return AuthResult.failure(_getErrorMessage(e));
    }
  }

  // Check if user is authenticated
  static Future<bool> isAuthenticated() async {
    try {
      final token = await getToken();
      if (token == null) return false;

      // Verify token with server
      final response = await _dio.get(
        '/api/auth/me',
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
      );

      return response.statusCode == 200;
    } catch (e) {
      // If token is invalid, clear stored data
      await logout();
      return false;
    }
  }

  // Get current user
  static Future<User?> getCurrentUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString(_userKey);
      if (userJson != null) {
        return User.fromJson(json.decode(userJson));
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Get stored token
  static Future<String?> getToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_tokenKey);
    } catch (e) {
      return null;
    }
  }

  // Logout
  static Future<void> logout() async {
    try {
      final token = await getToken();
      if (token != null) {
        // Call logout endpoint
        await _dio.post(
          '/api/auth/logout',
          options: Options(
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          ),
        );
      }
    } catch (e) {
      // Continue with local logout even if server call fails
    } finally {
      // Clear local storage
      await _clearAuthData();
    }
  }

  // Store authentication data
  static Future<void> _storeAuthData(String token, User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userKey, json.encode(user.toJson()));
  }

  // Clear authentication data
  static Future<void> _clearAuthData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }

  // Get error message from exception
  static String _getErrorMessage(dynamic error) {
    if (error is DioException) {
      if (error.response?.data != null && error.response?.data['error'] != null) {
        return error.response!.data['error'];
      }
      
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Connection timeout. Please check your internet connection.';
        case DioExceptionType.badResponse:
          return 'Server error. Please try again later.';
        case DioExceptionType.cancel:
          return 'Request was cancelled.';
        case DioExceptionType.unknown:
          return 'Network error. Please check your connection.';
        default:
          return 'An unexpected error occurred.';
      }
    }
    return error.toString();
  }
}

class AuthResult {
  final bool isSuccess;
  final String? error;
  final User? user;
  final int? remainingAttempts;
  final bool isLockedOut;
  final int? lockedUntil;

  AuthResult._({
    required this.isSuccess,
    this.error,
    this.user,
    this.remainingAttempts,
    this.isLockedOut = false,
    this.lockedUntil,
  });

  factory AuthResult.success(User user) {
    return AuthResult._(
      isSuccess: true,
      user: user,
    );
  }

  factory AuthResult.failure(
    String error, {
    int? remainingAttempts,
    bool isLockedOut = false,
    int? lockedUntil,
  }) {
    return AuthResult._(
      isSuccess: false,
      error: error,
      remainingAttempts: remainingAttempts,
      isLockedOut: isLockedOut,
      lockedUntil: lockedUntil,
    );
  }
}