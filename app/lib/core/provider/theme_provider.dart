import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

const _themeKey = 'theme_mode'; // 'dark' | 'light' | 'system'

class ThemeNotifier extends StateNotifier<ThemeMode> {
  ThemeNotifier() : super(ThemeMode.light) {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();

    // Migrate old boolean key → new string key
    const oldKey = 'is_dark_mode';
    if (prefs.containsKey(oldKey)) {
      final wasDark = prefs.getBool(oldKey) ?? false;
      await prefs.setString(_themeKey, wasDark ? 'dark' : 'light');
      await prefs.remove(oldKey);
    }

    final saved = prefs.getString(_themeKey);
    state = switch (saved) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      // No saved preference yet → default to light
      _ => ThemeMode.light,
    };
  }

  Future<void> setTheme(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    final value = switch (mode) {
      ThemeMode.dark => 'dark',
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
    };
    await prefs.setString(_themeKey, value);
  }

  // Keep toggleTheme for backward compat — toggles between light and dark
  Future<void> toggleTheme() async {
    final next = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await setTheme(next);
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>(
  (ref) => ThemeNotifier(),
);
