import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:shared_preferences/shared_preferences.dart';

// 1. SharedPreferences Provider (Initialized in main.dart)
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences not initialized');
});

// 2. Theme Notifier
class ThemeNotifier extends Notifier<ThemeMode> {
  static const String _themeKey = 'theme_mode';
  @override
  ThemeMode build() {
    // Load from SharedPreferences synchronously (since it's initialized in main)
    final prefs = ref.watch(sharedPreferencesProvider);

    final themeString = prefs.getString(_themeKey);

    return _getThemeModeFromString(themeString);
  }

  void setTheme(ThemeMode mode) {
    if (state == mode) return;
    state = mode;

    final prefs = ref.read(sharedPreferencesProvider);
    prefs.setString(_themeKey, _getThemeStringFromMode(mode));
  }

  ThemeMode _getThemeModeFromString(String? themeString) {
    switch (themeString) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  String _getThemeStringFromMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
      default:
        return 'system';
    }
  }
}

final themeProvider = NotifierProvider<ThemeNotifier, ThemeMode>(
  ThemeNotifier.new,
);
