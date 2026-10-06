import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's chosen download destination folder
/// (`shared_preferences`, same shape as every other store in this
/// directory). Nothing is stored until the user explicitly picks a folder in
/// [SettingsScreen] -- [loadDestinationFolder] falls back to
/// [getDownloadsDirectory] (the OS's own Downloads folder) in that case,
/// recomputed fresh each call rather than cached, same reasoning as
/// [RepositorySettingsStore]'s standalone db path default.
class DownloadSettingsStore {
  static const _key = 'download_destination_folder';
  static const _autoFavoriteKey = 'auto_favorite_on_download';

  const DownloadSettingsStore();

  Future<String?> loadDestinationFolder() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null) {
      return saved;
    }
    final dir = await getDownloadsDirectory();
    return dir?.path;
  }

  Future<void> saveDestinationFolder(String folder) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, folder);
  }

  /// Whether downloading a post should also queue a favorite-add for it
  /// (M10.1) -- a separate, download-triggered counterpart to the
  /// sync-triggered auto-favorite a saved search can already do (M9.6.8).
  /// Defaults to off.
  Future<bool> loadAutoFavoriteOnDownload() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoFavoriteKey) ?? false;
  }

  Future<void> saveAutoFavoriteOnDownload(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoFavoriteKey, enabled);
  }
}
