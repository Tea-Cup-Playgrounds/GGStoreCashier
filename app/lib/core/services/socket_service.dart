// ignore: library_prefixes
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:async';
import 'dart:developer' as dev;
import '../config/api_config.dart';
import './cache_manager.dart';

class SocketService {
  static IO.Socket? _socket;
  static bool _isConnected = false;
  static String? _currentRole;
  static int? _currentBranchId;

  static final StreamController<bool> _connectionController = StreamController<bool>.broadcast();

  static Stream<bool> get connectionStream => _connectionController.stream;
  static bool get isConnected => _isConnected;

  static final Map<String, List<Function(dynamic)>> _eventListeners = {};

  /// Active subscriptions — tracks which entities this client is subscribed to.
  /// Format: {'products': true, 'vouchers': true, 'users': true, 'live_transactions': true}
  static final Set<String> _activeSubscriptions = {};

  static void connect({
    required String token,
    required int branchId,
    required String role,
    void Function(String message)? onAuthFailed,
  }) {
    // If already connected with the same socket, avoid re-connecting
    if (_socket != null && _isConnected) {
      dev.log('Socket already connected');
      return;
    }

    _currentRole = role;
    _currentBranchId = branchId;

    final baseUrl = ApiConfig.apiUrl.replaceAll('/api', '');
    dev.log('Connecting to Socket.IO at: $baseUrl (role=$role, branch=$branchId)');

    _socket = IO.io(
      baseUrl,
      IO.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionDelay(2000)
          .setReconnectionDelayMax(10000)
          .setReconnectionAttempts(5)
          .setAuth({'token': 'Bearer $token'})
          .setExtraHeaders({
            'Authorization': 'Bearer $token',
            'ngrok-skip-browser-warning': 'true',
          })
          .build(),
    );

    _socket!.onConnect((_) {
      dev.log('Socket.IO connected successfully (role=$_currentRole, socketId=${_socket?.id})');
      _isConnected = true;
      _connectionController.add(true);
    });

    _socket!.onDisconnect((reason) {
      dev.log('Socket.IO disconnected: $reason');
      _isConnected = false;
      _connectionController.add(false);
    });

    _socket!.onConnectError((error) {
      final errorMessage = error.toString();
      dev.log('Socket.IO connection error: $errorMessage');
      _isConnected = false;
      _connectionController.add(false);

      if (errorMessage.contains('AUTHENTICATION_FAILED') || errorMessage.contains('Authentication error')) {
        dev.log('Socket authentication rejected by backend. Forcing logout...');

        disconnect();

        if (onAuthFailed != null) {
          onAuthFailed(errorMessage);
        }
      }
    });

    _socket!.onError((error) {
      dev.log('Socket.IO error: $error');
    });

    _socket!.onReconnect((attempt) {
      dev.log('Socket.IO reconnected on attempt #$attempt');
      _isConnected = true;
      _connectionController.add(true);
      // Clear cache to ensure fresh data after reconnection
      CacheManager.clear();
      dev.log('Cache cleared after socket reconnection');
      // Re-establish all active subscriptions
      _resubscribeAll();
    });

    _setupEventListeners();
  }

  static void _setupEventListeners() {
    _socket!.off('product-created');
    _socket!.off('product-updated');
    _socket!.off('product-deleted');
    _socket!.off('category-created');
    _socket!.off('category-updated');
    _socket!.off('category-deleted');
    _socket!.off('transaction-created');
    _socket!.off('payment-completed');
    _socket!.off('dashboard:live-update');
    _socket!.off('voucher-created');
    _socket!.off('voucher-updated');
    _socket!.off('voucher-deleted');
    _socket!.off('user-created');
    _socket!.off('user-updated');
    _socket!.off('user-deleted');

    _socket!.on('product-created', (data) {
      dev.log('Event received: product-created');
      _notifyListeners('product-created', data);
    });

    _socket!.on('product-updated', (data) {
      dev.log('Event received: product-updated');
      _notifyListeners('product-updated', data);
    });

    _socket!.on('product-deleted', (data) {
      dev.log('Event received: product-deleted');
      _notifyListeners('product-deleted', data);
    });

    _socket!.on('category-created', (data) {
      dev.log('Event received: category-created');
      _notifyListeners('category-created', data);
    });

    _socket!.on('category-updated', (data) {
      dev.log('Event received: category-updated');
      _notifyListeners('category-updated', data);
    });

    _socket!.on('category-deleted', (data) {
      dev.log('Event received: category-deleted');
      _notifyListeners('category-deleted', data);
    });

    _socket!.on('transaction-created', (data) {
      dev.log('Event received: transaction-created');
      _notifyListeners('transaction-created', data);
    });

    _socket!.on('payment-completed', (data) {
      dev.log('Event received: payment-completed');
      _notifyListeners('payment-completed', data);
    });

    _socket!.on('dashboard:live-update', (data) {
      dev.log('Event received: dashboard:live-update');
      _notifyListeners('dashboard:live-update', data);
    });

    _socket!.on('voucher-created', (data) {
      dev.log('Event received: voucher-created');
      _notifyListeners('voucher-created', data);
    });

    _socket!.on('voucher-updated', (data) {
      dev.log('Event received: voucher-updated');
      _notifyListeners('voucher-updated', data);
    });

    _socket!.on('voucher-deleted', (data) {
      dev.log('Event received: voucher-deleted');
      _notifyListeners('voucher-deleted', data);
    });

    _socket!.on('user-created', (data) {
      dev.log('Event received: user-created');
      _notifyListeners('user-created', data);
    });

    _socket!.on('user-updated', (data) {
      dev.log('Event received: user-updated');
      _notifyListeners('user-updated', data);
    });

    _socket!.on('user-deleted', (data) {
      dev.log('Event received: user-deleted');
      _notifyListeners('user-deleted', data);
    });
  }

