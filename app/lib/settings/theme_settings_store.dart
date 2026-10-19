import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The seed colors [ColorScheme.fromSeed] derives the whole app's palette
/// from -- `purple` is the long-standing default (M1's original choice),
/// the rest are just other common Material seed colors.
enum ThemeColorOption {
  purple(Colors.deepPurple),
  blue(Colors.blue),
  green(Colors.green),
  orange(Colors.deepOrange),
  red(Colors.red),
  teal(Colors.teal),
  pink(Colors.pink);

  final Color seedColor;
  const ThemeColorOption(this.seedColor);
}

/// Persists the chosen [ThemeMode], [ThemeColorOption], and AMOLED
/// ("true black" dark backgrounds, M27) setting across restarts
/// (`shared_preferences`, same shape as [RepositorySettingsStore]/
/// [AppLockService] in this directory) -- defaults to [ThemeMode.dark] (per
/// the user's stated preference), [ThemeColorOption.purple], and AMOLED off
/// when nothing has been chosen yet.
class ThemeSettingsStore {
  static const _key = 'theme_mode';
  static const _colorKey = 'theme_color';
  static const _amoledKey = 'theme_amoled';

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

  Future<ThemeColorOption> loadColor() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_colorKey);
    return ThemeColorOption.values.firstWhere((color) => color.name == name, orElse: () => ThemeColorOption.purple);
  }

  Future<void> saveColor(ThemeColorOption color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_colorKey, color.name);
  }

  /// Only takes visible effect in dark mode -- a "true black" light theme
  /// isn't a meaningful concept, there's nothing to save OLED pixels from.
  Future<bool> loadAmoled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_amoledKey) ?? false;
  }

  Future<void> saveAmoled(bool amoled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_amoledKey, amoled);
  }
}
