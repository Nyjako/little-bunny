import '../repository/bunny_models.dart';
import '../util/site_prefixed_name.dart';

/// A suggested search, not yet saved -- built from [BunnyStatsReport.
/// topTagPairs]/[BunnyStatsReport.topFavoritedTags] by [buildSearchRecommendations],
/// which already excludes anything the user has an equivalent search for.
class RecommendedSearch {
  final BunnySite site;

  /// The actual tag query a search/preview would run, e.g. `"male/female
  /// duo"` for a pair, or a single tag name.
  final String query;

  /// Display label -- the pair joined with " + " (matching how the stats
  /// report itself renders a pair, see [BunnyStatsReport.topTagPairs]'s own
  /// doc comment) or the single tag name, without the site prefix.
  final String label;

  final int count;

  const RecommendedSearch({required this.site, required this.query, required this.label, required this.count});
}

/// Tokenizes a tag query the same way e621/Inkbunny's own space-separated
/// syntax does, lowercased and order-independent -- the de-dup key: a saved
/// search `"duo male/female"` must exclude a candidate `"male/female duo"`
/// even though the token order differs.
Set<String> _queryFingerprint(String query) => query.toLowerCase().split(RegExp(r'\s+')).where((token) => token.isNotEmpty).toSet();

/// Builds up to [limit] [RecommendedSearch]es from [report], ranking tag
/// *pairs* that co-occur on favorited posts ahead of single favorited tags
/// (pairs are the stronger signal -- a tag favorited a lot is already
/// visible as its own stats-report section, see M10.2's original "the tag
/// itself is the recommendation" design), falling back to single tags only
/// if there aren't enough pairs left after filtering. Excludes any
/// candidate whose [_queryFingerprint] already matches one of
/// [existingSearches] on the same site, so a search the user already has
/// (in any tag order) is never suggested again.
List<RecommendedSearch> buildSearchRecommendations(BunnyStatsReport report, List<BunnySearch> existingSearches, {int limit = 5}) {
  final existingFingerprintsBySite = <BunnySite, Set<Set<String>>>{};
  for (final search in existingSearches) {
    (existingFingerprintsBySite[search.site] ??= {}).add(_queryFingerprint(search.query));
  }

  bool alreadyCovered(BunnySite site, Set<String> fingerprint) => (existingFingerprintsBySite[site] ?? const {}).any((existing) => existing.length == fingerprint.length && existing.containsAll(fingerprint));

  final recommendations = <RecommendedSearch>[];

  for (final pair in report.topTagPairs) {
    final split = splitSitePrefixedName(pair.name);
    if (split == null) {
      continue;
    }
    final (site, pairLabel) = split;
    final tags = pairLabel.split(' + ');
    if (tags.length != 2) {
      continue;
    }
    final query = tags.join(' ');
    final fingerprint = _queryFingerprint(query);
    if (alreadyCovered(site, fingerprint)) {
      continue;
    }
    recommendations.add(RecommendedSearch(site: site, query: query, label: pairLabel, count: pair.count));
  }

  if (recommendations.length < limit) {
    for (final tag in report.topFavoritedTags) {
      if (recommendations.length >= limit) {
        break;
      }
      final split = splitSitePrefixedName(tag.name);
      if (split == null) {
        continue;
      }
      final (site, label) = split;
      final fingerprint = _queryFingerprint(label);
      if (alreadyCovered(site, fingerprint)) {
        continue;
      }
      recommendations.add(RecommendedSearch(site: site, query: label, label: label, count: tag.count));
    }
  }

  return recommendations.take(limit).toList(growable: false);
}
