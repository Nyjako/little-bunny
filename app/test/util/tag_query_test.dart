import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/util/tag_query.dart';

import '../fakes/fake_bunny_repository.dart';

BunnyTagImplication _implication(String antecedent, String consequent, {String status = 'active'}) =>
    BunnyTagImplication(id: 0, antecedentName: antecedent, consequentName: consequent, status: status);

void main() {
  group('tagTokenRangeAt', () {
    test('finds the trailing token when the cursor is at the end', () {
      final (start, end) = tagTokenRangeAt('canine fo', 9);
      expect('canine fo'.substring(start, end), 'fo');
    });

    test('finds the token under a mid-string cursor', () {
      const text = 'cat -dog standing';
      // Cursor placed inside "-dog" (index 6, between '-' and 'd'... let's
      // land it right after the 'd' in "-dog").
      final (start, end) = tagTokenRangeAt(text, 7);
      expect(text.substring(start, end), '-dog');
    });

    test('returns an empty range for an empty string', () {
      final (start, end) = tagTokenRangeAt('', 0);
      expect(start, 0);
      expect(end, 0);
    });

    test('finds the first token when the cursor is at offset 0', () {
      final (start, end) = tagTokenRangeAt('cat dog', 0);
      expect('cat dog'.substring(start, end), 'cat');
    });
  });

  group('splitTagPrefix', () {
    test('plain tag has no prefix', () {
      final (prefix, tag) = splitTagPrefix('fox');
      expect(prefix, '');
      expect(tag, 'fox');
    });

    test('strips a leading -', () {
      final (prefix, tag) = splitTagPrefix('-dog');
      expect(prefix, '-');
      expect(tag, 'dog');
    });

    test('strips a leading ~', () {
      final (prefix, tag) = splitTagPrefix('~cat');
      expect(prefix, '~');
      expect(tag, 'cat');
    });

    test('strips a leading (', () {
      final (prefix, tag) = splitTagPrefix('(cat');
      expect(prefix, '(');
      expect(tag, 'cat');
    });

    test('strips a run of mixed prefix characters', () {
      final (prefix, tag) = splitTagPrefix('-(~cat');
      expect(prefix, '-(~');
      expect(tag, 'cat');
    });

    test('an all-prefix token has an empty tag', () {
      final (prefix, tag) = splitTagPrefix('-(');
      expect(prefix, '-(');
      expect(tag, '');
    });
  });

  group('tagHasWildcard', () {
    test('detects a wildcard', () {
      expect(tagHasWildcard('african_*'), isTrue);
    });

    test('plain tags have no wildcard', () {
      expect(tagHasWildcard('fox'), isFalse);
    });
  });

  group('applyTagSuggestion', () {
    test('appends a suggestion to the trailing token with a trailing space', () {
      final (text, cursor) = applyTagSuggestion('canine fo', 9, 'fox');
      expect(text, 'canine fox ');
      expect(cursor, text.length);
    });

    test('preserves a negation prefix when replacing the token', () {
      final (text, cursor) = applyTagSuggestion('cat -do', 7, 'dog');
      expect(text, 'cat -dog ');
      expect(cursor, text.length);
    });

    test('replaces a mid-string token without disturbing the rest of the query', () {
      final (text, cursor) = applyTagSuggestion('cat -do standing', 7, 'dog');
      expect(text, 'cat -dog  standing');
      expect(cursor, 'cat -dog '.length);
    });
  });

  group('queryHasBareTag', () {
    test('finds a plain tag', () {
      expect(queryHasBareTag('cat dog', 'dog'), isTrue);
    });

    test('finds a tag regardless of its prefix', () {
      expect(queryHasBareTag('cat -dog', 'dog'), isTrue);
      expect(queryHasBareTag('cat ~dog', 'dog'), isTrue);
    });

    test('a tag not present returns false', () {
      expect(queryHasBareTag('cat dog', 'fox'), isFalse);
    });
  });

  group('addTagToQuery', () {
    test('appends to an empty query', () {
      expect(addTagToQuery('', 'cat'), 'cat');
    });

    test('appends to a non-empty query', () {
      expect(addTagToQuery('cat', 'dog'), 'cat dog');
    });

    test('replaces an existing excluded occurrence rather than duplicating it', () {
      expect(addTagToQuery('cat -dog', 'dog'), 'cat dog');
    });

    test('adding an already-present plain tag is a no-op', () {
      expect(addTagToQuery('cat dog', 'dog'), 'cat dog');
    });
  });

  group('excludeTagInQuery', () {
    test('appends as an excluded token', () {
      expect(excludeTagInQuery('cat', 'dog'), 'cat -dog');
    });

    test('replaces an existing plain occurrence rather than duplicating it', () {
      expect(excludeTagInQuery('cat dog', 'dog'), 'cat -dog');
    });

    test('excluding an already-excluded tag is idempotent', () {
      expect(excludeTagInQuery('cat -dog', 'dog'), 'cat -dog');
    });

    test('works from an empty query', () {
      expect(excludeTagInQuery('', 'dog'), '-dog');
    });
  });

  group('removeTagFromQuery', () {
    test('removes a plain tag', () {
      expect(removeTagFromQuery('cat dog', 'dog'), 'cat');
    });

    test('removes an excluded tag', () {
      expect(removeTagFromQuery('cat -dog', 'dog'), 'cat');
    });

    test('removing the only tag leaves an empty string', () {
      expect(removeTagFromQuery('dog', 'dog'), '');
    });

    test('removing a tag not present is a no-op', () {
      expect(removeTagFromQuery('cat dog', 'fox'), 'cat dog');
    });
  });

  group('queryIsPoolSentinel', () {
    test('an exact pool:<id> query is a pool sentinel', () {
      expect(queryIsPoolSentinel('pool:123'), isTrue);
    });

    test('a tag-polluted pool query is not', () {
      expect(queryIsPoolSentinel('pool:123 sometag'), isFalse);
    });

    test('a plain tag query is not', () {
      expect(queryIsPoolSentinel('cat'), isFalse);
    });

    test('a non-numeric pool id is not', () {
      expect(queryIsPoolSentinel('pool:abc'), isFalse);
    });
  });

  group('resolveTagImplicationChain', () {
    test('walks a multi-hop chain in order, including the starting tag', () async {
      final repository = FakeBunnyRepository();
      repository.tagImplicationsByNameMatches['hyper_breasts'] = [_implication('hyper_breasts', 'huge_breasts')];
      repository.tagImplicationsByNameMatches['huge_breasts'] = [_implication('huge_breasts', 'big_breasts')];
      repository.tagImplicationsByNameMatches['big_breasts'] = [_implication('big_breasts', 'breasts')];

      final chain = await resolveTagImplicationChain(repository, 'hyper_breasts');

      expect(chain, ['hyper_breasts', 'huge_breasts', 'big_breasts', 'breasts']);
    });

    test('returns an empty list for a tag with no active implication', () async {
      final repository = FakeBunnyRepository();

      expect(await resolveTagImplicationChain(repository, 'cat'), isEmpty);
    });

    test('ignores a pending (not-yet-active) implication', () async {
      final repository = FakeBunnyRepository();
      repository.tagImplicationsByNameMatches['cat'] = [_implication('cat', 'felid', status: 'pending')];

      expect(await resolveTagImplicationChain(repository, 'cat'), isEmpty);
    });

    test('stops and lists every consequent when a tag has more than one active implication', () async {
      final repository = FakeBunnyRepository();
      repository.tagImplicationsByNameMatches['chimera'] = [_implication('chimera', 'multiple_heads'), _implication('chimera', 'hybrid')];

      final chain = await resolveTagImplicationChain(repository, 'chimera');

      expect(chain, ['chimera', 'multiple_heads', 'hybrid']);
    });

    test('stops at a cycle instead of looping forever', () async {
      final repository = FakeBunnyRepository();
      repository.tagImplicationsByNameMatches['a'] = [_implication('a', 'b')];
      repository.tagImplicationsByNameMatches['b'] = [_implication('b', 'a')];

      final chain = await resolveTagImplicationChain(repository, 'a');

      expect(chain, ['a', 'b']);
    });

    test('caps at maxHops for a pathologically long chain', () async {
      final repository = FakeBunnyRepository();
      for (var i = 0; i < 20; i++) {
        repository.tagImplicationsByNameMatches['tag$i'] = [_implication('tag$i', 'tag${i + 1}')];
      }

      final chain = await resolveTagImplicationChain(repository, 'tag0', maxHops: 5);

      expect(chain, hasLength(6)); // starting tag + 5 hops
    });
  });
}
