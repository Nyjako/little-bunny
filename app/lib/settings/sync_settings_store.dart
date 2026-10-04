import 'package:shared_preferences/shared_preferences.dart';

/// Persists the default sync interval (hours) pre-filled into
/// [CreateSearchScreen]'s interval field (`shared_preferences`, same shape as
/// [ThemeSettingsStore]/[AppLockService] in this directory) -- defaults to 24
/// when nothing has been chosen yet, matching `bunny_db`'s own schema
/// default. Purely a client-side UX convenience: there's no equivalent
/// backend setting, since the sync engine only ever reads each search's own
/// `interval_hours`.
class SyncSettingsStore {
  static const _key = 'default_sync_interval_hours';

  const SyncSettingsStore();

  Future<int> loadDefaultIntervalHours() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_key) ?? 24;
  }

  Future<void> saveDefaultIntervalHours(int hours) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, hours);
  }
}
