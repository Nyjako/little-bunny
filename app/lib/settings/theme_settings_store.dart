import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the chosen [ThemeMode] across restarts (`shared_preferences`,
/// same shape as [RepositorySettingsStore]/[AppLockService] in this
/// directory) -- defaults to [ThemeMode.dark] when nothing has been chosen
/// yet, per the user's stated preference.
class ThemeSettingsStore {
  static const _key = 'theme_mode';

  const ThemeSettingsStore();

  Future<ThemeMode> load() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_key);
    return ThemeMode.values.firstWhere((mode) => mode.name == name, orElse: () => ThemeMode.dark);
  }

  Future<void> save(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }
}
