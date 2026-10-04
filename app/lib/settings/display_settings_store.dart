import 'package:shared_preferences/shared_preferences.dart';

/// Which image variant [PostGridScreen] loads per tile. `thumbnail` is the
/// smallest/fastest (`BunnyPost.previewUrl`); `medium` prefers the
/// sample/screen variant (`BunnyPost.sampleUrl`) when the post has one,
/// falling back to the thumbnail otherwise (e.g. every Inkbunny post synced
/// via search alone, which never gets a sample URL -- see architecture.md).
enum PreviewQuality { thumbnail, medium }

/// Persists the grid's preview image quality and column count
/// (`shared_preferences`, same shape as [ThemeSettingsStore]/
/// [SyncSettingsStore] in this directory) -- defaults to
/// [PreviewQuality.thumbnail] and 3 columns when nothing has been chosen yet,
/// matching [PostGridScreen]'s pre-M8.5.6 hardcoded behavior.
class DisplaySettingsStore {
  static const _qualityKey = 'preview_quality';
  static const _columnsKey = 'grid_columns';

  const DisplaySettingsStore();

  Future<PreviewQuality> loadPreviewQuality() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_qualityKey);
    return PreviewQuality.values.firstWhere((quality) => quality.name == name, orElse: () => PreviewQuality.thumbnail);
  }

  Future<void> savePreviewQuality(PreviewQuality quality) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_qualityKey, quality.name);
  }

  Future<int> loadGridColumns() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_columnsKey) ?? 3;
  }

  Future<void> saveGridColumns(int columns) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_columnsKey, columns);
  }
}
