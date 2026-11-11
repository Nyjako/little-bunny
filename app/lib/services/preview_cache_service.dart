import 'dart:async';
import 'dart:collection';

import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';

class _CachedPreview {
  final List<BunnyPost> posts;
  final DateTime fetchedAt;

  const _CachedPreview(this.posts, this.fetchedAt);
}

/// Short-lived, bounded cache for [BunnyRepository.previewSearch] results --
/// `previewSearch` always makes a live request (it has no result-level
/// cache of its own; only the individual posts it returns get cached), so
/// without this, warming a preview in the background ([prefetch]) and then
/// opening it for real (a [TagBrowseScreen] constructed with this cache)
/// would just mean two live requests instead of one.
///
/// Scoped to a handful of recently-shown recommendations, not a general
/// cache: short TTL, small capacity, LRU eviction. A miss or an expired
/// entry is simply re-fetched -- this is a speed optimization, never a
/// correctness dependency.
class PreviewCacheService {
  PreviewCacheService({this.ttl = const Duration(minutes: 5), this.maxEntries = 20});

  final Duration ttl;
  final int maxEntries;

  /// Insertion order doubles as recency for LRU eviction -- every access
  /// (hit or fresh insert) re-inserts its key, so the map's first entry is
  /// always the least recently used one.
  final LinkedHashMap<String, _CachedPreview> _cache = LinkedHashMap();

  String _key(BunnySite site, String query, int page) => '${site.name}|$query|$page';

  bool _isFresh(_CachedPreview cached) => DateTime.now().difference(cached.fetchedAt) < ttl;

  /// Returns the cached page if present and not yet expired; otherwise
  /// fetches via [repository.previewSearch], caches, and returns that.
  Future<List<BunnyPost>> getOrFetch(BunnyRepository repository, BunnySite site, String query, {int page = 1}) async {
    final key = _key(site, query, page);
    final cached = _cache.remove(key);
    if (cached != null && _isFresh(cached)) {
      _cache[key] = cached; // re-insert to mark as most recently used
      return cached.posts;
    }

    final posts = await repository.previewSearch(site, query, page: page);
    _store(key, posts);
    return posts;
  }

  void _store(String key, List<BunnyPost> posts) {
    _cache.remove(key); // drop any stale entry first so the re-insert below lands at the end
    _cache[key] = _CachedPreview(posts, DateTime.now());
    while (_cache.length > maxEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// Fire-and-forget warm-up for page 1 of [site]/[query] -- best-effort:
  /// a failure here just means the later real fetch (e.g. opening
  /// [TagBrowseScreen]) tries again on its own, so errors are swallowed
  /// rather than surfaced anywhere.
  void prefetch(BunnyRepository repository, BunnySite site, String query) {
    unawaited(getOrFetch(repository, site, query, page: 1).catchError((_) => <BunnyPost>[]));
  }
}
