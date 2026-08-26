import 'dart:convert';
import 'dart:developer' as dev;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gg_store_cashier/core/router/app_router.dart';
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

  // Cached SharedPreferences instance — avoids re-initializing on every call.
  // Populated on first access; all subsequent calls reuse the same instance.
  static SharedPreferences? _prefs;
  static Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'user_data';
  static const String _rememberMeKey = 'remember_me';

  static bool _isDioInitialized = false;

  // Initialize dio with interceptors for logging
  static void _initializeDio() {
    if (_isDioInitialized) return;
    _isDioInitialized = true;

    if (ApiConfig.enableNetworkLogging) {
      _dio.interceptors.add(LogInterceptor(
        requestBody: true,
        responseBody: true,
        requestHeader: true,
        responseHeader: false,
        error: true,
        logPrint: (obj) {
          if (ApiConfig.enableLogging) {
            dev.log('[DIO] $obj');
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
        dev.log('=== LOGIN ATTEMPT ===');
        dev.log('Username: $username');
        dev.log('API URL: ${ApiConfig.apiUrl}');
        dev.log('Login Endpoint: ${ApiConfig.loginEndpoint}');
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
        dev.log('Response status: ${response.statusCode}');
        dev.log('Response data: ${response.data}');
      }

      if (response.statusCode == 200) {
        final data = response.data;
        final user = User.fromJson(data['user']);
        final token = data['token'];

        // Store token and user data
        await _storeAuthData(token, user, rememberMe: rememberMe);

        // Connect to Socket.IO for real-time updates (role-aware room assignment)
        SocketService.connect(
          token: token,
          branchId: user.branchId ?? 0,
          role: user.role,
          onAuthFailed: (errorMessage) {
            dev.log("Auth Failed: $errorMessage");
            handleSessionExpired();
          },
        );

        if (ApiConfig.enableLogging) {
          dev.log('Login successful for user: ${user.username}');
          dev.log('Socket.IO connection initiated for branch: ${user.branchId}');
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
        dev.log('=== LOGIN ERROR ===');
        dev.log('Error: $e');
      }

      if (e is DioException) {
        if (ApiConfig.enableLogging) {
          dev.log('DioException type: ${e.type}');
          dev.log('DioException message: ${e.message}');
          dev.log('Response: ${e.response?.data}');
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
  // Uses local token check only — fast and offline-safe.
  // Background token validation happens via AuthGuard on navigation.
  static Future<bool> isAuthenticated() async {
    try {
      final token = await getToken();
      return token != null;
    } catch (e) {
      return false;
    }
  }

  // Get current user
  static Future<User?> getCurrentUser() async {
    try {
      final prefs = await _getPrefs();
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
      final prefs = await _getPrefs();
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
      dev.log('Server logout failed or offline: $e');
    } finally {
      SocketService.disconnect();
      await _clearAuthData();
    }
  }

  /// Save updated user data to SharedPreferences (used after profile updates).
  static Future<void> saveUser(Map<String, dynamic> userMap) async {
    final prefs = await _getPrefs();
    // Merge with existing stored user to preserve fields not returned by the update endpoint
    final existing = prefs.getString(_userKey);
    Map<String, dynamic> merged = existing != null ? Map<String, dynamic>.from(json.decode(existing)) : {};
    merged.addAll(userMap);
    await prefs.setString(_userKey, json.encode(merged));
  }

  static Future<void> _storeAuthData(String token, User user, {bool rememberMe = false}) async {
    final prefs = await _getPrefs();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userKey, json.encode(user.toJson()));
    // rememberMe kept in storage for future use but no longer controls
    // whether the session survives a cold start — it always does now.
    await prefs.setBool(_rememberMeKey, rememberMe);
  }

  static Future<void> _clearAuthData() async {
    final prefs = await _getPrefs();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    await prefs.remove(_rememberMeKey);
    // Invalidate the cache so the next read reflects the cleared state.
    _prefs = null;
  }

  /// Previously wiped the session when rememberMe=false on cold start.
  /// Now a no-op — session lifetime is controlled by JWT expiry on the server
  /// and explicit logout only. The socket's onAuthFailed callback handles the
  /// "token rejected by server" path and shows the session-expired modal.
  static Future<void> clearSessionIfNotRemembered() async {
    // Intentionally empty — kept for call-site compatibility.
  }

  static bool consumeSessionClearedFlag() => false;

  /// Shows the "Sesimu sudah habis" modal and clears local auth data.
  /// Called when the server rejects the JWT (socket auth failure or 401).
  static Future<void> handleSessionExpired() async {
    await logout(); // wipe local storage + disconnect socket

    final ctx = AppRouter.rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;

    // Pop any open dialogs first so we don't stack modals.
    // Then show the session-expired modal on top of whatever is visible.
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.lock_clock_outlined, size: 40, color: Color(0xFFF59E0B)),
        title: const Text(
          'Sesimu sudah habis',
          textAlign: TextAlign.center,
        ),
        content: const Text(
          'Silahkan login kembali untuk melanjutkan.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              // Navigate to login — GoRouter redirect will handle auth state.
              AppRouter.router.go('/');
            },
            child: const Text('Login Kembali'),
          ),
        ],
      ),
    );
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
