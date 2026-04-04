import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gg_store_cashier/core/services/connectivity_monitor.dart';

class ConnectivityBanner extends ConsumerStatefulWidget {
  const ConnectivityBanner({super.key});

  @override
  ConsumerState<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends ConsumerState<ConnectivityBanner> {
  bool _showOnlineBanner = false;
  Timer? _onlineTimer;

  /// The last status we *acted on* — used to detect genuine transitions.
  /// Null means we haven't seen any status yet (initial state).
  ConnectivityStatus? _lastActedStatus;

  @override
  void initState() {
    super.initState();
    // Listen to the stream directly so we only react to real status changes,
    // not to widget rebuilds.
    ConnectivityMonitor.instance.statusStream.listen(_onStatusChange);
  }

  void _onStatusChange(ConnectivityStatus status) {
    if (status == ConnectivityStatus.online &&
        _lastActedStatus == ConnectivityStatus.offline) {
      if (!mounted) return;
      setState(() => _showOnlineBanner = true);
      _onlineTimer?.cancel();
      _onlineTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _showOnlineBanner = false);
      });
    } else if (status == ConnectivityStatus.offline && _showOnlineBanner) {
      _onlineTimer?.cancel();
      if (mounted) setState(() => _showOnlineBanner = false);
    }

    _lastActedStatus = status;
  }

  @override
  void dispose() {
    _onlineTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch the provider only to keep the widget alive and get the current
    // offline/online state for the amber banner. We do NOT trigger the
    // "Kembali Online" logic here — that's handled in _onStatusChange.
    final connectivityAsync = ref.watch(connectivityProvider);
    final isOffline = connectivityAsync.valueOrNull == ConnectivityStatus.offline;

    Widget? bannerContent;

    if (isOffline) {
      bannerContent = Container(
        key: const ValueKey('offline'),
        color: Colors.amber,
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        child: const Row(
          children: [
            Icon(Icons.wifi_off, size: 16, color: Colors.black87),
            SizedBox(width: 8),
            Text(
              'Kamu Offline',
              style: TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ],
        ),
      );
    } else if (_showOnlineBanner) {
      bannerContent = Container(
        key: const ValueKey('online'),
        color: Colors.green,
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        child: const Row(
          children: [
            Icon(Icons.wifi, size: 16, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'Kembali Online',
              style: TextStyle(fontSize: 12, color: Colors.white),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: bannerContent != null ? 32 : 0,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: bannerContent ?? const SizedBox.shrink(),
      ),
    );
  }
}
