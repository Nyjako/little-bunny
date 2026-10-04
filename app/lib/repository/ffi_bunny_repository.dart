import 'package:bunny_core_ffi/bunny_core_ffi.dart';

import 'bunny_models.dart';
import 'bunny_repository.dart';

BunnyAccount _accountFromMap(Map<String, Object?> m) => BunnyAccount(
  id: m['id'] as int,
  site: BunnySite.fromWireString(m['site'] as String),
  username: m['username'] as String,
  createdAt: m['createdAt'] as String,
);

BunnySearch _searchFromMap(Map<String, Object?> m) => BunnySearch(
  id: m['id'] as int,
  site: BunnySite.fromWireString(m['site'] as String),
  label: m['label'] as String,
  query: m['query'] as String,
  intervalHours: m['intervalHours'] as int,
  createdAt: m['createdAt'] as String,
  lastRunAt: m['lastRunAt'] as String?,
  unseenCount: m['unseenCount'] as int,
);

BunnyPost _postFromMap(Map<String, Object?> m) => BunnyPost(
  id: m['id'] as int,
  site: BunnySite.fromWireString(m['site'] as String),
  externalId: m['externalId'] as int,
  artist: m['artist'] as String?,
  title: m['title'] as String?,
  description: m['description'] as String?,
  rating: m['rating'] as String?,
  score: m['score'] as int,
  scoreUp: m['scoreUp'] as int,
  scoreDown: m['scoreDown'] as int,
  favCount: m['favCount'] as int,
  commentCount: m['commentCount'] as int,
  fileUrl: m['fileUrl'] as String?,
  fileExt: m['fileExt'] as String?,
  fileMd5: m['fileMd5'] as String?,
  previewUrl: m['previewUrl'] as String?,
  width: m['width'] as int,
  height: m['height'] as int,
  createdAtSite: m['createdAtSite'] as String?,
  cachedAt: m['cachedAt'] as String,
  isSeen: m['isSeen'] as bool,
  isFavorited: m['isFavorited'] as bool,
);

BunnyTagStat _tagStatFromMap(Map<String, Object?> m) => BunnyTagStat(name: m['name'] as String, count: m['count'] as int);

BunnyPostTag _postTagFromMap(Map<String, Object?> m) => BunnyPostTag(name: m['name'] as String, category: m['category'] as String?);

BunnySyncStats _syncStatsFromMap(Map<String, Object?> m) => BunnySyncStats(
  searchesChecked: m['searchesChecked'] as int,
  searchesSynced: m['searchesSynced'] as int,
  postsUpserted: m['postsUpserted'] as int,
);

BunnyQueueStats _queueStatsFromMap(Map<String, Object?> m) => BunnyQueueStats(
  actionsProcessed: m['actionsProcessed'] as int,
  actionsSucceeded: m['actionsSucceeded'] as int,
  actionsFailed: m['actionsFailed'] as int,
);

Future<T> _wrapped<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on BunnyCoreNativeException catch (e) {
    throw BunnyRepositoryException(e.message);
  }
}

/// [BunnyRepository] for standalone mode: FFI into `bunny_core` via
/// `bunny_core_ffi`'s dedicated background isolate (see
/// `bunny_core_ffi/lib/src/bunny_core_isolate.dart`). Call [open] to create
/// an instance -- it owns the native `bunny_core_t` handle for its lifetime,
/// so callers must [close] it when done.
class FfiBunnyRepository implements BunnyRepository {
  final BunnyCoreNative _native;

  FfiBunnyRepository._(this._native);

  static Future<FfiBunnyRepository> open({
    required String dbPath,
    required String userAgent,
  }) async {
    final native = BunnyCoreNative();
    await _wrapped(() => native.open(dbPath, userAgent));
    return FfiBunnyRepository._(native);
  }

  Future<void> close() => _native.close();

  @override
  Future<void> verifyAccount(BunnySite site, String username, String secret) => _wrapped(() => _native.verifyAccount(site.toWireString(), username, secret));

  @override
  Future<void> setAccount(BunnySite site, String username, String secret) => _wrapped(() => _native.setAccount(site.toWireString(), username, secret));

  @override
  Future<BunnyAccount?> getAccount(BunnySite site) async {
    final map = await _wrapped(() => _native.getAccount(site.toWireString()));
    return map == null ? null : _accountFromMap(map);
  }

  @override
  Future<void> deleteAccount(BunnySite site) => _wrapped(() => _native.deleteAccount(site.toWireString()));

  @override
  Future<int> createSearch(BunnySite site, String label, String query, {int intervalHours = 24}) => _wrapped(() => _native.createSearch(site.toWireString(), label, query, intervalHours));

  @override
  Future<List<BunnySearch>> listSearches() async {
    final items = await _wrapped(() => _native.listSearches());
    return items.map(_searchFromMap).toList();
  }

  @override
  Future<void> deleteSearch(int searchId) => _wrapped(() => _native.deleteSearch(searchId));

  @override
  Future<List<BunnyPost>> listSearchPosts(int searchId, {bool unseenOnly = false}) async {
    final items = await _wrapped(() => _native.listSearchPosts(searchId, unseenOnly));
    return items.map(_postFromMap).toList();
  }

  @override
  Future<List<BunnyTagStat>> tagAutocomplete(BunnySite site, String prefix, {int limit = 10}) async {
    final items = await _wrapped(() => _native.tagAutocomplete(site.toWireString(), prefix, limit));
    return items.map(_tagStatFromMap).toList();
  }

  @override
  Future<void> markPostSeen(int postId) => _wrapped(() => _native.markPostSeen(postId));

  @override
  Future<void> markAllSeen(int searchId) => _wrapped(() => _native.markAllSeen(searchId));

  @override
  Future<List<BunnyPostTag>> getPostTagsByCategory(int postId) async {
    final items = await _wrapped(() => _native.getPostTagsByCategory(postId));
    return items.map(_postTagFromMap).toList();
  }

  @override
  Future<List<String>> getPostSources(int postId) => _wrapped(() => _native.getPostSources(postId));

  @override
  Future<BunnySyncStats> syncDueSearches() async {
    final map = await _wrapped(() => _native.syncDueSearches());
    return _syncStatsFromMap(map);
  }

  @override
  Future<void> queueFavoriteAdd(int postId, {int? stars}) => _wrapped(() => _native.queueFavoriteAdd(postId, stars ?? -1));

  @override
  Future<void> queueFavoriteRemove(int postId) => _wrapped(() => _native.queueFavoriteRemove(postId));

  @override
  Future<void> queueVote(int postId, int score, {bool noUnvote = false}) => _wrapped(() => _native.queueVote(postId, score, noUnvote));

  @override
  Future<void> queueComment(int postId, String body, {bool anonymous = false}) => _wrapped(() => _native.queueComment(postId, body, anonymous));

  @override
  Future<BunnyQueueStats> processQueue() async {
    final map = await _wrapped(() => _native.processQueue());
    return _queueStatsFromMap(map);
  }
}