  static void on(String event, Function(dynamic) callback) {
    _eventListeners.putIfAbsent(event, () => []).add(callback);
  }

  static void off(String event, Function(dynamic) callback) {
    _eventListeners[event]?.remove(callback);
  }

  static void _notifyListeners(String event, dynamic data) {
    final listeners = _eventListeners[event];
    if (listeners != null) {
      for (final cb in List.of(listeners)) {
        cb(data);
      }
    }
  }

  static void joinBranch(int branchId) {
    if (_socket == null || !_isConnected) return;
    _socket!.emit('join-branch', branchId);
    dev.log('Requested join to branch-$branchId');
  }

  static void leaveBranch(int branchId) {
    if (_socket == null || !_isConnected) return;
    _socket!.emit('leave-branch', branchId);
    dev.log('Requested leave from branch-$branchId');
  }

  static void changeBranch(int newBranchId) {
    if (_socket == null || !_isConnected) {
      dev.log('Socket not connected, cannot change branch');
      return;
    }
    if (_currentBranchId != null) {
      leaveBranch(_currentBranchId!);
    }
    _currentBranchId = newBranchId;
    joinBranch(newBranchId);
    dev.log('Changed branch to: $newBranchId');
  }

  static void emit(String event, dynamic data) {
    if (_socket != null && _isConnected) {
      _socket!.emit(event, data);
    } else {
      dev.log('Cannot emit $event: Socket not connected');
    }
  }

  static void disconnect() {
    if (_socket != null) {
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
      _isConnected = false;
      _currentRole = null;
      _currentBranchId = null;
      _eventListeners.clear();
      _activeSubscriptions.clear();
      _connectionController.add(false);
      dev.log('Socket.IO disconnected and disposed', name: 'SOCKET_SERVICE');
    }
  }

  // ── Granular Subscriptions ───────────────────────────────────────────────────

  /// Subscribe to a specific entity type for real-time updates.
  ///
  /// Supported entities:
  /// - 'products': inventory updates
  /// - 'vouchers': voucher CRUD updates
  /// - 'users': user account updates
  /// - 'live_transactions': real-time transaction events
  ///
  /// Subscriptions are automatically maintained across reconnections.
  static void subscribe(String entity) {
    if (_activeSubscriptions.contains(entity)) {
      dev.log('Already subscribed to $entity', name: 'SOCKET_SERVICE');
      return;
    }

    _activeSubscriptions.add(entity);

    if (_socket != null && _isConnected) {
      _socket!.emit('subscribe', entity);
      dev.log('Subscribed to: $entity', name: 'SOCKET_SERVICE');
    }
  }

  /// Unsubscribe from a specific entity type.
  static void unsubscribe(String entity) {
    if (!_activeSubscriptions.contains(entity)) {
      dev.log('Not subscribed to $entity', name: 'SOCKET_SERVICE');
      return;
    }

    _activeSubscriptions.remove(entity);

    if (_socket != null && _isConnected) {
      _socket!.emit('unsubscribe', entity);
      dev.log('Unsubscribed from: $entity', name: 'SOCKET_SERVICE');
    }
  }

  /// Re-establish all active subscriptions after reconnection.
  static void _resubscribeAll() {
    if (_socket == null || !_isConnected || _activeSubscriptions.isEmpty) return;

    dev.log('Re-subscribing to ${_activeSubscriptions.length} entities', name: 'SOCKET_SERVICE');

    for (final entity in _activeSubscriptions) {
      _socket!.emit('subscribe', entity);
      dev.log('Re-subscribed to: $entity', name: 'SOCKET_SERVICE');
    }
  }
}
