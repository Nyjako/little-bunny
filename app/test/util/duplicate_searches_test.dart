import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/util/duplicate_searches.dart';

BunnySearch _search({required int id, BunnySite site = BunnySite.e621, required String query, String label = 'label'}) =>
    BunnySearch(id: id, site: site, label: label, query: query, intervalHours: 24, createdAt: '2026-01-01T00:00:00Z');

void main() {
  group('findDuplicateSearchGroups', () {
    test('returns nothing when every (site, query) pair is unique', () {
      final searches = [_search(id: 1, query: 'wolf'), _search(id: 2, query: 'fox')];
      expect(findDuplicateSearchGroups(searches), isEmpty);
    });

    test('groups two searches sharing the same (site, query)', () {
      final searches = [_search(id: 1, query: 'wolf'), _search(id: 2, query: 'wolf')];
      final groups = findDuplicateSearchGroups(searches);
      expect(groups, hasLength(1));
      expect(groups.single.map((s) => s.id), containsAll([1, 2]));
    });

    test('groups three searches sharing the same (site, query) into one group', () {
      final searches = [_search(id: 1, query: 'wolf'), _search(id: 2, query: 'wolf'), _search(id: 3, query: 'wolf')];
      final groups = findDuplicateSearchGroups(searches);
      expect(groups, hasLength(1));
      expect(groups.single, hasLength(3));
    });

    test('the same query on different sites is not a duplicate', () {
      final searches = [_search(id: 1, site: BunnySite.e621, query: 'wolf'), _search(id: 2, site: BunnySite.inkbunny, query: 'wolf')];
      expect(findDuplicateSearchGroups(searches), isEmpty);
    });

    test('a pool query duplicate is detected the same way as a regular one', () {
      final searches = [_search(id: 1, query: 'pool:42'), _search(id: 2, query: 'pool:42')];
      final groups = findDuplicateSearchGroups(searches);
      expect(groups, hasLength(1));
      expect(groups.single.map((s) => s.id), containsAll([1, 2]));
    });

    test('multiple independent duplicate groups are all reported', () {
      final searches = [_search(id: 1, query: 'wolf'), _search(id: 2, query: 'wolf'), _search(id: 3, query: 'fox'), _search(id: 4, query: 'fox'), _search(id: 5, query: 'cat')];
      final groups = findDuplicateSearchGroups(searches);
      expect(groups, hasLength(2));
      expect(groups.map((g) => g.length), everyElement(2));
    });
  });
}
