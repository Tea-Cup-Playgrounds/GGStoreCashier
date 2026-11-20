import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:gg_store_cashier/core/provider/theme_provider.dart';
import 'package:gg_store_cashier/shared/utils/snackbar_service.dart';
import 'package:gg_store_cashier/core/services/cache_manager.dart';
import 'package:gg_store_cashier/core/services/offline_queue.dart';
import 'package:gg_store_cashier/core/services/pending_operations_queue.dart';
import 'package:gg_store_cashier/core/services/orientation_manager.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/constants/app_constants.dart';
import 'core/services/auth_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

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

  // Neutral transparent system UI — AnnotatedRegion in the widget tree
  // handles light/dark icons reactively based on the active theme
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
    ),
  );

  // isOptional: a missing or empty .env still marks dotenv as loaded (with no values), so
  // ApiConfig falls back to its defaults. Swallowing the error instead left dotenv
  // uninitialised, and every later dotenv.env read threw NotInitializedError (login broke on
  // builds made without app/.env). The catch covers a malformed file the same way.
  try {
    await dotenv.load(fileName: '.env', isOptional: true);
  } catch (_) {
    dotenv.loadFromString(envString: '', isOptional: true);
  }

  // In release a widget that throws while building shows a blank grey box; show a readable
  // message instead. Debug builds keep Flutter's red error screen with the full detail.
  if (kReleaseMode) {
    ErrorWidget.builder = (details) => const Material(
          color: Colors.transparent,
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Bagian ini gagal ditampilkan. Coba buka ulang halaman.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
  }

  // Clear non-persistent session if user didn't check "remember me"
  await AuthService.clearSessionIfNotRemembered();

  runApp(
    const ProviderScope(
      child: GGStoreCashierApp(),
    ),
  );
}

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
      ),
    );
  }
}
