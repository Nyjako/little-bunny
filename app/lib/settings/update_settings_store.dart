import 'package:shared_preferences/shared_preferences.dart';

/// Whether [SearchesScreen]'s once-per-launch update check (M23) runs
/// automatically, or only when the user taps "Check for app update" in
/// [AboutScreen]. Defaults to true -- preserves pre-existing behavior for
/// anyone who never touches this setting.
class UpdateSettingsStore {
  static const _autoCheckKey = 'update_auto_check_enabled';

  const UpdateSettingsStore();

  Future<bool> loadAutoCheckEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoCheckKey) ?? true;
  }

  Future<void> saveAutoCheckEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoCheckKey, enabled);
  }
}
