import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/api_config.dart';

export '../config/api_config.dart' show ApiConfig;

enum ConnectivityStatus { online, offline }

// ── Mobile probe — runs in a separate isolate so it never blocks the UI ───────

Future<bool> _isolateProbe(String endpoint) {
  return Isolate.run(() async {
    try {
      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) => true;
      client.connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(Uri.parse(endpoint));
      request.headers.set('ngrok-skip-browser-warning', 'true');
      final response = await request.close();
      await response.drain<void>();
      client.close();
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  });
}

// ── Web probe — dart:io / dart:isolate are unavailable on Flutter Web ─────────
// Uses Dio which compiles to XMLHttpRequest under the hood.

Future<bool> _webProbe(String endpoint) async {
  try {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
      headers: ApiConfig.defaultHeaders,
      validateStatus: (status) => status != null && status >= 200 && status < 300,
    ));
    final response = await dio.get<void>(endpoint);
    return (response.statusCode ?? 0) >= 200 && (response.statusCode ?? 0) < 300;
  } catch (_) {
    return false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class ConnectivityMonitor {
  ConnectivityMonitor._internal();

  static final ConnectivityMonitor instance = ConnectivityMonitor._internal();

  static const Duration _probeInterval = Duration(seconds: 30);
  // Debounce: collapse rapid connectivity events (e.g. keyboard open/close)
  static const Duration _debounce = Duration(seconds: 2);

  final _controller = StreamController<ConnectivityStatus>.broadcast();
  ConnectivityStatus _currentStatus = ConnectivityStatus.offline;
  ConnectivityStatus? _lastEmitted;
  bool _initialProbeComplete = false;
  bool _started = false;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _periodicTimer;
  Timer? _debounceTimer;

  Stream<ConnectivityStatus> get statusStream => _controller.stream;
  ConnectivityStatus get currentStatus => _currentStatus;
  bool get initialProbeComplete => _initialProbeComplete;

  /// Start monitoring. Call this AFTER login, not on app startup.
  void start() {
    if (_started) return;
    _started = true;

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((_) => _debouncedProbe());

    _periodicTimer = Timer.periodic(_probeInterval, (_) => _probeAndEmit());

    // Delay first probe so the first frame renders before any network work.
    Timer(const Duration(milliseconds: 800), () => _probeAndEmit(isInitial: true));
  }

  void _debouncedProbe() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, _probeAndEmit);
  }

  Future<void> _probeAndEmit({bool isInitial = false}) async {
    final status = await probe();
    _currentStatus = status;

    if (status != _lastEmitted) {
      _lastEmitted = status;
      if (!_controller.isClosed) _controller.add(status);
    }

    if (isInitial) _initialProbeComplete = true;
  }

  /// Probes the API health endpoint.
  /// - On web: uses Dio (XMLHttpRequest) — dart:io/dart:isolate unavailable
  /// - On mobile: uses dart:io HttpClient in a separate isolate
  Future<ConnectivityStatus> probe() async {
    try {
      final ok = kIsWeb ? await _webProbe(ApiConfig.testEndpoint) : await _isolateProbe(ApiConfig.testEndpoint);
      return ok ? ConnectivityStatus.online : ConnectivityStatus.offline;
    } catch (_) {
      return ConnectivityStatus.offline;
    }
  }

  void dispose() {
    _debounceTimer?.cancel();
    _connectivitySubscription?.cancel();
    _periodicTimer?.cancel();
    _controller.close();
  }
}

final connectivityProvider = StreamProvider<ConnectivityStatus>((ref) async* {
  yield ConnectivityMonitor.instance.currentStatus;
  yield* ConnectivityMonitor.instance.statusStream;
});
