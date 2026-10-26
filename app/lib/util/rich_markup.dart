import '../repository/bunny_models.dart';

/// A segment of a post/pool/wiki description's text (M50/M53) -- plain
/// text, an auto-linked URL, or one of e621.wiki's own cross-reference
/// conventions: `{{author}}` (an author reference), `[[title]]` (a link
/// to another wiki page/tag), and `pool #<id>`/`thumb #<id>` (M44/M53's
/// own pool/post reference conventions, folded into this one shared parser
/// so every description -- post, pool, or wiki -- gets the same rich
/// rendering). A bare URL that happens to point at a post or pool this app
/// already knows how to open (an e621/Inkbunny permalink) becomes a
/// [RichMarkupPostSegment]/[RichMarkupPoolSegment] instead of a plain
/// [RichMarkupUrlSegment], so the caller can open it in-app rather than
/// launching an external browser.
sealed class RichMarkupSegment {
  const RichMarkupSegment();
}

class RichMarkupTextSegment extends RichMarkupSegment {
  final String text;
  const RichMarkupTextSegment(this.text);
}

class RichMarkupUrlSegment extends RichMarkupSegment {
  final String url;
  const RichMarkupUrlSegment(this.url);
}

class RichMarkupAuthorSegment extends RichMarkupSegment {
  final String authorName;

  /// The exact substring matched ("{{someartist}}"), rendered as-is inline
  /// rather than reformatted, same reasoning as
  /// [RichMarkupWikiSegment.matchedText].
  final String matchedText;
  const RichMarkupAuthorSegment(this.authorName, this.matchedText);
}

class RichMarkupWikiSegment extends RichMarkupSegment {
  final String title;
  final String matchedText;
  const RichMarkupWikiSegment(this.title, this.matchedText);
}

/// A reference to a specific post -- either `thumb #<id>` (e621.wiki's own
/// wiki-body convention, always [BunnySite.e621]) or a bare URL recognized
/// as an e621/Inkbunny post permalink (site determined by which domain
/// matched).
class RichMarkupPostSegment extends RichMarkupSegment {
  final BunnySite site;
  final int postId;
  final String matchedText;
  const RichMarkupPostSegment(this.site, this.postId, this.matchedText);
}

/// A reference to a pool -- either `pool #<id>` (M44's own convention) or a
/// bare URL recognized as an e621 pool permalink. Always e621: pool
/// metadata/descriptions in this app only ever come from e621's pool
/// endpoint (see [BunnyPoolInfo]), so a pool reference is never meaningfully
/// Inkbunny's.
class RichMarkupPoolSegment extends RichMarkupSegment {
  final int poolId;
  final String matchedText;
  const RichMarkupPoolSegment(this.poolId, this.matchedText);
}

/// `{{author}}`, `[[title]]`, `thumb #<id>`, `pool #<id>`, or a bare
/// `http(s)://` URL -- whichever starts earliest wins at each position,
/// same single-pass left-to-right scan this app's own pool-description
/// parser (M44) originally used for its one pattern, generalized here to
/// cover all of them in one shared parser. Trailing sentence punctuation
/// (`.,;:!?)]}`) immediately after a URL match is excluded from the link --
/// "see https://example.com." should link just the URL, not swallow the
/// period into it.
final RegExp _markupPattern = RegExp(r'(\{\{[^{}]*\}\})|(\[\[[^\[\]]*\]\])|(thumb #\d+)|(pool #\d+)|(https?://\S+)');

bool _isTrailingPunctuation(String char) => '.,;:!?)]}'.contains(char);

/// e621's current post permalink (`/posts/<id>`) and its older form
/// (`/post/show/<id>`, which still resolves) -- `e926.net` is e621's own
/// safe-mode mirror of the same site/database.
final RegExp _e621PostUrl = RegExp(r'^https?://(?:www\.)?(?:e621|e926)\.net/posts?(?:/show)?/(\d+)', caseSensitive: false);
final RegExp _e621PoolUrl = RegExp(r'^https?://(?:www\.)?(?:e621|e926)\.net/pools/(\d+)', caseSensitive: false);
final RegExp _inkbunnySubmissionUrl = RegExp(r'^https?://(?:www\.)?inkbunny\.net/s/(\d+)', caseSensitive: false);

/// Recognizes [url] as an e621/Inkbunny post or pool permalink, producing
/// the matching typed segment instead of a plain external-link segment --
/// falls back to [RichMarkupUrlSegment] for anything else (the vast
/// majority of links: ordinary off-site sources, art references, etc.).
RichMarkupSegment _urlSegment(String url) {
  final e621Post = _e621PostUrl.firstMatch(url);
  if (e621Post != null) {
    return RichMarkupPostSegment(BunnySite.e621, int.parse(e621Post.group(1)!), url);
  }
  final inkbunnyPost = _inkbunnySubmissionUrl.firstMatch(url);
  if (inkbunnyPost != null) {
    return RichMarkupPostSegment(BunnySite.inkbunny, int.parse(inkbunnyPost.group(1)!), url);
  }
  final e621Pool = _e621PoolUrl.firstMatch(url);
  if (e621Pool != null) {
    return RichMarkupPoolSegment(int.parse(e621Pool.group(1)!), url);
  }
  return RichMarkupUrlSegment(url);
}

List<RichMarkupSegment> parseRichMarkup(String text) {
  final segments = <RichMarkupSegment>[];
  var cursor = 0;

  for (final match in _markupPattern.allMatches(text)) {
    if (match.start > cursor) {
      segments.add(RichMarkupTextSegment(text.substring(cursor, match.start)));
    }

    final authorMatch = match.group(1);
    final wikiMatch = match.group(2);
    final thumbMatch = match.group(3);
    final poolMatch = match.group(4);
    final urlMatch = match.group(5);

    if (authorMatch != null) {
      segments.add(RichMarkupAuthorSegment(authorMatch.substring(2, authorMatch.length - 2), authorMatch));
      cursor = match.end;
    } else if (wikiMatch != null) {
      segments.add(RichMarkupWikiSegment(wikiMatch.substring(2, wikiMatch.length - 2), wikiMatch));
      cursor = match.end;
    } else if (thumbMatch != null) {
      segments.add(RichMarkupPostSegment(BunnySite.e621, int.parse(thumbMatch.substring('thumb #'.length)), thumbMatch));
      cursor = match.end;
    } else if (poolMatch != null) {
      segments.add(RichMarkupPoolSegment(int.parse(poolMatch.substring('pool #'.length)), poolMatch));
      cursor = match.end;
    } else if (urlMatch != null) {
      var end = match.end;
      while (end > match.start && _isTrailingPunctuation(text[end - 1])) {
        end--;
      }
      segments.add(_urlSegment(text.substring(match.start, end)));
      cursor = end;
    }
  }

  if (cursor < text.length) {
    segments.add(RichMarkupTextSegment(text.substring(cursor)));
  }
  return segments;
}
