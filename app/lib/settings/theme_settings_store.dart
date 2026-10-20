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

/// Persists the chosen [ThemeMode], [ThemeColorOption], AMOLED
/// ("true black" dark backgrounds, M27) setting, and language override
/// (M30) across restarts (`shared_preferences`, same shape as
/// [RepositorySettingsStore]/[AppLockService] in this directory) -- defaults
/// to [ThemeMode.dark] (per the user's stated preference),
/// [ThemeColorOption.purple], AMOLED off, and no language override (follow
/// the device's own locale) when nothing has been chosen yet.
class ThemeSettingsStore {
  static const _key = 'theme_mode';
  static const _colorKey = 'theme_color';
  static const _amoledKey = 'theme_amoled';
  static const _languageCodeKey = 'language_code';

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

  /// Null means "no manual override -- follow the device's own locale,
  /// falling back to [AppLocalizations.supportedLocales]'s first entry
  /// (English) if the device's language isn't one this app ships yet."
  /// That fallback chain is Flutter's own built-in locale resolution
  /// (MaterialApp's `locale` param left unset); a manual override here is
  /// the one case that takes priority over it (M30) -- "manual setting >
  /// device language > default language" is the full resolution order the
  /// user asked for, and only this first tier needs any code at all, since
  /// the other two are what `locale: null` already does.
  Future<String?> loadLanguageCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_languageCodeKey);
  }

  Future<void> saveLanguageCode(String? languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    if (languageCode == null) {
      await prefs.remove(_languageCodeKey);
    } else {
      await prefs.setString(_languageCodeKey, languageCode);
    }
  }
}
