import 'package:bunny_core_ffi/bunny_core_ffi.dart';

import 'bunny_models.dart';
import 'bunny_repository.dart';
import 'download_file_native.dart';

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
  lastUpdatedAt: m['lastUpdatedAt'] as String?,
);

BunnyGroup _groupFromMap(Map<String, Object?> m) => BunnyGroup(id: m['id'] as int, name: m['name'] as String, pinned: m['pinned'] as bool, createdAt: m['createdAt'] as String);

BunnySlideshow _slideshowFromMap(Map<String, Object?> m) => BunnySlideshow(
  id: m['id'] as int,
  label: m['label'] as String,
  defaultPostsPerSearch: m['defaultPostsPerSearch'] as int?,
  maxTotalPosts: m['maxTotalPosts'] as int?,
  createdAt: m['createdAt'] as String,
);

BunnySlideshowSearch _slideshowSearchFromMap(Map<String, Object?> m) =>
    BunnySlideshowSearch(slideshowId: m['slideshowId'] as int, searchId: m['searchId'] as int, overrideCount: m['overrideCount'] as int?, addedAt: m['addedAt'] as String);

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
  favoriteStars: m['favoriteStars'] as int,
);

BunnySlideshowPost _slideshowPostFromMap(Map<String, Object?> m) => BunnySlideshowPost(searchId: m['searchId'] as int, post: _postFromMap(m['post'] as Map<String, Object?>));

BunnyTagStat _tagStatFromMap(Map<String, Object?> m) => BunnyTagStat(name: m['name'] as String, count: m['count'] as int);

List<BunnyTagStat> _tagStatListFromMaps(Object? list) => (list as List).cast<Map<String, Object?>>().map(_tagStatFromMap).toList();

BunnyStatsReport _statsReportFromMap(Map<String, Object?> m) => BunnyStatsReport(
  computedAt: m['computedAt'] as String?,
  topFavoritedTags: _tagStatListFromMaps(m['topFavoritedTags']),
  topUsedTags: _tagStatListFromMaps(m['topUsedTags']),
  topPools: _tagStatListFromMaps(m['topPools']),
  topViewedSearches: _tagStatListFromMaps(m['topViewedSearches']),
);

BunnyPostTag _postTagFromMap(Map<String, Object?> m) => BunnyPostTag(name: m['name'] as String, category: m['category'] as String?);

BunnyPostFile _postFileFromMap(Map<String, Object?> m) => BunnyPostFile(
  fileUrl: m['fileUrl'] as String,
  sampleUrl: m['sampleUrl'] as String?,
  previewUrl: m['previewUrl'] as String?,
  fileExt: m['fileExt'] as String?,
  fileMd5: m['fileMd5'] as String?,
  width: m['width'] as int,
  height: m['height'] as int,
  mimetype: m['mimetype'] as String?,
);

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

BunnyTag _tagFromMap(Map<String, Object?> m) => BunnyTag(
  id: m['id'] as int,
  name: m['name'] as String?,
  postCount: m['postCount'] as int,
  category: BunnyTagCategory.values[m['category'] as int],
  relatedTags: m['relatedTags'] as String?,
  isLocked: m['isLocked'] as bool,
  createdAt: m['createdAt'] as String?,
  updatedAt: m['updatedAt'] as String?,
);

BunnyWikiPage _wikiPageFromMap(Map<String, Object?> m) => BunnyWikiPage(
  id: m['id'] as int,
  title: m['title'] as String?,
  body: m['body'] as String?,
  otherNames: (m['otherNames'] as List? ?? const []).cast<String>(),
  isLocked: m['isLocked'] as bool,
  createdAt: m['createdAt'] as String?,
  updatedAt: m['updatedAt'] as String?,
);

BunnyTagAlias _tagAliasFromMap(Map<String, Object?> m) =>
    BunnyTagAlias(id: m['id'] as int, antecedentName: m['antecedentName'] as String?, consequentName: m['consequentName'] as String?, status: m['status'] as String?, postCount: m['postCount'] as int);

