import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user.dart';
import '../services/auth_service.dart';

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
    _checkAuthStatus();
  }

  // Check authentication status on app start
  Future<void> _checkAuthStatus() async {
    state = state.copyWith(isLoading: true);
    
    try {
      final isAuth = await AuthService.isAuthenticated();
      if (isAuth) {
        final user = await AuthService.getCurrentUser();
        state = state.copyWith(
          isAuthenticated: true,
          user: user,
          isLoading: false,
        );
      } else {
        state = state.copyWith(
          isAuthenticated: false,
          user: null,
          isLoading: false,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isAuthenticated: false,
        user: null,
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  // Login method
  Future<bool> login(String username, String password) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final result = await AuthService.login(username, password);
      
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

  // Logout method
  Future<void> logout() async {
    state = state.copyWith(isLoading: true);
    
    try {
      await AuthService.logout();
      state = const AuthState();
    } catch (e) {
      // Even if logout fails on server, clear local state
      state = const AuthState();
    }
  }

  // Clear error
  void clearError() {
    state = state.copyWith(error: null);
  }

  // Check if lockout has expired
  bool isLockoutExpired() {
    if (!state.isLockedOut || state.lockedUntil == null) return true;
    return DateTime.now().isAfter(state.lockedUntil!);
  }

  // Get remaining lockout time in minutes
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