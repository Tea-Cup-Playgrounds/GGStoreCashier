import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/api_config.dart';

enum ConnectivityStatus { online, offline }

class ConnectivityMonitor {
  ConnectivityMonitor._internal() {
    _init();
  }

  static final ConnectivityMonitor instance = ConnectivityMonitor._internal();

  /// Probe interval — 30s is plenty; 10s was hammering the server.
  static const Duration _probeInterval = Duration(seconds: 30);
  static const Duration _probeTimeout = Duration(seconds: 3);

  final _controller = StreamController<ConnectivityStatus>.broadcast();
  ConnectivityStatus _currentStatus = ConnectivityStatus.offline;
  ConnectivityStatus? _lastEmitted;

  /// Whether the initial probe has completed. Listeners should ignore
  /// the very first emission if they only care about *transitions*.
  bool _initialProbeComplete = false;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _periodicTimer;

  Stream<ConnectivityStatus> get statusStream => _controller.stream;
  ConnectivityStatus get currentStatus => _currentStatus;

  /// True once the first probe has finished and a status is known.
  bool get initialProbeComplete => _initialProbeComplete;

  void _init() {
    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen((_) => _probeAndEmit());

    _periodicTimer = Timer.periodic(_probeInterval, (_) => _probeAndEmit());

    _probeAndEmit(isInitial: true);
  }

  Future<void> _probeAndEmit({bool isInitial = false}) async {
    final status = await probe();
    _currentStatus = status;

    if (status != _lastEmitted) {
      _lastEmitted = status;
      _controller.add(status);
    }

    if (isInitial) _initialProbeComplete = true;
  }

  /// Performs an HTTP probe to verify actual internet connectivity.
  /// Returns [ConnectivityStatus.online] on any 2xx response,
  /// [ConnectivityStatus.offline] on any failure.
  Future<ConnectivityStatus> probe() async {
    try {
      final dio = Dio();
      final response = await dio.get(
        ApiConfig.testEndpoint,
        options: Options(
          sendTimeout: _probeTimeout,
          receiveTimeout: _probeTimeout,
          headers: ApiConfig.defaultHeaders,
        ),
      );
      final statusCode = response.statusCode ?? 0;
      if (statusCode >= 200 && statusCode < 300) {
        return ConnectivityStatus.online;
      }
      return ConnectivityStatus.offline;
    } catch (_) {
      return ConnectivityStatus.offline;
    }
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _periodicTimer?.cancel();
    _controller.close();
  }
}

final connectivityProvider = StreamProvider<ConnectivityStatus>((ref) {
  return ConnectivityMonitor.instance.statusStream;
});
