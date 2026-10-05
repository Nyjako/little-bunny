/// Finds the start/end offsets (in [text]) of the whitespace-delimited token
/// that contains [cursorOffset] -- unlike splitting on the last space in the
/// whole string (which always picks the trailing word), this works correctly
/// when the cursor sits in the middle of a longer query, e.g. editing an
/// earlier tag in `cat -dog| standing` (`|` = cursor).
(int start, int end) tagTokenRangeAt(String text, int cursorOffset) {
  final clamped = cursorOffset.clamp(0, text.length);
  var start = clamped;
  while (start > 0 && text[start - 1] != ' ') {
    start--;
  }
  var end = clamped;
  while (end < text.length && text[end] != ' ') {
    end++;
  }
  return (start, end);
}

/// Splits [token] into its leading e621 search-syntax prefix (any run of
/// `-`, `~`, `(` -- negation, "or", and group-open) and the bare tag text
/// autocomplete should actually be queried against. No parsing of balanced
/// parenthesized groups beyond this -- `(` is just another prefix character
/// to strip and later reattach.
(String prefix, String tag) splitTagPrefix(String token) {
  var i = 0;
  while (i < token.length && (token[i] == '-' || token[i] == '~' || token[i] == '(')) {
    i++;
  }
  return (token.substring(0, i), token.substring(i));
}

/// e621 wildcards (e.g. `african_*`) have nothing sensible to prefix-complete
/// against a partial pattern, so autocomplete should be skipped entirely
/// rather than querying the fragment before or after the `*`.
bool tagHasWildcard(String tag) => tag.contains('*');

/// Replaces the tag token containing [cursorOffset] in [text] with its own
/// prefix followed by [suggestion] and a trailing space, returning the new
/// full text and the cursor offset just past the inserted space.
(String text, int cursorOffset) applyTagSuggestion(String text, int cursorOffset, String suggestion) {
  final (start, end) = tagTokenRangeAt(text, cursorOffset);
  final (prefix, _) = splitTagPrefix(text.substring(start, end));
  final replacement = '$prefix$suggestion ';
  final newText = text.replaceRange(start, end, replacement);
  return (newText, start + replacement.length);
}
