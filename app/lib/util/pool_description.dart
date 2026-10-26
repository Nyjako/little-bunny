/// A segment of a pool description's text (M26) -- either plain text, or a
/// `pool #<id>` cross-reference that should render as a tappable inline
/// link instead of literal text (M44).
sealed class PoolDescriptionSegment {
  const PoolDescriptionSegment();
}

class PoolDescriptionTextSegment extends PoolDescriptionSegment {
  final String text;
  const PoolDescriptionTextSegment(this.text);
}

class PoolDescriptionReferenceSegment extends PoolDescriptionSegment {
  final int poolId;

  /// The exact substring matched ("pool #456") -- rendered as-is inline
  /// rather than reformatted, so the surrounding sentence still reads
  /// naturally.
  final String matchedText;
  const PoolDescriptionReferenceSegment(this.poolId, this.matchedText);
}

bool _isAsciiDigit(String char) {
  final code = char.codeUnitAt(0);
  return code >= 48 && code <= 57;
}

/// Splits [description] into plain-text and `pool #<id>` reference segments
/// (M44), using the exact same "pool #" + one-or-more-digits convention
/// `bunny_core`'s own `parse_pool_references` (`libs/core/src/sync.c`)
/// already extracts `BunnyPoolInfo.referencedPoolIds` with -- this just also
/// needs *where* each reference sits in the text, not only the list of ids,
/// so the description can render each one as an inline link in place rather
/// than as separate chips below it. A "pool #" not followed by a digit
/// isn't a real reference and is left as plain text, same as the C side.
List<PoolDescriptionSegment> parsePoolDescriptionSegments(String description) {
  const marker = 'pool #';
  final segments = <PoolDescriptionSegment>[];
  // Two separate cursors: segmentStart is where the next plain-text segment
  // should start from (only advances when a real reference is emitted), and
  // searchCursor is just where to resume scanning for the next "pool #" (always
  // advances past a false match, so it isn't matched again forever) -- a single
  // shared cursor would silently drop the leading text in front of a "pool #"
  // that turns out not to be followed by digits.
  var segmentStart = 0;
  var searchCursor = 0;

  while (true) {
    final markerIndex = description.indexOf(marker, searchCursor);
    if (markerIndex == -1) {
      break;
    }
    var digitsEnd = markerIndex + marker.length;
    while (digitsEnd < description.length && _isAsciiDigit(description[digitsEnd])) {
      digitsEnd++;
    }
    if (digitsEnd == markerIndex + marker.length) {
      searchCursor = markerIndex + marker.length;
      continue;
    }

    if (markerIndex > segmentStart) {
      segments.add(PoolDescriptionTextSegment(description.substring(segmentStart, markerIndex)));
    }
    final matchedText = description.substring(markerIndex, digitsEnd);
    final poolId = int.parse(description.substring(markerIndex + marker.length, digitsEnd));
    segments.add(PoolDescriptionReferenceSegment(poolId, matchedText));
    segmentStart = digitsEnd;
    searchCursor = digitsEnd;
  }

  if (segmentStart < description.length) {
    segments.add(PoolDescriptionTextSegment(description.substring(segmentStart)));
  }
  return segments;
}
