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
  totalCount: m['totalCount'] as int,
  autoFavorite: m['autoFavorite'] as bool,
  autoFavoriteStars: m['autoFavoriteStars'] as int,
  autoUpvote: m['autoUpvote'] as bool,
  pinned: m['pinned'] as bool,
  lastViewedAt: m['lastViewedAt'] as String?,
  usesDefaultInterval: m['usesDefaultInterval'] as bool,
  groupId: m['groupId'] as int,
);

BunnyGroup _groupFromMap(Map<String, Object?> m) => BunnyGroup(id: m['id'] as int, name: m['name'] as String, pinned: m['pinned'] as bool, createdAt: m['createdAt'] as String);

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
  sampleUrl: m['sampleUrl'] as String?,
  userVote: m['userVote'] as int,
);

BunnyTagStat _tagStatFromMap(Map<String, Object?> m) => BunnyTagStat(name: m['name'] as String, count: m['count'] as int);

BunnyPostTag _postTagFromMap(Map<String, Object?> m) => BunnyPostTag(name: m['name'] as String, category: m['category'] as String?);

BunnyPostRelationships _relationshipsFromMap(Map<String, Object?> m) => BunnyPostRelationships(
  hasParent: m['hasParent'] as bool,
  parentExternalId: m['parentExternalId'] as int?,
  hasActiveChildren: m['hasActiveChildren'] as bool,
  children: (m['children'] as List).cast<int>(),
);

BunnyPoolInfo _poolInfoFromMap(Map<String, Object?> m) => BunnyPoolInfo(
  id: m['id'] as int,
  name: m['name'] as String?,
  description: m['description'] as String?,
  postCount: m['postCount'] as int,
  referencedPoolIds: (m['referencedPoolIds'] as List? ?? const []).cast<int>(),
);

BunnyComment _commentFromMap(Map<String, Object?> m) => BunnyComment(id: m['id'] as int, creatorName: m['creatorName'] as String?, body: m['body'] as String?, createdAt: m['createdAt'] as String?);

