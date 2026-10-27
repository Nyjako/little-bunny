/// Below this many characters, the server rejects an autocomplete request
/// outright (M39) -- a shorter prefix matches far too many tags for its
/// index to narrow usefully, which is what hung the server on a single
/// keystroke. Checked client-side too, so a short prefix never fires the
/// request in the first place.
const int tagAutocompleteMinPrefixLength = 5;

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

/// True if any whitespace-separated token in [query], once its `-`/`~`/`(`
/// prefix is stripped, exactly equals [tag] -- used to decide whether
/// "Remove from current search" (M54) has anything to actually remove.
bool queryHasBareTag(String query, String tag) => query.split(' ').any((token) => splitTagPrefix(token).$2 == tag);

/// Removes every token from [query] whose bare form (prefix stripped)
/// equals [tag], regardless of which prefix (if any) it carried, and
/// collapses the result back down to single-spaced, trimmed text. Shared by
/// [addTagToQuery]/[excludeTagInQuery] (drop any existing form of the tag
/// before re-adding it in the requested form) and [removeTagFromQuery]
/// itself.
String _withoutTag(String query, String tag) => query.split(' ').where((token) => token.isNotEmpty && splitTagPrefix(token).$2 != tag).join(' ');

/// Adds [tag] to [query] as a plain (non-prefixed) token -- replacing any
/// existing occurrence under a different prefix (e.g. turns `-tag` into
/// `tag` rather than leaving a contradictory `tag -tag`) -- for M54's
/// "Add to current search" tag-menu action. Unlike [applyTagSuggestion],
/// this fully normalizes whitespace (collapses runs, trims ends) since
/// there's no cursor position to preserve here.
String addTagToQuery(String query, String tag) {
  final without = _withoutTag(query, tag);
  return without.isEmpty ? tag : '$without $tag';
}

/// Adds `-tag` to [query] -- "Exclude from current search" (M54), filtering
/// out posts with [tag] entirely. Same replace-not-duplicate behavior as
/// [addTagToQuery].
String excludeTagInQuery(String query, String tag) {
  final without = _withoutTag(query, tag);
  return without.isEmpty ? '-$tag' : '$without -$tag';
}

/// Removes [tag] from [query] in whatever form it's currently present --
/// "Remove from current search" (M54). May return an empty string if [tag]
/// was the query's only token; callers don't guard against that here (see
/// this function's own call sites for how an empty result is handled).
String removeTagFromQuery(String query, String tag) => _withoutTag(query, tag);

/// True for an exact `pool:<id>` sentinel query (M22/M28's convention for
/// browsing a pool) -- mirrors the identical exact-match check duplicated in
/// `TagBrowseScreen._poolId`/`PostGridScreen._poolId`. M54's current-search
/// tag actions are suppressed entirely for a pool browse: appending a bare
/// tag token to `pool:123` produces `pool:123 sometag`, which still starts
/// with `pool:` but no longer parses back out to a pool id via
/// `int.tryParse` -- silently breaking the pool header/ascending-sort logic
/// built on that exact-match assumption.
bool queryIsPoolSentinel(String query) => query.startsWith('pool:') && int.tryParse(query.substring(5)) != null;
