import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/util/tag_query.dart';

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
}
