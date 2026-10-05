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
}