BunnyDownload _downloadFromMap(Map<String, Object?> m) => BunnyDownload(
  id: m['id'] as int,
  postId: m['postId'] as int,
  filePath: m['filePath'] as String?,
  checksumMd5: m['checksumMd5'] as String?,
  checksumVerified: m['checksumVerified'] as bool,
  downloadedAt: m['downloadedAt'] as String?,
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

  /// Standalone mode has no server/other devices to share sync progress
  /// with, but [syncAllSearches] still runs as a loop someone might want to
  /// watch -- tracked here purely in Dart so [getSyncStatus] can drive the
  /// same generic progress UI as [HttpBunnyRepository] without special
  /// casing (M20).
  BunnySyncStatus _syncStatus = BunnySyncStatus.inactive;

  FfiBunnyRepository._(this._native);

  static Future<FfiBunnyRepository> open({
    required String dbPath,
    required String userAgent,
  }) async {
    final native = BunnyCoreNative();
    await _wrapped(() => native.open(dbPath, userAgent));
    return FfiBunnyRepository._(native);
  }

  @override
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
  Future<int> createSearch(
    BunnySite site,
    String label,
    String query, {
    int intervalHours = 24,
    bool autoFavorite = false,
    int autoFavoriteStars = 1,
    bool autoUpvote = false,
    bool usesDefaultInterval = false,
  }) => _wrapped(
    () => _native.createSearch(
      site.toWireString(),
      label,
      query,
      intervalHours,
      autoFavorite: autoFavorite,
      autoFavoriteStars: autoFavoriteStars,
      autoUpvote: autoUpvote,
      usesDefaultInterval: usesDefaultInterval,
    ),
  );

  @override
  Future<List<BunnySearch>> listSearches() async {
    final items = await _wrapped(() => _native.listSearches());
    return items.map(_searchFromMap).toList();
  }

  @override
  Future<void> deleteSearch(int searchId) => _wrapped(() => _native.deleteSearch(searchId));

  @override
  Future<void> setSearchPinned(int searchId, bool pinned) => _wrapped(() => _native.setSearchPinned(searchId, pinned));

  @override
  Future<void> touchSearchViewed(int searchId) => _wrapped(() => _native.touchSearchViewed(searchId));

  @override
  Future<void> setSearchGroup(int searchId, int groupId) => _wrapped(() => _native.setSearchGroup(searchId, groupId));

  @override
  Future<int> createGroup(String name, bool pinned) => _wrapped(() => _native.createGroup(name, pinned));

  @override
  Future<List<BunnyGroup>> listGroups() async {
    final items = await _wrapped(() => _native.listGroups());
    return items.map(_groupFromMap).toList();
  }

  @override
  Future<void> updateGroup(int groupId, String name, bool pinned) => _wrapped(() => _native.updateGroup(groupId, name, pinned));

  @override
  Future<void> deleteGroup(int groupId) => _wrapped(() => _native.deleteGroup(groupId));

  @override
  Future<void> updateSearch(
    int searchId,
    String label,
    String query, {
    int intervalHours = 24,
    bool autoFavorite = false,
    int autoFavoriteStars = 1,
    bool autoUpvote = false,
    bool usesDefaultInterval = false,
  }) => _wrapped(
    () => _native.updateSearch(
      searchId,
      label,
      query,
      intervalHours,
      autoFavorite: autoFavorite,
      autoFavoriteStars: autoFavoriteStars,
      autoUpvote: autoUpvote,
      usesDefaultInterval: usesDefaultInterval,
    ),
  );

  @override
  Future<int> getDefaultSyncIntervalHours() => _wrapped(() => _native.getDefaultSyncIntervalHours());

  @override
  Future<void> setDefaultSyncIntervalHours(int hours) => _wrapped(() => _native.setDefaultSyncIntervalHours(hours));

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
  Future<List<BunnyTagStat>> topFavoritedTags(BunnySite site, {int limit = 20}) async {
    final items = await _wrapped(() => _native.topFavoritedTags(site.toWireString(), limit));
    return items.map(_tagStatFromMap).toList();
  }

  @override
  Future<List<BunnyTagStat>> topUsedTags(BunnySite site, {int limit = 20}) async {
    final items = await _wrapped(() => _native.topUsedTags(site.toWireString(), limit));
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
  Future<BunnyPostRelationships> getPostRelationships(int postId) async {
    final map = await _wrapped(() => _native.getPostRelationships(postId));
    return _relationshipsFromMap(map);
  }

  @override
  Future<List<int>> getPostPoolIds(int postId) => _wrapped(() => _native.getPostPoolIds(postId));

  @override
  Future<int> fetchPost(BunnySite site, int externalId) => _wrapped(() => _native.fetchAndCachePost(site.toWireString(), externalId));

  @override
  Future<List<String>> getBlacklist(BunnySite site) => _wrapped(() => _native.blacklistList(site.toWireString()));

  @override
  Future<void> addBlacklistTag(BunnySite site, String tag) => _wrapped(() => _native.blacklistAdd(site.toWireString(), tag));

  @override
  Future<void> removeBlacklistTag(BunnySite site, String tag) => _wrapped(() => _native.blacklistRemove(site.toWireString(), tag));

  @override
  Future<BunnyPoolInfo> fetchPool(int poolId) async {
    final map = await _wrapped(() => _native.fetchPool(poolId));
    return _poolInfoFromMap(map);
  }

  @override
  Future<BunnyPost> getPost(int postId) async {
    final map = await _wrapped(() => _native.getPostById(postId));
    return _postFromMap(map);
  }

  @override
  Future<List<BunnyPost>> previewSearch(BunnySite site, String query, {int page = 1}) async {
    final items = await _wrapped(() => _native.previewSearch(site.toWireString(), query, page: page));
    return items.map(_postFromMap).toList();
  }

  @override
  Future<List<BunnyPost>> myInkbunnyFavorites({int page = 1}) async {
    final items = await _wrapped(() => _native.listMyInkbunnyFavorites(page: page));
    return items.map(_postFromMap).toList();
  }

  @override
  Future<List<BunnyComment>> getPostComments(int postId) async {
    final items = await _wrapped(() => _native.listComments(postId));
    return items.map(_commentFromMap).toList();
  }

  @override
  Future<int> recordDownload(int postId, String filePath, {String? checksumMd5, bool verified = false}) => _wrapped(() => _native.recordDownload(postId, filePath, checksumMd5, verified));

  @override
  Future<List<BunnyDownload>> listDownloadsForPost(int postId) async {
    final items = await _wrapped(() => _native.listDownloadsForPost(postId));
    return items.map(_downloadFromMap).toList();
  }

  @override
  Future<void> syncDueSearches() => _wrapped(() => _native.syncDueSearches());

  @override
  Future<void> syncSearch(int searchId) => _wrapped(() => _native.syncSearch(searchId));

  /// Unlike [HttpBunnyRepository] (which enqueues one job server-side and
  /// returns immediately), this runs the loop itself and only resolves once
  /// every search has been synced -- standalone mode already runs every
  /// native call on its own isolate (see [BunnyCoreNative]'s doc comment),
  /// so there's no UI-thread-blocking or worker-thread-starvation concern
  /// here to avoid by deferring the work. [_syncStatus] is still updated
  /// throughout so [getSyncStatus] can drive the same progress UI.
  @override
  Future<void> syncAllSearches() async {
    final searches = await listSearches();
    _syncStatus = BunnySyncStatus(active: true, source: 'manual', position: 0, total: searches.length);
    try {
      for (var i = 0; i < searches.length; i++) {
        _syncStatus = BunnySyncStatus(active: true, source: 'manual', searchLabel: searches[i].label, position: i + 1, total: searches.length);
        await syncSearch(searches[i].id);
      }
    } finally {
      _syncStatus = BunnySyncStatus.inactive;
    }
  }

  @override
  Future<BunnySyncStatus> getSyncStatus() async => _syncStatus;

  /// Standalone mode has no task_queue (M24) -- every call here runs
  /// synchronously in-process (see [syncAllSearches] above), so there's
  /// never anything queued or running in the background to report.
  @override
  Future<List<BunnyTask>> getTasks() async => const [];

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
