import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/util/rich_markup.dart';

void main() {
  group('parseRichMarkup', () {
    test('plain text with no markup is a single text segment', () {
      final segments = parseRichMarkup('A description with no special markup.');
      expect(segments, [isA<RichMarkupTextSegment>().having((s) => s.text, 'text', 'A description with no special markup.')]);
    });

    test('an empty description produces no segments at all', () {
      expect(parseRichMarkup(''), isEmpty);
    });

    test('an author reference mid-sentence splits into text/author/text', () {
      final segments = parseRichMarkup('Art by {{someartist}} this week.');
      expect(segments, hasLength(3));
      expect((segments[0] as RichMarkupTextSegment).text, 'Art by ');
      final author = segments[1] as RichMarkupAuthorSegment;
      expect(author.authorName, 'someartist');
      expect(author.matchedText, '{{someartist}}');
      expect((segments[2] as RichMarkupTextSegment).text, ' this week.');
    });

    test('a wiki reference mid-sentence splits into text/wiki/text', () {
      final segments = parseRichMarkup('See [[canine]] for details.');
      expect(segments, hasLength(3));
      final wiki = segments[1] as RichMarkupWikiSegment;
      expect(wiki.title, 'canine');
      expect(wiki.matchedText, '[[canine]]');
    });

    test('a thumb reference mid-sentence splits into text/post/text, always e621', () {
      final segments = parseRichMarkup('Related: thumb #12345 above.');
      expect(segments, hasLength(3));
      final post = segments[1] as RichMarkupPostSegment;
      expect(post.site, BunnySite.e621);
      expect(post.postId, 12345);
      expect(post.matchedText, 'thumb #12345');
    });

    test('a pool reference mid-sentence splits into text/pool/text', () {
      final segments = parseRichMarkup('See pool #456 for the sequel.');
      expect(segments, hasLength(3));
      final pool = segments[1] as RichMarkupPoolSegment;
      expect(pool.poolId, 456);
      expect(pool.matchedText, 'pool #456');
    });

    test('a bare URL is linkified', () {
      final segments = parseRichMarkup('Source: https://example.com/page here.');
      expect(segments, hasLength(3));
      final url = segments[1] as RichMarkupUrlSegment;
      expect(url.url, 'https://example.com/page');
      expect((segments[2] as RichMarkupTextSegment).text, ' here.');
    });

    test('trailing sentence punctuation is excluded from the URL', () {
      final segments = parseRichMarkup('See https://example.com.');
      expect(segments, hasLength(3));
      expect((segments[1] as RichMarkupUrlSegment).url, 'https://example.com');
      expect((segments[2] as RichMarkupTextSegment).text, '.');
    });

    test('a URL wrapped in parentheses keeps the closing paren out of the link', () {
      final segments = parseRichMarkup('(https://example.com/x)');
      expect(segments, hasLength(3));
      expect((segments[0] as RichMarkupTextSegment).text, '(');
      expect((segments[1] as RichMarkupUrlSegment).url, 'https://example.com/x');
      expect((segments[2] as RichMarkupTextSegment).text, ')');
    });

    group('post/pool permalink URLs are recognized for in-app opening', () {
      test('an e621.net post URL becomes a post segment', () {
        final segments = parseRichMarkup('See https://e621.net/posts/12345 for the original.');
        final post = segments[1] as RichMarkupPostSegment;
        expect(post.site, BunnySite.e621);
        expect(post.postId, 12345);
        expect(post.matchedText, 'https://e621.net/posts/12345');
      });

      test('an e621.net old-style post URL (/post/show/<id>) becomes a post segment', () {
        final segments = parseRichMarkup('https://e621.net/post/show/777');
        final post = segments[0] as RichMarkupPostSegment;
        expect(post.site, BunnySite.e621);
        expect(post.postId, 777);
      });

      test('an e926.net post URL (safe-mode mirror) becomes a post segment', () {
        final segments = parseRichMarkup('https://e926.net/posts/555');
        final post = segments[0] as RichMarkupPostSegment;
        expect(post.site, BunnySite.e621);
        expect(post.postId, 555);
      });

      test('an e621.net pool URL becomes a pool segment', () {
        final segments = parseRichMarkup('https://e621.net/pools/99');
        final pool = segments[0] as RichMarkupPoolSegment;
        expect(pool.poolId, 99);
      });

      test('an inkbunny.net submission URL becomes a post segment for Inkbunny', () {
        final segments = parseRichMarkup('https://inkbunny.net/s/1234567');
        final post = segments[0] as RichMarkupPostSegment;
        expect(post.site, BunnySite.inkbunny);
        expect(post.postId, 1234567);
      });

      test('a www. prefix is still recognized', () {
        final segments = parseRichMarkup('https://www.e621.net/posts/42');
        final post = segments[0] as RichMarkupPostSegment;
        expect(post.site, BunnySite.e621);
        expect(post.postId, 42);
      });

      test('an unrelated URL on the same domain stays a plain link', () {
        final segments = parseRichMarkup('https://e621.net/help/show');
        expect(segments[0], isA<RichMarkupUrlSegment>());
      });

      test('an unrelated domain entirely stays a plain link', () {
        final segments = parseRichMarkup('https://example.com/posts/12345');
        expect(segments[0], isA<RichMarkupUrlSegment>());
      });
    });

    test('markup at the very start has no leading text segment', () {
      final segments = parseRichMarkup('{{someartist}} drew this.');
      expect(segments, hasLength(2));
      expect(segments[0], isA<RichMarkupAuthorSegment>());
    });

    test('markup at the very end has no trailing text segment', () {
      final segments = parseRichMarkup('Drawn by {{someartist}}');
      expect(segments, hasLength(2));
      expect(segments[1], isA<RichMarkupAuthorSegment>());
    });

    test('multiple different markup kinds in one description', () {
      final segments = parseRichMarkup('{{artist}} drew [[a_tag]], see thumb #1 or pool #2 or https://example.com.');
      final kinds = segments.map((s) => s.runtimeType).toList();
      expect(kinds, [
        RichMarkupAuthorSegment,
        RichMarkupTextSegment,
        RichMarkupWikiSegment,
        RichMarkupTextSegment,
        RichMarkupPostSegment,
        RichMarkupTextSegment,
        RichMarkupPoolSegment,
        RichMarkupTextSegment,
        RichMarkupUrlSegment,
        RichMarkupTextSegment,
      ]);
    });

    test('an unterminated "{{" with no closing "}}" is left as plain text', () {
      final segments = parseRichMarkup('A {{broken reference.');
      expect(segments, [isA<RichMarkupTextSegment>().having((s) => s.text, 'text', 'A {{broken reference.')]);
    });

    test('"thumb #" with no digits after it is left as plain text', () {
      final segments = parseRichMarkup('A thumb #for display.');
      expect(segments, [isA<RichMarkupTextSegment>().having((s) => s.text, 'text', 'A thumb #for display.')]);
    });

    test('"pool #" with no digits after it is left as plain text', () {
      final segments = parseRichMarkup('A pool #for cats.');
      expect(segments, [isA<RichMarkupTextSegment>().having((s) => s.text, 'text', 'A pool #for cats.')]);
    });
  });
}
