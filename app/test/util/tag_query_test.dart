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
}
