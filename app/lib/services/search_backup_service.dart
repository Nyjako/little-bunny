import 'dart:convert';

import '../repository/bunny_models.dart';

/// A search parsed out of an import file, ready to be passed straight into
/// [BunnyRepository.createSearch] -- deliberately missing the local-only
/// fields [BunnySearch] carries (`id`/`createdAt`/`lastRunAt`/`unseenCount`),
/// since those are either assigned by `bunny_db` or computed live and never
/// meaningful to import from somewhere else.
class ImportSearchEntry {
  final BunnySite site;
  final String label;
  final String query;
  final int intervalHours;
  final bool autoFavorite;
  final int autoFavoriteStars;
  final bool autoUpvote;

  const ImportSearchEntry({
    required this.site,
    required this.label,
    required this.query,
    required this.intervalHours,
    this.autoFavorite = false,
    this.autoFavoriteStars = 1,
    this.autoUpvote = false,
  });
}

enum ImportFormat { littleBunny, wolfsStash, unrecognized }

class ImportParseResult {
  final ImportFormat format;
  final List<ImportSearchEntry> entries;

  /// Entries present in the file but dropped before reaching [entries] --
  /// e.g. a Wolf's Stash row whose tag array joins into an empty string.
  final int invalidCount;

  const ImportParseResult({required this.format, required this.entries, this.invalidCount = 0});

  static const unrecognized = ImportParseResult(format: ImportFormat.unrecognized, entries: []);
}

/// Pure logic, no widget -- same `services/` shape as [DownloadManager]
/// (M9.4): independently unit-testable, with the actual `createSearch` loop
/// and dedup-against-current-state left to the caller (M11), since that
/// needs live repository data this class has no business holding.
///
/// Supports two input shapes, auto-detected from the parsed JSON's own
/// structure rather than the file's name or extension (no public spec exists
/// for either format, and the real "Wolf's Stash" sample seen during M11's
/// planning was named `.tws2`, not the `.tws_plain` the roadmap had guessed
/// at):
/// - This app's own export format (see [exportSearches]): a JSON array of
///   objects with `site`/`label`/`query` keys.
/// - "The Wolf's Stash" (`https://zepiwolf.se/tws/`) export format: a JSON
///   array of objects with exactly the keys `a` (label, often empty), `b`
///   (unconfirmed meaning -- ignored), `c` (array of tag tokens to AND
///   together, including `-exclude`/`~or-group`/`pool:<id>` forms), `d`/`e`
///   (created/checked timestamps -- ignored, this app's own scheduling means
///   something different) and `f` (unseen count at export time -- ignored,
///   this app computes its own live). Every entry in this format is treated
///   as e621 -- the tool has no Inkbunny equivalent.
class SearchBackupService {
  const SearchBackupService();

  List<Map<String, dynamic>> exportSearches(List<BunnySearch> searches) => searches
      .map(
        (search) => {
          'site': search.site.toWireString(),
          'label': search.label,
          'query': search.query,
          'intervalHours': search.intervalHours,
          'autoFavorite': search.autoFavorite,
          'autoFavoriteStars': search.autoFavoriteStars,
          'autoUpvote': search.autoUpvote,
        },
      )
      .toList();

  ImportParseResult parseImportFile(String contents, {required int defaultIntervalHours}) {
    dynamic decoded;
    try {
      decoded = jsonDecode(contents);
    } catch (_) {
      return ImportParseResult.unrecognized;
    }
    if (decoded is! List || decoded.isEmpty) {
      return ImportParseResult.unrecognized;
    }
    if (decoded.every((item) => item is Map && item.containsKey('site') && item.containsKey('label') && item.containsKey('query'))) {
      return _parseLittleBunnyFormat(decoded.cast<Map>(), defaultIntervalHours);
    }
    if (decoded.every((item) => item is Map && const {'a', 'b', 'c', 'd', 'e', 'f'}.containsAll(item.keys) && item.length == 6)) {
      return _parseWolfsStashFormat(decoded.cast<Map>(), defaultIntervalHours);
    }
    return ImportParseResult.unrecognized;
  }

  ImportParseResult _parseLittleBunnyFormat(List<Map> rows, int defaultIntervalHours) {
    final entries = <ImportSearchEntry>[];
    var invalid = 0;
    for (final row in rows) {
      final query = row['query'] as String?;
      if (query == null || query.isEmpty) {
        invalid++;
        continue;
      }
      final label = row['label'] as String?;
      entries.add(
        ImportSearchEntry(
          site: BunnySite.fromWireString(row['site'] as String),
          label: (label == null || label.isEmpty) ? query : label,
          query: query,
          intervalHours: (row['intervalHours'] as int?) ?? defaultIntervalHours,
          autoFavorite: (row['autoFavorite'] as bool?) ?? false,
          autoFavoriteStars: (row['autoFavoriteStars'] as int?) ?? 1,
          autoUpvote: (row['autoUpvote'] as bool?) ?? false,
        ),
      );
    }
    return ImportParseResult(format: ImportFormat.littleBunny, entries: entries, invalidCount: invalid);
  }

  ImportParseResult _parseWolfsStashFormat(List<Map> rows, int defaultIntervalHours) {
    final entries = <ImportSearchEntry>[];
    var invalid = 0;
    for (final row in rows) {
      final tags = (row['c'] as List).cast<String>();
      final query = tags.join(' ').trim();
      if (query.isEmpty) {
        invalid++;
        continue;
      }
      final label = row['a'] as String;
      entries.add(ImportSearchEntry(site: BunnySite.e621, label: label.isEmpty ? query : label, query: query, intervalHours: defaultIntervalHours));
    }
    return ImportParseResult(format: ImportFormat.wolfsStash, entries: entries, invalidCount: invalid);
  }
}