BunnyTagImplication _tagImplicationFromMap(Map<String, Object?> m) =>
    BunnyTagImplication(id: m['id'] as int, antecedentName: m['antecedentName'] as String?, consequentName: m['consequentName'] as String?, status: m['status'] as String?);

BunnyQueueStats _queueStatsFromMap(Map<String, Object?> m) => BunnyQueueStats(
  actionsProcessed: m['actionsProcessed'] as int,
  actionsSucceeded: m['actionsSucceeded'] as int,
  actionsFailed: m['actionsFailed'] as int,
);

DownloadQueueRecord _downloadQueueRecordFromMap(Map<String, Object?> m) => DownloadQueueRecord(
  id: m['id'] as int,
  postId: m['postId'] as int,
  status: m['status'] as String,
  failureReason: m['failureReason'] as String?,
  createdAt: m['createdAt'] as String,
  poolId: m['poolId'] as int,
  poolName: m['poolName'] as String?,
  poolPage: m['poolPage'] as int,
);

BunnyBlacklistSyncStats _blacklistSyncStatsFromMap(Map<String, Object?> m) => BunnyBlacklistSyncStats(
  added: m['added'] as int,
  alreadyPresent: m['alreadyPresent'] as int,
  skippedInvalid: m['skippedInvalid'] as int,
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
  Future<void> mergeDuplicateSearch(int keeperId, int duplicateId) => _wrapped(() => _native.mergeDuplicateSearch(keeperId, duplicateId));

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
  Future<List<BunnyPost>> listSearchPosts(int searchId, {bool unseenOnly = false, int ratingMask = kRatingMaskAll, int mediaMask = kMediaMaskAll, int page = 1}) async {
    final items = await _wrapped(() => _native.listSearchPosts(searchId, unseenOnly, ratingMask, mediaMask, page));
    return items.map(_postFromMap).toList();
  }

  @override
  Future<List<BunnyTagStat>> tagAutocomplete(BunnySite site, String prefix, {int limit = 10}) async {
    final items = await _wrapped(() => _native.tagAutocomplete(site.toWireString(), prefix, limit));
    return items.map(_tagStatFromMap).toList();
  }

  @override
  Future<BunnyStatsReport> getStatsReport() async {
    final map = await _wrapped(() => _native.getStatsReport());
    return _statsReportFromMap(map);
  }

  @override
  Future<BunnyStatsReport> refreshStatsReport() async {
    final map = await _wrapped(() => _native.refreshStatsReport());
    return _statsReportFromMap(map);
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
  Future<List<BunnyPostFile>> getPostFiles(int postId) async {
    final items = await _wrapped(() => _native.getPostFiles(postId));
    return items.map(_postFileFromMap).toList();
  }

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
  Future<BunnyBlacklistSyncStats> syncE621Blacklist() async => _blacklistSyncStatsFromMap(await _wrapped(() => _native.syncE621Blacklist()));

  @override
  Future<int?> validateTagQuery(BunnySite site, String text) => _wrapped(() => _native.tagQueryValidate(text, site.toWireString()));

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
  Future<List<BunnyTag>> searchTags(String nameMatches, {int limit = 0}) async {
    final items = await _wrapped(() => _native.searchTags(nameMatches, limit: limit));
    return items.map(_tagFromMap).toList();
  }

  @override
  Future<BunnyWikiPage?> getWikiPage(String title) async {
    final map = await _wrapped(() => _native.getWikiPage(title));
    return map == null ? null : _wikiPageFromMap(map);
  }

  @override
  Future<List<BunnyTagAlias>> searchTagAliases(String nameMatches, {int limit = 0}) async {
    final items = await _wrapped(() => _native.searchTagAliases(nameMatches, limit: limit));
    return items.map(_tagAliasFromMap).toList();
  }

  @override
  Future<List<BunnyTagImplication>> searchTagImplications(String nameMatches, {int limit = 0}) async {
    final items = await _wrapped(() => _native.searchTagImplications(nameMatches, limit: limit));
    return items.map(_tagImplicationFromMap).toList();
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
  Future<List<BunnyTaskHistoryEntry>> getTaskHistory() async => const [];

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

  @override
  Future<int> downloadQueueAdd(int postId, {int poolId = 0, String? poolName, int poolPage = 0}) =>
      _wrapped(() => _native.downloadQueueAdd(postId, poolId: poolId, poolName: poolName, poolPage: poolPage));

  @override
  Future<void> downloadQueueSetStatus(int id, String status, {String? failureReason}) => _wrapped(() => _native.downloadQueueSetStatus(id, status, failureReason: failureReason));

  @override
  Future<List<DownloadQueueRecord>> downloadQueueList() async {
    final list = await _wrapped(() => _native.downloadQueueList());
    return list.map(_downloadQueueRecordFromMap).toList(growable: false);
  }

  @override
  Future<void> downloadQueueClearFinished() => _wrapped(() => _native.downloadQueueClearFinished());

  @override
  Future<DownloadFetchResult> downloadFile(String fileUrl, Map<String, String> extraHeaders, String destDir, String filename, String? expectedMd5, void Function(int received, int? total) onProgress) =>
      downloadFileViaNative(_native, fileUrl, extraHeaders, destDir, filename, expectedMd5, onProgress);

  @override
  Future<int> slideshowCreate(String label, {int? defaultPostsPerSearch, int? maxTotalPosts}) => _wrapped(() => _native.slideshowCreate(label, defaultPostsPerSearch, maxTotalPosts));

  @override
  Future<void> slideshowUpdate(int slideshowId, String label, {int? defaultPostsPerSearch, int? maxTotalPosts}) =>
      _wrapped(() => _native.slideshowUpdate(slideshowId, label, defaultPostsPerSearch, maxTotalPosts));

  @override
  Future<void> slideshowDelete(int slideshowId) => _wrapped(() => _native.slideshowDelete(slideshowId));

  @override
  Future<List<BunnySlideshow>> slideshowList() async {
    final items = await _wrapped(() => _native.slideshowList());
    return items.map(_slideshowFromMap).toList(growable: false);
  }

  @override
  Future<BunnySlideshow> slideshowGet(int slideshowId) async {
    final map = await _wrapped(() => _native.slideshowGet(slideshowId));
    return _slideshowFromMap(map);
  }

  @override
  Future<void> slideshowSearchAdd(int slideshowId, int searchId, {int? overrideCount}) => _wrapped(() => _native.slideshowSearchAdd(slideshowId, searchId, overrideCount));

  @override
  Future<void> slideshowSearchRemove(int slideshowId, int searchId) => _wrapped(() => _native.slideshowSearchRemove(slideshowId, searchId));

  @override
  Future<List<BunnySlideshowSearch>> slideshowSearchList(int slideshowId) async {
    final items = await _wrapped(() => _native.slideshowSearchList(slideshowId));
    return items.map(_slideshowSearchFromMap).toList(growable: false);
  }

  @override
  Future<List<BunnySlideshowPost>> slideshowPostsList(int slideshowId, {int? searchId}) async {
    final items = await _wrapped(() => _native.slideshowPostsList(slideshowId, searchId ?? 0));
    return items.map(_slideshowPostFromMap).toList(growable: false);
  }

  @override
  Future<void> slideshowRerollAll(int slideshowId) => _wrapped(() => _native.slideshowRerollAll(slideshowId));

  @override
  Future<void> slideshowRerollSearch(int slideshowId, int searchId) => _wrapped(() => _native.slideshowRerollSearch(slideshowId, searchId));

  @override
  Future<void> slideshowReplacePost(int slideshowId, int searchId, int deadPostId) => _wrapped(() => _native.slideshowReplacePost(slideshowId, searchId, deadPostId));
}
