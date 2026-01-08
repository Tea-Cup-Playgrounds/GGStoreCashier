import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

const _themeKey = 'is_dark_mode';
class ThemeNotifier extends StateNotifier<ThemeMode> {
  ThemeNotifier() : super(ThemeMode.dark) {
    _loadTheme();
  }

// Load Theme
  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool(_themeKey);

    if (isDark != null) {
      state = isDark ? ThemeMode.dark : ThemeMode.light;
    }
  }

  // Toggle mode
  Future<void> toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    state = state == ThemeMode.dark ? ThemeMode.light: ThemeMode.dark;
    await prefs.setBool(_themeKey, state == ThemeMode.dark);
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>(
  (ref) => ThemeNotifier(),
);
