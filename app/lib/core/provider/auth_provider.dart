import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/socket_service.dart';
import '../database/app_database.dart';

class AuthState {
  final bool isAuthenticated;
  final User? user;
  final bool isLoading;
  final String? error;
  final int? remainingAttempts;
  final bool isLockedOut;
  final DateTime? lockedUntil;

  const AuthState({
    this.isAuthenticated = false,
    this.user,
    this.isLoading = false,
    this.error,
    this.remainingAttempts,
    this.isLockedOut = false,
    this.lockedUntil,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    User? user,
    bool? isLoading,
    String? error,
    int? remainingAttempts,
    bool? isLockedOut,
    DateTime? lockedUntil,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      remainingAttempts: remainingAttempts,
      isLockedOut: isLockedOut ?? this.isLockedOut,
      lockedUntil: lockedUntil,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState()) {
    _hydrate();
  }

  /// Restore session from SharedPreferences on cold start.
  /// This is what makes the dashboard show the real user name and keeps
  /// the app from treating every launch as a fresh session.
  Future<void> _hydrate() async {
    try {
      final token = await AuthService.getToken();
      if (token == null) return; // no stored session — stay unauthenticated

      final user = await AuthService.getCurrentUser();
      if (user == null) {
        // Token exists but user data is corrupt/missing — wipe silently.
        await AuthService.logout();
        return;
      }

      // Reconnect Socket.IO so real-time events resume immediately.
      // If the server rejects the JWT, onAuthFailed fires the session-expired
      // modal and redirects to login — no extra handling needed here.
      SocketService.connect(
        token: token,
        branchId: user.branchId ?? 0,
        role: user.role,
        onAuthFailed: (_) => AuthService.handleSessionExpired(),
      );

      state = state.copyWith(
        isAuthenticated: true,
        user: user,
        isLoading: false,
      );
    } catch (_) {
      // Hydration failure is non-fatal; user simply sees the login screen.
    }
  }

  Future<bool> login(String username, String password, {bool rememberMe = false}) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final result = await AuthService.login(username, password, rememberMe: rememberMe);

      if (result.isSuccess) {
        state = state.copyWith(
          isAuthenticated: true,
          user: result.user,
          isLoading: false,
          remainingAttempts: null,
          isLockedOut: false,
          lockedUntil: null,
        );
        return true;
      } else {
        DateTime? lockedUntilDate;
        if (result.lockedUntil != null) {
          lockedUntilDate = DateTime.fromMillisecondsSinceEpoch(result.lockedUntil!);
        }
        state = state.copyWith(
          isAuthenticated: false,
          user: null,
          isLoading: false,
          error: result.error,
          remainingAttempts: result.remainingAttempts,
          isLockedOut: result.isLockedOut,
          lockedUntil: lockedUntilDate,
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        isAuthenticated: false,
        user: null,
        isLoading: false,
        error: e.toString(),
      );
      return false;
    }
  }

  Future<void> logout() async {
    state = state.copyWith(isLoading: true);
    try {
      await AuthService.logout();
    } catch (_) {
      // Continue with local logout even if server call fails.
    }
    // Disconnect socket and wipe the SQLite store so no stale
    // data from the previous session bleeds into the next login.
    SocketService.disconnect();
    await AppDatabase.clearAll();
    state = const AuthState();
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  /// Update user data in state after a profile self-edit (name/username).
  void refreshUser(Map<String, dynamic> userMap) {
    if (state.user == null) return;
    final updated = state.user!.copyWith(
      name: userMap['name'] as String? ?? state.user!.name,
      username: userMap['username'] as String? ?? state.user!.username,
    );
    state = state.copyWith(user: updated);
  }

  bool isLockoutExpired() {
    if (!state.isLockedOut || state.lockedUntil == null) return true;
    return DateTime.now().isAfter(state.lockedUntil!);
  }

  int getRemainingLockoutMinutes() {
    if (!state.isLockedOut || state.lockedUntil == null) return 0;
    final now = DateTime.now();
    if (now.isAfter(state.lockedUntil!)) return 0;
    return state.lockedUntil!.difference(now).inMinutes + 1;
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);
