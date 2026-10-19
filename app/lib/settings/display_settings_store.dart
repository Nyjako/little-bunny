import 'package:shared_preferences/shared_preferences.dart';

/// Which image variant [PostGridScreen] loads per tile. `thumbnail` is the
/// smallest/fastest (`BunnyPost.previewUrl`); `medium` prefers the
/// sample/screen variant (`BunnyPost.sampleUrl`) when the post has one,
/// falling back to the thumbnail otherwise (e.g. every Inkbunny post synced
/// via search alone, which never gets a sample URL -- see architecture.md).
enum PreviewQuality { thumbnail, medium }

/// How [SearchesScreen] orders its saved-search list (M13.1). `mostUnseen`
/// is the default -- surfacing searches with new results first is more
/// useful day-to-day than alphabetical order.
enum SearchSortOrder { mostUnseen, label, recentlyCreated, lastViewed }

/// Persists the grid's preview image quality and column count, and the
/// searches list's sort order (`shared_preferences`, same shape as
/// [ThemeSettingsStore] in this directory) -- defaults to
/// [PreviewQuality.thumbnail], 3 columns, and [SearchSortOrder.mostUnseen]
/// when nothing has been chosen yet, matching [PostGridScreen]'s pre-M8.5.6
/// hardcoded behavior.
class DisplaySettingsStore {
  static const _qualityKey = 'preview_quality';
  static const _columnsKey = 'grid_columns';
  static const _searchSortOrderKey = 'search_sort_order';
  static const _preloadCountKey = 'image_preload_count';

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

  Future<SearchSortOrder> loadSearchSortOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_searchSortOrderKey);
    return SearchSortOrder.values.firstWhere((order) => order.name == name, orElse: () => SearchSortOrder.mostUnseen);
  }

  Future<void> saveSearchSortOrder(SearchSortOrder order) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_searchSortOrderKey, order.name);
  }

  /// How many images [PostDetailScreen]/[FullScreenPostViewerScreen]
  /// precache in each direction (next/previous) from whichever post is
  /// currently shown -- 3 by default, so up to 7 images (3 behind, the
  /// current one, 3 ahead) sit decoded in memory at once, trading some
  /// memory for swiping through a gallery feeling instant either direction.
  Future<int> loadImagePreloadCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_preloadCountKey) ?? 3;
  }

  Future<void> saveImagePreloadCount(int count) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_preloadCountKey, count);
  }
}
