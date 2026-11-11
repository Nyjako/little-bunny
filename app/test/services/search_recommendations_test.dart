import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/services/search_recommendations.dart';

BunnySearch _search({required int id, BunnySite site = BunnySite.e621, required String query}) =>
    BunnySearch(id: id, site: site, label: query, query: query, intervalHours: 24, createdAt: '2026-01-01T00:00:00Z');

BunnyStatsReport _report({List<BunnyTagStat> topTagPairs = const [], List<BunnyTagStat> topFavoritedTags = const []}) => BunnyStatsReport(
  computedAt: '2026-01-01T00:00:00Z',
  topFavoritedTags: topFavoritedTags,
  topUsedTags: const [],
  topPools: const [],
  topViewedSearches: const [],
  topTagPairs: topTagPairs,
);

void main() {
  group('buildSearchRecommendations', () {
    test('a tag pair becomes a two-tag query, space-joined', () {
      final report = _report(topTagPairs: [const BunnyTagStat(name: 'e621: forest + wolf', count: 5)]);
      final recommendations = buildSearchRecommendations(report, []);
      expect(recommendations, hasLength(1));
      expect(recommendations.single.site, BunnySite.e621);
      expect(recommendations.single.query, 'forest wolf');
      expect(recommendations.single.label, 'forest + wolf');
      expect(recommendations.single.count, 5);
    });

    test('excludes a pair already covered by an existing search, regardless of tag order', () {
      final report = _report(topTagPairs: [const BunnyTagStat(name: 'e621: forest + wolf', count: 5)]);
      final recommendations = buildSearchRecommendations(report, [_search(id: 1, query: 'wolf forest')]);
      expect(recommendations, isEmpty);
    });

    test('a pair on a different site than the matching existing search is still recommended', () {
      final report = _report(topTagPairs: [const BunnyTagStat(name: 'inkbunny: forest + wolf', count: 5)]);
      final recommendations = buildSearchRecommendations(report, [_search(id: 1, site: BunnySite.e621, query: 'wolf forest')]);
      expect(recommendations, hasLength(1));
    });

    test('pairs rank ahead of single favorited tags when both are present', () {
      final report = _report(
        topTagPairs: [const BunnyTagStat(name: 'e621: forest + wolf', count: 5)],
        topFavoritedTags: [const BunnyTagStat(name: 'e621: fox', count: 20)],
      );
      final recommendations = buildSearchRecommendations(report, [], limit: 1);
      expect(recommendations, hasLength(1));
      expect(recommendations.single.label, 'forest + wolf');
    });

    test('falls back to single favorited tags once pairs run out', () {
      final report = _report(
        topTagPairs: [const BunnyTagStat(name: 'e621: forest + wolf', count: 5)],
        topFavoritedTags: [const BunnyTagStat(name: 'e621: fox', count: 20)],
      );
      final recommendations = buildSearchRecommendations(report, [], limit: 2);
      expect(recommendations, hasLength(2));
      expect(recommendations.last.query, 'fox');
    });

    test('excludes a single tag already covered by an existing search', () {
      final report = _report(topFavoritedTags: [const BunnyTagStat(name: 'e621: fox', count: 20)]);
      final recommendations = buildSearchRecommendations(report, [_search(id: 1, query: 'fox')]);
      expect(recommendations, isEmpty);
    });

    test('caps the result at limit even with plenty of candidates', () {
      final report = _report(
        topFavoritedTags: [
          const BunnyTagStat(name: 'e621: a', count: 5),
          const BunnyTagStat(name: 'e621: b', count: 4),
          const BunnyTagStat(name: 'e621: c', count: 3),
        ],
      );
      final recommendations = buildSearchRecommendations(report, [], limit: 2);
      expect(recommendations, hasLength(2));
    });

    test('an empty report and no existing searches produces no recommendations', () {
      expect(buildSearchRecommendations(_report(), []), isEmpty);
    });

    test('ignores an entry with no recognizable site prefix rather than throwing', () {
      final report = _report(topTagPairs: [const BunnyTagStat(name: 'forest + wolf', count: 5)]);
      expect(buildSearchRecommendations(report, []), isEmpty);
    });
  });
}
