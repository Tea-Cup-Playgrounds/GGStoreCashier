import 'package:flutter/material.dart';
import 'package:gg_store_cashier/core/theme/app_theme.dart';

class SnackBarService {
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  static void show(
    String message, {
    Color backgroundColor = AppTheme.gold,
    Duration duration = const Duration(seconds: 2),
  }) {
    messengerKey.currentState?.clearSnackBars();
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        // margin: const EdgeInsets.all(8),
        duration: duration,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  static void success(String message) {
    show(message, backgroundColor: AppTheme.gold );
  }

  static void error(String message) {
    show(message, backgroundColor: Colors.red);
  }
}
