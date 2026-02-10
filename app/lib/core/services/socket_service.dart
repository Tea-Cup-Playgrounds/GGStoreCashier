import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';

class SocketService {
  static IO.Socket? _socket;
  static bool _isConnected = false;
  static int? _currentBranchId;

  // Callbacks for real-time events
  static final Map<String, List<Function(dynamic)>> _eventListeners = {};

  static bool get isConnected => _isConnected;

  // Initialize socket connection
  static void connect(String token, int branchId) {
    if (_socket != null && _isConnected) {
      debugPrint('Socket already connected');
      return;
    }

    final baseUrl = ApiConfig.baseUrl.replaceAll('/api', '');
    
    debugPrint('Connecting to Socket.IO at: $baseUrl');
    
    _socket = IO.io(
      baseUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(5000)
          .setReconnectionAttempts(5)
          .setExtraHeaders({'Authorization': 'Bearer $token'})
          .build(),
    );

    _socket!.onConnect((_) {
      debugPrint('Socket.IO connected');
      _isConnected = true;
      _currentBranchId = branchId;
      
      // Join branch room
      _socket!.emit('join-branch', branchId);
      
      // Also join branch-0 for superadmin to receive all events
      _socket!.emit('join-branch', 0);
    });

    _socket!.onDisconnect((_) {
      debugPrint('Socket.IO disconnected');
      _isConnected = false;
    });

    _socket!.onConnectError((error) {
      debugPrint('Socket.IO connection error: $error');
      _isConnected = false;
    });

    _socket!.onError((error) {
      debugPrint('Socket.IO error: $error');
    });

    // Setup event listeners
    _setupEventListeners();
  }

  // Setup event listeners for real-time updates
  static void _setupEventListeners() {
    // Product events
    _socket!.on('product-created', (data) {
      debugPrint('Product created: $data');
      _notifyListeners('product-created', data);
    });

    _socket!.on('product-updated', (data) {
      debugPrint('Product updated: $data');
      _notifyListeners('product-updated', data);
    });

    _socket!.on('product-deleted', (data) {
      debugPrint('Product deleted: $data');
      _notifyListeners('product-deleted', data);
    });

    // Transaction events
    _socket!.on('transaction-created', (data) {
      debugPrint('Transaction created: $data');
      _notifyListeners('transaction-created', data);
    });

    // Payment events
    _socket!.on('payment-completed', (data) {
      debugPrint('Payment completed: $data');
      _notifyListeners('payment-completed', data);
    });
  }

  // Register event listener
  static void on(String event, Function(dynamic) callback) {
    if (!_eventListeners.containsKey(event)) {
      _eventListeners[event] = [];
    }
    _eventListeners[event]!.add(callback);
  }

  // Unregister event listener
  static void off(String event, Function(dynamic) callback) {
    if (_eventListeners.containsKey(event)) {
      _eventListeners[event]!.remove(callback);
    }
  }

  // Notify all listeners for an event
  static void _notifyListeners(String event, dynamic data) {
    if (_eventListeners.containsKey(event)) {
      for (var callback in _eventListeners[event]!) {
        callback(data);
      }
    }
  }

  // Change branch room
  static void changeBranch(int newBranchId) {
    if (_socket == null || !_isConnected) {
      debugPrint('Socket not connected, cannot change branch');
      return;
    }

    if (_currentBranchId != null) {
      _socket!.emit('leave-branch', _currentBranchId);
    }

    _currentBranchId = newBranchId;
    _socket!.emit('join-branch', newBranchId);
    
    // Also join branch-0 for superadmin
    _socket!.emit('join-branch', 0);
    
    debugPrint('Changed to branch: $newBranchId');
  }

  // Disconnect socket
  static void disconnect() {
    if (_socket != null) {
      if (_currentBranchId != null) {
        _socket!.emit('leave-branch', _currentBranchId);
      }
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
      _isConnected = false;
      _currentBranchId = null;
      _eventListeners.clear();
      debugPrint('Socket.IO disconnected and disposed');
    }
  }

  // Emit custom event
  static void emit(String event, dynamic data) {
    if (_socket != null && _isConnected) {
      _socket!.emit(event, data);
    } else {
      debugPrint('Cannot emit event: Socket not connected');
    }
  }
}
