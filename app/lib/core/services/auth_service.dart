import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/user.dart';
import './socket_service.dart';

class AuthService {
  static final _dio = Dio(BaseOptions(
    baseUrl: ApiConfig.apiUrl,
    connectTimeout: ApiConfig.connectTimeout,
    receiveTimeout: ApiConfig.receiveTimeout,
    sendTimeout: ApiConfig.sendTimeout,
    headers: {
      'ngrok-skip-browser-warning': 'true',
    },
  ));

  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'user_data';
  static const String _rememberMeKey = 'remember_me';

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
  static Future<AuthResult> login(String username, String password, {bool rememberMe = false}) async {
    _initializeDio(); // Initialize logging

    try {
      if (ApiConfig.enableLogging) {
        print('=== LOGIN ATTEMPT ===');
        print('Username: $username');
        print('API URL: ${ApiConfig.apiUrl}');
        print('Login Endpoint: ${ApiConfig.loginEndpoint}');
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
        await _storeAuthData(token, user, rememberMe: rememberMe);

        // Connect to Socket.IO for real-time updates
        SocketService.connect(token, user.branchId ?? 0);

        if (ApiConfig.enableLogging) {
          print('Login successful for user: ${user.username}');
          print('Socket.IO connection initiated for branch: ${user.branchId}');
        }

        return AuthResult.success(user);
      } else {
        final errorData = response.data;
        final remaining = errorData?['remainingAttempts'];
        final locked = errorData?['lockedUntil'];
        final isLockedOut = response.statusCode == 429;
        return AuthResult.failure(
          errorData?['error'] ?? 'Login failed',
          remainingAttempts: remaining is int ? remaining : int.tryParse(remaining?.toString() ?? ''),
          isLockedOut: isLockedOut,
          lockedUntil: locked is int ? locked : int.tryParse(locked?.toString() ?? ''),
        );
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
          final remaining = errorData?['remainingAttempts'];
          return AuthResult.failure(
            errorData?['error'] ?? 'Invalid credentials',
            remainingAttempts: remaining is int ? remaining : int.tryParse(remaining?.toString() ?? ''),
          );
        } else if (e.response?.statusCode == 429) {
          final errorData = e.response?.data;
          final locked = errorData?['lockedUntil'];
          return AuthResult.failure(
            errorData?['error'] ?? 'Too many attempts',
            isLockedOut: true,
            lockedUntil: locked is int ? locked : int.tryParse(locked?.toString() ?? ''),
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
      await logout();
      return false;
    }
  }

  // Get current user
  static Future<User?> getCurrentUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString(_userKey);
      if (userJson != null) return User.fromJson(json.decode(userJson));
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
      // Disconnect Socket.IO
      SocketService.disconnect();

      // Clear local storage
      await _clearAuthData();
    }
  }

  // Store authentication data — token always persisted, rememberMe controls
  // whether it survives the next cold start
  static Future<void> _storeAuthData(String token, User user, {bool rememberMe = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userKey, json.encode(user.toJson()));
    await prefs.setBool(_rememberMeKey, rememberMe);
  }

  // Clear authentication data
  static Future<void> _clearAuthData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    await prefs.remove(_rememberMeKey);
  }

  // Call this on app startup — clears session if remember me was off
  static Future<void> clearSessionIfNotRemembered() async {
    final prefs = await SharedPreferences.getInstance();
    final remembered = prefs.getBool(_rememberMeKey) ?? false;
    if (!remembered) {
      await prefs.remove(_tokenKey);
      await prefs.remove(_userKey);
    }
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
          return 'Koneksi timeout. Periksa koneksi internet Anda.';
        case DioExceptionType.badResponse:
          return 'Terjadi kesalahan pada server. Coba lagi nanti.';
        case DioExceptionType.cancel:
          return 'Permintaan dibatalkan.';
        case DioExceptionType.unknown:
          return 'Gagal terhubung ke jaringan. Periksa koneksi Anda.';
        default:
          return 'Terjadi kesalahan yang tidak terduga.';
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
