import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Private lifecycle observer that re-applies orientation on app resume.
class _OrientationLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      OrientationManager.init();
    }
  }
}

/// Manages device orientation based on the system auto-rotate setting.
///
/// Call [init] once after [WidgetsFlutterBinding.ensureInitialized] in main().
class OrientationManager {
  static const MethodChannel _channel = MethodChannel('gg_kasir/orientation');

  static _OrientationLifecycleObserver? _observer;

  /// Reads the auto-rotate setting and applies the appropriate orientation
  /// constraints. Also registers a lifecycle observer to re-apply on resume.
  static Future<void> init() async {
    // Register the lifecycle observer only once.
    if (_observer == null) {
      _observer = _OrientationLifecycleObserver();
      WidgetsBinding.instance.addObserver(_observer!);
    }

    final autoRotate = await isAutoRotateEnabled();
    await applyOrientation(autoRotateEnabled: autoRotate);
  }

  /// Applies orientation constraints via [SystemChrome.setPreferredOrientations].
  ///
  /// - [autoRotateEnabled] == true  → all four orientations allowed.
  /// - [autoRotateEnabled] == false → portrait-up only.
  static Future<void> applyOrientation({required bool autoRotateEnabled}) async {
    if (autoRotateEnabled) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
  }

  /// Returns whether the system auto-rotate setting is enabled.
  ///
  /// On Android, queries the native side via the [MethodChannel]
  /// `'gg_kasir/orientation'` with method `'isAutoRotateEnabled'`.
  /// Falls back to `true` (all orientations) if the platform channel is
  /// unavailable (e.g., on iOS or when the native handler is not implemented).
  static Future<bool> isAutoRotateEnabled() async {
    try {
      final result = await _channel.invokeMethod<bool>('isAutoRotateEnabled');
      return result ?? true;
    } on PlatformException {
      return true;
    } on MissingPluginException {
      return true;
    }
  }
}
