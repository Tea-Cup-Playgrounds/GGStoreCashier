import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:gg_store_cashier/core/provider/theme_provider.dart';
import 'package:gg_store_cashier/shared/utils/snackbar_service.dart';
import 'package:gg_store_cashier/core/services/cache_manager.dart';
import 'package:gg_store_cashier/core/services/offline_queue.dart';
import 'package:gg_store_cashier/core/services/pending_operations_queue.dart';
import 'package:gg_store_cashier/core/services/orientation_manager.dart';
import 'package:gg_store_cashier/core/database/app_database.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/constants/app_constants.dart';
import 'core/services/auth_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Re-applies the status-bar-hidden mode every time the app becomes active.
/// This is the only reliable way to keep Android from permanently showing the
/// status bar after the user peeks or full-swipes it.
void _applySystemUiMode() {
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [SystemUiOverlay.bottom], // nav bar only; status bar hidden
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  Hive.registerAdapter(CacheEntryAdapter());
  Hive.registerAdapter(OfflineTransactionEntryAdapter());
  Hive.registerAdapter(PendingOperationAdapter());
  await Hive.openBox<CacheEntry>('cache_box');
  await Hive.openBox<OfflineTransactionEntry>('offline_queue_box');
  await Hive.openBox<PendingOperation>('pending_ops_box');

  await OrientationManager.init();

  // Initialise SQLite — single source of truth for high-frequency data
  if (!kIsWeb) {
    await AppDatabase.database;
  }

  // Initial hide — status bar off, nav bar on.
  _applySystemUiMode();

  // Transparent nav bar background; AnnotatedRegion in the widget tree
  // handles light/dark icon tints reactively.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
    ),
  );

  await dotenv.load(fileName: ".env").catchError((_) {});

  await AuthService.clearSessionIfNotRemembered();

  runApp(
    const ProviderScope(
      child: GGStoreCashierApp(),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Root app widget
// ─────────────────────────────────────────────────────────────────────────────

class GGStoreCashierApp extends ConsumerWidget {
  const GGStoreCashierApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    final isDark = themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system && MediaQuery.of(context).platformBrightness == Brightness.dark);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: isDark ? AppTheme.background : AppTheme.lightBackground,
        systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
      child: MaterialApp.router(
        scaffoldMessengerKey: SnackBarService.messengerKey,
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeMode,
        routerConfig: AppRouter.router,
        // Wrap every page with the lifecycle + UI-visibility observer so the
        // status bar is re-hidden wherever the user is in the app.
        builder: (context, child) => _SystemUiGuard(child: child!),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SystemUiGuard
//
// Sits at the root of the widget tree and handles two scenarios:
//
//  1. Peek  — user drags down slightly to check time / notifications.
//             Android makes the status bar visible temporarily.
//             We detect the change via [didChangeMetrics] and start a 2-second
//             countdown.  If the user lets go (status bar disappears on its own
//             before the timer fires) the timer is simply cancelled.
//             If the bar stays visible after 2 s we call _applySystemUiMode().
//
//  2. Full swipe / app resume — [didChangeAppLifecycleState] fires resumed.
//             We immediately re-apply the hidden mode; no timer needed.
// ─────────────────────────────────────────────────────────────────────────────

class _SystemUiGuard extends StatefulWidget {
  final Widget child;
  const _SystemUiGuard({required this.child});

  @override
  State<_SystemUiGuard> createState() => _SystemUiGuardState();
}

class _SystemUiGuardState extends State<_SystemUiGuard> with WidgetsBindingObserver {
  // Cached padding so we can compare old vs new on metrics change.
  double _lastTopPadding = 0;

  // Timer for the 2-second "peek" debounce.
  // Cancelled if the user closes the notification shade before it fires.
  static const _rehideDelay = Duration(seconds: 2);
  bool _timerActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Capture baseline padding after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _lastTopPadding = MediaQuery.of(context).padding.top;
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ── Lifecycle: re-hide immediately when app resumes ──────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Cancel any pending timer — we're hiding right now.
      _timerActive = false;
      _applySystemUiMode();
    }
  }

  // ── Metrics: detect when the status bar peeks in ──────────────────────────
  //
  // When the status bar is hidden, MediaQuery.padding.top == 0 (or very small).
  // When the user swipes down to peek, Android insets the view and padding.top
  // jumps to ~24–28dp.  We use that delta as our "status bar appeared" signal.

  @override
  void didChangeMetrics() {
    if (!mounted) return;

    // Schedule after the frame so MediaQuery is up-to-date.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final currentPadding = MediaQuery.of(context).padding.top;

      final statusBarAppeared = currentPadding > 10 && _lastTopPadding <= 10;
      final statusBarDisappeared = currentPadding <= 10 && _lastTopPadding > 10;

      _lastTopPadding = currentPadding;

      if (statusBarAppeared && !_timerActive) {
        // Status bar peeked in — start the 2-second countdown.
        _timerActive = true;
        Future.delayed(_rehideDelay, () {
          if (!_timerActive) return; // cancelled because it disappeared itself
          _timerActive = false;
          _applySystemUiMode();
        });
      }

      if (statusBarDisappeared) {
        // User closed the shade before our timer fired — cancel it.
        _timerActive = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
