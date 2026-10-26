/// A segment of a post/pool/wiki description's text (M50/M53) -- plain
/// text, an auto-linked URL, or one of e621.wiki's own cross-reference
/// conventions: `{{author}}` (an author reference) and `[[title]]` (a link
/// to another wiki page/tag). Shared between M50 (post/pool descriptions)
/// and M53 (wiki page bodies, which also use `thumb #<id>` for an inline
/// post thumbnail -- not meaningful outside a wiki body, but recognized
/// unconditionally here since the markup itself doesn't depend on context;
/// the widget that renders these simply leaves thumbnail segments inert
/// when it has nothing to do with them.
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
  /// [PoolDescriptionReferenceSegment.matchedText] (M44).
  final String matchedText;
  const RichMarkupAuthorSegment(this.authorName, this.matchedText);
}

class RichMarkupWikiSegment extends RichMarkupSegment {
  final String title;
  final String matchedText;
  const RichMarkupWikiSegment(this.title, this.matchedText);
}

class RichMarkupThumbSegment extends RichMarkupSegment {
  final int postId;
  final String matchedText;
  const RichMarkupThumbSegment(this.postId, this.matchedText);
}

/// `{{author}}`, `[[title]]`, `thumb #<id>`, or a bare `http(s)://` URL --
/// whichever starts earliest wins at each position, same single-pass
/// left-to-right scan this app's own pool-description parser (M44) already
/// uses for its one pattern, generalized to four. Trailing sentence
/// punctuation (`.,;:!?)]}`) immediately after a URL match is excluded from
/// the link -- "see https://example.com." should link just the URL, not
/// swallow the period into it.
final RegExp _markupPattern = RegExp(r'(\{\{[^{}]*\}\})|(\[\[[^\[\]]*\]\])|(thumb #\d+)|(https?://\S+)');

bool _isTrailingPunctuation(String char) => '.,;:!?)]}'.contains(char);

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
    final urlMatch = match.group(4);

    if (authorMatch != null) {
      segments.add(RichMarkupAuthorSegment(authorMatch.substring(2, authorMatch.length - 2), authorMatch));
      cursor = match.end;
    } else if (wikiMatch != null) {
      segments.add(RichMarkupWikiSegment(wikiMatch.substring(2, wikiMatch.length - 2), wikiMatch));
      cursor = match.end;
    } else if (thumbMatch != null) {
      segments.add(RichMarkupThumbSegment(int.parse(thumbMatch.substring('thumb #'.length)), thumbMatch));
      cursor = match.end;
    } else if (urlMatch != null) {
      var end = match.end;
      while (end > match.start && _isTrailingPunctuation(text[end - 1])) {
        end--;
      }
      segments.add(RichMarkupUrlSegment(text.substring(match.start, end)));
      cursor = end;
    }
  }

  if (cursor < text.length) {
    segments.add(RichMarkupTextSegment(text.substring(cursor)));
  }
  return segments;
}
