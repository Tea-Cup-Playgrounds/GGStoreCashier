// ignore: library_prefixes
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/widgets.dart';
import 'dart:developer' as dev;
import '../config/api_config.dart';

/// Live updates from the API (Socket.IO, see API/src/server.js).
///
/// Events are hints that something changed; screens reload what they show through the normal API.
/// Delivery is not guaranteed (phones sleep, networks drop), so whenever events may have been
/// missed — the socket reconnects, or the app comes back from the background — listeners get a
/// [resyncEvent] and reload everything on screen.
///
/// Lifecycle:
///   - [ensureConnected] is called after login and on every authenticated navigation (AuthGuard),
///     so a session restored at app start ("Remember me") connects too. It is cheap and idempotent.
///   - The socket reconnects forever with backoff; it never gives up while the user is signed in.
///   - [disconnect] on logout closes the socket but keeps the listeners: the screens' providers
///     register them once and live for the whole app run.
class SocketService {
  /// Synthetic event: reload everything, live events may have been missed.
  static const resyncEvent = 'resync';

  /// Events the API emits to location rooms.
  static const _serverEvents = ['sale-created', 'stock-changed'];

  /// Back from the background after at least this long: treat as a gap and resync.
  static const _resumeResyncAfter = Duration(seconds: 10);

  static IO.Socket? _socket;
  static String? _token;
  static int? _branchId;
  static bool _connectedOnce = false;
  static AppLifecycleListener? _lifecycle;
  static DateTime? _pausedAt;

  /// Whether the live connection is up; for a "Live / Offline" indicator.
  static final ValueNotifier<bool> connected = ValueNotifier(false);

  static final Map<String, List<void Function(dynamic)>> _eventListeners = {};

  static bool get isConnected => connected.value;

  /// Connects with [token] and joins [branchId]'s room (plus the all-locations room, which the
  /// server grants only to users whose access covers every location). Does nothing when already set
  /// up for this token and branch; replaces the socket when the token or branch changed.
  static void ensureConnected({required String token, required int branchId}) {
    _watchLifecycle();
    if (_socket != null && _token == token) {
      if (_branchId != branchId) _switchBranch(branchId);
      if (!(_socket!.connected)) _socket!.connect();
      return;
    }
    _dispose();
    _token = token;
    _branchId = branchId;

    final baseUrl = ApiConfig.apiUrl.replaceAll('/api', '');
    dev.log('Connecting to Socket.IO at: $baseUrl');

    final socket = IO.io(
      baseUrl,
      IO.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .enableAutoConnect()
          // A fresh manager per login: IO.io caches one per URL, which would keep the old token.
          .enableForceNew()
          .enableReconnection()
          // No attempt limit: keep trying while signed in (1 s, growing to 15 s between tries).
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(15000)
          .setRandomizationFactor(0.5)
          // The server refuses connections without a valid token (handshake auth or header).
          .setAuth({'token': token})
          .setExtraHeaders({'Authorization': 'Bearer $token', 'ngrok-skip-browser-warning': 'true'})
          .build(),
    );
    _socket = socket;

    socket.onConnect((_) {
      dev.log('Socket.IO connected');
      connected.value = true;
      _joinRooms();
      // Every connect after the first is a reconnect: events in between were missed.
      if (_connectedOnce) _notifyListeners(resyncEvent, null);
      _connectedOnce = true;
    });
    socket.onDisconnect((reason) {
      dev.log('Socket.IO disconnected: $reason');
      connected.value = false;
      // Socket.IO does not reconnect by itself when the server closed the connection on purpose;
      // while signed in we always want it back.
      if (reason == 'io server disconnect') {
        Future<void>.delayed(const Duration(seconds: 2), () {
          if (identical(_socket, socket) && !socket.connected) socket.connect();
        });
      }
    });
    socket.onConnectError((error) {
      dev.log('Socket.IO connection error: $error');
      connected.value = false;
    });
    socket.onError((error) => dev.log('Socket.IO error: $error'));

    for (final event in _serverEvents) {
      socket.on(event, (data) {
        dev.log('$event: $data');
        _notifyListeners(event, data);
      });
    }
  }

  /// Backwards-compatible entry point.
  static void connect(String token, int branchId) => ensureConnected(token: token, branchId: branchId);

  static void _joinRooms() {
    final socket = _socket;
    if (socket == null) return;
    socket.emit('join-branch', _branchId ?? 0);
    socket.emit('join-branch', 0);
  }

  static void _switchBranch(int branchId) {
    final socket = _socket;
    if (socket != null && socket.connected && _branchId != null) socket.emit('leave-branch', _branchId);
    _branchId = branchId;
    if (socket != null && socket.connected) _joinRooms();
  }

  /// Move to another location's room (the all-locations room is kept).
  static void changeBranch(int newBranchId) => _switchBranch(newBranchId);

  /// App lifecycle: reconnect and resync when the app comes back after a while in the background
  /// (mobile OSes usually cut the socket while the app is suspended).
  static void _watchLifecycle() {
    _lifecycle ??= AppLifecycleListener(
      onPause: () => _pausedAt = DateTime.now(),
      onHide: () => _pausedAt ??= DateTime.now(),
      onResume: () {
        final pausedAt = _pausedAt;
        _pausedAt = null;
        final socket = _socket;
        if (socket == null) return;
        if (!socket.connected) {
          socket.connect(); // onConnect will resync
        } else if (pausedAt != null && DateTime.now().difference(pausedAt) >= _resumeResyncAfter) {
          _notifyListeners(resyncEvent, null);
        }
      },
    );
  }

  /// Register an event listener. Listeners survive [disconnect] and reconnects.
  static void on(String event, void Function(dynamic) callback) {
    _eventListeners.putIfAbsent(event, () => []).add(callback);
  }

  static void off(String event, void Function(dynamic) callback) {
    _eventListeners[event]?.remove(callback);
  }

  static void _notifyListeners(String event, dynamic data) {
    for (final callback in List.of(_eventListeners[event] ?? const <void Function(dynamic)>[])) {
      try {
        callback(data);
      } catch (e) {
        dev.log('Listener for $event failed: $e');
      }
    }
  }

  static void _dispose() {
    final socket = _socket;
    if (socket != null) {
      socket.disconnect();
      socket.dispose();
      dev.log('Socket.IO disposed');
    }
    _socket = null;
    _token = null;
    _branchId = null;
    _connectedOnce = false;
    connected.value = false;
  }

  /// Logout: close the connection. Listeners are kept (see class docs).
  static void disconnect() => _dispose();

  static void emit(String event, dynamic data) {
    final socket = _socket;
    if (socket != null && socket.connected) {
      socket.emit(event, data);
    } else {
      dev.log('Cannot emit $event: socket not connected');
    }
  }
}
