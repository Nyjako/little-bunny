import '../repository/bunny_models.dart';

/// Extra HTTP headers for fetching a post's image/thumbnail. Inkbunny's CDN
/// (metapix.net) rejects bare requests with no `User-Agent`/`Referer` with a
/// 403 -- `CachedNetworkImage` sends no headers at all by default. e621's CDN
/// has no such requirement, so this only applies to Inkbunny.
Map<String, String>? imageHeadersFor(BunnySite site) {
  if (site != BunnySite.inkbunny) {
    return null;
  }
  return const {'User-Agent': 'LittleBunny/1.0 (+https://github.com/Nyjako/little-bunny)', 'Referer': 'https://inkbunny.net/'};
}
