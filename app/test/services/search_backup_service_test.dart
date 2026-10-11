import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/services/search_backup_service.dart';

/// Synthetic -- never the real sample file seen during M11's planning, which
/// is a third party's personal data and was never committed to this repo.
/// Covers the same shapes that file demonstrated: a plain tag, a `pool:`
/// entry with its own label, a multi-tag `-exclude` entry, and a `~or` entry.
const _wolfsStashFixture = '''
[
  {"a": "", "b": 1, "c": ["somecreator"], "d": 1700000000000, "e": 1700000001000, "f": 0},
  {"a": "Some Comic - Chapter 1", "b": 1, "c": ["pool:12345"], "d": 1700000000000, "e": 1700000001000, "f": 3},
  {"a": "", "b": 8, "c": ["comic", "female", "-animal_pussy"], "d": 1700000000000, "e": 1700000001000, "f": 0},
  {"a": "", "b": 1, "c": ["~tentacle_in_pussy", "~tentacle_on_penis"], "d": 1700000000000, "e": 1700000001000, "f": 27},
  {"a": "", "b": 1, "c": [], "d": 1700000000000, "e": 1700000001000, "f": 0}
]
''';

BunnySearch _search({int id = 1, BunnySite site = BunnySite.e621, String label = 'label', String query = 'query', int intervalHours = 24, bool autoFavorite = false, int autoFavoriteStars = 1, bool autoUpvote = false}) =>
    BunnySearch(id: id, site: site, label: label, query: query, intervalHours: intervalHours, createdAt: '2026-01-01T00:00:00Z', autoFavorite: autoFavorite, autoFavoriteStars: autoFavoriteStars, autoUpvote: autoUpvote);

void main() {
  const service = SearchBackupService();

  group('exportSearches', () {
    test('maps every round-trippable field, dropping local-only ones', () {
      final json = service.exportSearches([_search(site: BunnySite.inkbunny, label: 'My label', query: 'fav:me', intervalHours: 12, autoFavorite: true, autoFavoriteStars: 3, autoUpvote: true)]);

      expect(json, [
        {'site': 'inkbunny', 'label': 'My label', 'query': 'fav:me', 'intervalHours': 12, 'autoFavorite': true, 'autoFavoriteStars': 3, 'autoUpvote': true},
      ]);
    });
  });

  group('parseImportFile -- this app\'s own format', () {
    test('round-trips exportSearches output', () {
      final exported = service.exportSearches([_search(site: BunnySite.e621, label: 'Wolves', query: 'wolf', intervalHours: 6, autoFavorite: true, autoFavoriteStars: 2, autoUpvote: true)]);

      final result = service.parseImportFile(jsonEncode(exported), defaultIntervalHours: 24);

      expect(result.format, ImportFormat.littleBunny);
      expect(result.invalidCount, 0);
      expect(result.entries, hasLength(1));
      final entry = result.entries.single;
      expect(entry.site, BunnySite.e621);
      expect(entry.label, 'Wolves');
      expect(entry.query, 'wolf');
      expect(entry.intervalHours, 6);
      expect(entry.autoFavorite, isTrue);
      expect(entry.autoFavoriteStars, 2);
      expect(entry.autoUpvote, isTrue);
    });

    test('falls back to the default interval and the query as label when absent', () {
      final result = service.parseImportFile(jsonEncode([{'site': 'e621', 'label': '', 'query': 'fox'}]), defaultIntervalHours: 48);

      final entry = result.entries.single;
      expect(entry.label, 'fox');
      expect(entry.intervalHours, 48);
      expect(entry.autoFavorite, isFalse);
      expect(entry.autoFavoriteStars, 1);
      expect(entry.autoUpvote, isFalse);
    });
  });

  group('parseImportFile -- Wolf\'s Stash format', () {
    test('maps plain tags, pool labels, exclusions, and OR groups', () {
      final result = service.parseImportFile(_wolfsStashFixture, defaultIntervalHours: 24);

      expect(result.format, ImportFormat.wolfsStash);
      expect(result.invalidCount, 1); // the empty-`c` entry
      expect(result.entries, hasLength(4));

      expect(result.entries[0].site, BunnySite.e621);
      expect(result.entries[0].label, 'somecreator'); // blank "a" falls back to the joined query
      expect(result.entries[0].query, 'somecreator');
      expect(result.entries[0].intervalHours, 24); // "b" is ignored

      expect(result.entries[1].label, 'Some Comic - Chapter 1');
      expect(result.entries[1].query, 'pool:12345');

      expect(result.entries[2].query, 'comic female -animal_pussy');
      expect(result.entries[2].intervalHours, 24); // "b": 8 is still ignored

      expect(result.entries[3].query, '~tentacle_in_pussy ~tentacle_on_penis');

      for (final entry in result.entries) {
        expect(entry.autoFavorite, isFalse);
        expect(entry.autoFavoriteStars, 1);
        expect(entry.autoUpvote, isFalse);
      }
    });
  });

  group('parseImportFile -- unrecognized input', () {
    test('malformed JSON', () {
      expect(service.parseImportFile('not json', defaultIntervalHours: 24).format, ImportFormat.unrecognized);
    });

    test('valid JSON that is not a list', () {
      expect(service.parseImportFile('{"a": 1}', defaultIntervalHours: 24).format, ImportFormat.unrecognized);
    });

    test('a list of objects matching neither known shape', () {
      expect(service.parseImportFile(jsonEncode([{'foo': 'bar'}]), defaultIntervalHours: 24).format, ImportFormat.unrecognized);
    });

    test('empty list', () {
      expect(service.parseImportFile('[]', defaultIntervalHours: 24).format, ImportFormat.unrecognized);
    });
  });
}
