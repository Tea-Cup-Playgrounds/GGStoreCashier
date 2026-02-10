import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user.dart';
import 'auth_service.dart';
import '../provider/auth_provider.dart';

/// Session manager for handling user session validation and timeout
class SessionManager {
  static Timer? _sessionTimer;
  static DateTime? _lastActivity;
  static const Duration _sessionTimeout = Duration(hours: 8);
  static const Duration _checkInterval = Duration(minutes: 5);

  /// Initialize session monitoring
  static void initialize(WidgetRef ref) {
    _lastActivity = DateTime.now();
    _startSessionMonitoring(ref);
  }

  /// Update last activity timestamp
  static void updateActivity() {
    _lastActivity = DateTime.now();
  }

  /// Start monitoring session
  static void _startSessionMonitoring(WidgetRef ref) {
    _sessionTimer?.cancel();
    
    _sessionTimer = Timer.periodic(_checkInterval, (timer) async {
      await _checkSession(ref);
    });
  }

  /// Check if session is still valid
  static Future<void> _checkSession(WidgetRef ref) async {
    try {
      // Check if user is authenticated
      final isAuth = await AuthService.isAuthenticated();
      
      if (!isAuth) {
        await _handleSessionExpired(ref);
        return;
      }

      // Check session timeout
      if (_lastActivity != null) {
        final inactiveDuration = DateTime.now().difference(_lastActivity!);
        
        if (inactiveDuration > _sessionTimeout) {
          await _handleSessionTimeout(ref);
          return;
        }
      }

      // Validate user session with backend
      final user = await AuthService.getCurrentUser();
      if (user == null) {
        await _handleSessionExpired(ref);
      }
    } catch (e) {
      print('Session check error: $e');
      await _handleSessionExpired(ref);
    }
  }

  /// Handle session timeout
  static Future<void> _handleSessionTimeout(WidgetRef ref) async {
    print('Session timeout - logging out');
    await _handleSessionExpired(ref);
  }

  /// Handle expired session
  static Future<void> _handleSessionExpired(WidgetRef ref) async {
    _sessionTimer?.cancel();
    _sessionTimer = null;
    _lastActivity = null;
    
    // Logout user
    await ref.read(authProvider.notifier).logout();
  }

  /// Stop session monitoring
  static void dispose() {
    _sessionTimer?.cancel();
    _sessionTimer = null;
    _lastActivity = null;
  }

  /// Get remaining session time
  static Duration? getRemainingSessionTime() {
    if (_lastActivity == null) return null;
    
    final elapsed = DateTime.now().difference(_lastActivity!);
    final remaining = _sessionTimeout - elapsed;
    
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Check if session is about to expire (within 15 minutes)
  static bool isSessionExpiringSoon() {
    final remaining = getRemainingSessionTime();
    if (remaining == null) return false;
    
    return remaining.inMinutes <= 15 && remaining.inMinutes > 0;
  }

  /// Extend session
  static void extendSession() {
    _lastActivity = DateTime.now();
  }
}

/// Provider for session state
final sessionStateProvider = StateNotifierProvider<SessionStateNotifier, SessionState>((ref) {
  return SessionStateNotifier(ref);
});

class SessionState {
  final bool isActive;
  final Duration? remainingTime;
  final bool isExpiringSoon;

  const SessionState({
    this.isActive = false,
    this.remainingTime,
    this.isExpiringSoon = false,
  });

  SessionState copyWith({
    bool? isActive,
    Duration? remainingTime,
    bool? isExpiringSoon,
  }) {
    return SessionState(
      isActive: isActive ?? this.isActive,
      remainingTime: remainingTime ?? this.remainingTime,
      isExpiringSoon: isExpiringSoon ?? this.isExpiringSoon,
    );
  }
}

class SessionStateNotifier extends StateNotifier<SessionState> {
  final Ref ref;
  Timer? _updateTimer;

  SessionStateNotifier(this.ref) : super(const SessionState()) {
    _startUpdating();
  }

  void _startUpdating() {
    _updateTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _updateState();
    });
  }

  void _updateState() {
    final remaining = SessionManager.getRemainingSessionTime();
    final isExpiring = SessionManager.isSessionExpiringSoon();
    
    state = state.copyWith(
      isActive: remaining != null && remaining > Duration.zero,
      remainingTime: remaining,
      isExpiringSoon: isExpiring,
    );
  }

  void extendSession() {
    SessionManager.extendSession();
    _updateState();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }
}
