import '../repository/bunny_models.dart';

/// Splits a [BunnyStatsReport] entry's merged, site-prefixed `name` (e.g.
/// `"e621: wolf"`) back into the site and the bare name -- every section of
/// the report prefixes each entry this way so the same tag/label text on
/// both sites can't collide (see [BunnyStatsReport]'s own doc comment).
/// Returns `null` if `name` doesn't start with a known prefix at all.
(BunnySite, String)? splitSitePrefixedName(String name) {
  const e621Prefix = 'e621: ';
  const inkbunnyPrefix = 'inkbunny: ';
  if (name.startsWith(e621Prefix)) {
    return (BunnySite.e621, name.substring(e621Prefix.length));
  }
  if (name.startsWith(inkbunnyPrefix)) {
    return (BunnySite.inkbunny, name.substring(inkbunnyPrefix.length));
  }
  return null;
}
