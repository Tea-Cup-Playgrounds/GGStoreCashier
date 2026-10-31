// ignore: library_prefixes
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:developer' as dev;
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
      dev.log('Socket already connected');
      return;
    }

    final baseUrl = ApiConfig.apiUrl.replaceAll('/api', '');

    dev.log('Connecting to Socket.IO at: $baseUrl');

    _socket = IO.io(
      baseUrl,
      IO.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionDelay(2000)
          .setReconnectionDelayMax(10000)
          .setReconnectionAttempts(3)
          // The server refuses connections without a valid token (handshake auth or header).
          .setAuth({'token': token})
          .setExtraHeaders({'Authorization': 'Bearer $token', 'ngrok-skip-browser-warning': 'true'})
          .build(),
    );

    _socket!.onConnect((_) {
      dev.log('Socket.IO connected');
      _isConnected = true;
      _currentBranchId = branchId;

      // Join the location room; the all-locations room (0) is only granted to users whose access
      // covers every location, and the server ignores the request for anyone else.
      _socket!.emit('join-branch', branchId);
      _socket!.emit('join-branch', 0);
    });

    _socket!.onDisconnect((_) {
      dev.log('Socket.IO disconnected');
      _isConnected = false;
    });

    _socket!.onConnectError((error) {
      dev.log('Socket.IO connection error: $error');
      _isConnected = false;
    });

    _socket!.onError((error) {
      dev.log('Socket.IO error: $error');
    });

    // Setup event listeners
    _setupEventListeners();
  }

  // Events the API emits to location rooms (see API/src/server.js).
  static void _setupEventListeners() {
    for (final event in const ['sale-created', 'stock-changed']) {
      _socket!.on(event, (data) {
        dev.log('$event: $data');
        _notifyListeners(event, data);
      });
    }
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
      dev.log('Socket not connected, cannot change branch');
      return;
    }

    if (_currentBranchId != null) {
      _socket!.emit('leave-branch', _currentBranchId);
    }

    _currentBranchId = newBranchId;
    _socket!.emit('join-branch', newBranchId);

    // All-locations room; ignored by the server unless the user's access covers every location.
    _socket!.emit('join-branch', 0);

    dev.log('Changed to branch: $newBranchId');
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
      dev.log('Socket.IO disconnected and disposed');
    }
  }

  // Emit custom event
  static void emit(String event, dynamic data) {
    if (_socket != null && _isConnected) {
      _socket!.emit(event, data);
    } else {
      dev.log('Cannot emit event: Socket not connected');
    }
  }
}
