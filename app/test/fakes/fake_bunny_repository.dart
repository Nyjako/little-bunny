import 'dart:async';

import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/repository/bunny_repository.dart';

/// In-memory fake for widget tests that exercise account login/verify/list/
/// remove and search/post browsing -- fakes the dependency, not the business
/// logic, same philosophy as every C library's own tests. Queue methods are
/// unimplemented since nothing under test (through M8) calls them -- that's
/// M9's scope. [syncDueSearches] is a no-op returning zeroed stats (M8.3's
/// [PostGridScreen] calls it as a manual "refresh" action, but nothing under
/// test needs it to actually add posts -- tests seed `postsBySearchId`
/// directly instead).
class FakeBunnyRepository implements BunnyRepository {
  final Map<BunnySite, BunnyAccount> accounts = {};
  final List<BunnySearch> searches = [];
  final Map<int, List<BunnyPost>> postsBySearchId = {};
  final List<BunnyTagStat> tagStats = [];
  final Map<BunnySite, List<BunnyTagStat>> topFavoritedTagsBySite = {};
  final Map<int, List<BunnyPostTag>> tagsByPostId = {};
  final Map<int, List<String>> sourcesByPostId = {};
  final Map<int, BunnyPostRelationships> relationshipsByPostId = {};
  final Map<int, List<int>> poolIdsByPostId = {};

  /// Per-site tag blacklist (M13.3), as a set so add/remove stay idempotent
  /// the same way the real `bunny_db_blacklist_*` functions are.
  final Map<BunnySite, Set<String>> blacklistBySite = {};
  final Map<int, List<BunnyComment>> commentsByPostId = {};
  final Map<int, List<BunnyDownload>> downloadsByPostId = {};
  int _nextDownloadId = 1;

  /// Each entry is the `(postId, filePath, checksumMd5, verified)` passed to
  /// [recordDownload].
  final List<(int, String, String?, bool)> recordDownloadCalls = [];

  /// Keyed by `'${site.toWireString()}:$externalId'` -- the post id
  /// [fetchPost] returns for that (site, externalId) pair.
  final Map<String, int> fetchPostResults = {};
  final Map<int, BunnyPoolInfo> poolInfoById = {};

  /// Extra posts [getPost] can resolve by id, for ones that aren't already
  /// sitting in [postsBySearchId] (e.g. a parent/child/pool-mate post that
  /// was only ever fetched standalone via [fetchPost], never synced into a
  /// saved search's results).
  final Map<int, BunnyPost> postsById = {};

  /// Keyed by `'${site.toWireString()}:$query:$page'` -- the posts
  /// [previewSearch] returns for that (site, query, page) triple (M9.6.2
  /// added `page` to support infinite scroll); an unregistered triple
  /// returns an empty list (a search genuinely matching nothing, or running
  /// past the last page, is a normal, non-error outcome, same convention as
  /// every other list-returning fake here).
  final Map<String, List<BunnyPost>> previewSearchResults = {};

  /// Each entry is the `(site, query, page)` passed to [previewSearch].
  final List<(BunnySite, String, int)> previewSearchCalls = [];

  /// Keyed by `page` -- the posts [myInkbunnyFavorites] returns for that page
  /// (M10.3); an unregistered page returns an empty list, same convention as
  /// [previewSearchResults] above.
  final Map<int, List<BunnyPost>> myInkbunnyFavoritesResults = {};

  /// Each entry is the `page` passed to [myInkbunnyFavorites].
  final List<int> myInkbunnyFavoritesCalls = [];
  int _nextSearchId = 1;
  int syncCallCount = 0;

  /// Set a message here to make [verifyAccount] throw for that site instead
  /// of succeeding.
  final Map<BunnySite, String> verifyFailures = {};

  @override
  Future<void> verifyAccount(BunnySite site, String username, String secret) async {
    final failure = verifyFailures[site];
    if (failure != null) {
      throw BunnyRepositoryException(failure);
    }
  }

  @override
  Future<void> setAccount(BunnySite site, String username, String secret) async {
    accounts[site] = BunnyAccount(id: accounts.length + 1, site: site, username: username, createdAt: '2026-01-01T00:00:00Z');
  }

  @override
  Future<BunnyAccount?> getAccount(BunnySite site) async => accounts[site];

  @override
  Future<void> deleteAccount(BunnySite site) async => accounts.remove(site);

  @override
  Future<int> createSearch(BunnySite site, String label, String query, {int intervalHours = 24, bool autoFavorite = false, int autoFavoriteStars = 1, bool autoUpvote = false}) async {
    final id = _nextSearchId++;
    searches.add(
      BunnySearch(
        id: id,
        site: site,
        label: label,
        query: query,
        intervalHours: intervalHours,
        createdAt: '2026-01-01T00:00:00Z',
        autoFavorite: autoFavorite,
        autoFavoriteStars: autoFavoriteStars,
        autoUpvote: autoUpvote,
      ),
    );
    return id;
  }

  @override
  Future<List<BunnySearch>> listSearches() async => searches
      .map(
        (search) => BunnySearch(
          id: search.id,
          site: search.site,
          label: search.label,
          query: search.query,
          intervalHours: search.intervalHours,
          createdAt: search.createdAt,
          lastRunAt: search.lastRunAt,
          unseenCount: (postsBySearchId[search.id] ?? const []).where((post) => !post.isSeen).length,
          totalCount: (postsBySearchId[search.id] ?? const []).length,
          autoFavorite: search.autoFavorite,
          autoFavoriteStars: search.autoFavoriteStars,
          autoUpvote: search.autoUpvote,
          pinned: search.pinned,
        ),
      )
      .toList();

  @override
  Future<void> deleteSearch(int searchId) async {
    searches.removeWhere((search) => search.id == searchId);
    postsBySearchId.remove(searchId);
  }

  @override
  Future<void> setSearchPinned(int searchId, bool pinned) async {
    final index = searches.indexWhere((search) => search.id == searchId);
    if (index == -1) {
      return;
    }
    final search = searches[index];
    searches[index] = BunnySearch(
      id: search.id,
      site: search.site,
      label: search.label,
      query: search.query,
      intervalHours: search.intervalHours,
      createdAt: search.createdAt,
      lastRunAt: search.lastRunAt,
      unseenCount: search.unseenCount,
      totalCount: search.totalCount,
      autoFavorite: search.autoFavorite,
      autoFavoriteStars: search.autoFavoriteStars,
      autoUpvote: search.autoUpvote,
      pinned: pinned,
    );
  }

  @override
  Future<void> updateSearch(int searchId, String label, String query, {int intervalHours = 24, bool autoFavorite = false, int autoFavoriteStars = 1, bool autoUpvote = false}) async {
    final index = searches.indexWhere((search) => search.id == searchId);
    if (index == -1) {
      return;
    }
    final search = searches[index];
    searches[index] = BunnySearch(
      id: search.id,
      site: search.site,
      label: label,
      query: query,
      intervalHours: intervalHours,
      createdAt: search.createdAt,
      lastRunAt: search.lastRunAt,
      unseenCount: search.unseenCount,
      totalCount: search.totalCount,
      autoFavorite: autoFavorite,
      autoFavoriteStars: autoFavoriteStars,
      autoUpvote: autoUpvote,
      pinned: search.pinned,
    );
  }

  @override
  Future<List<BunnyPost>> listSearchPosts(int searchId, {bool unseenOnly = false}) async {
    final posts = postsBySearchId[searchId] ?? const [];
    return unseenOnly ? posts.where((post) => !post.isSeen).toList() : List.of(posts);
  }

  @override
  Future<List<BunnyTagStat>> tagAutocomplete(BunnySite site, String prefix, {int limit = 10}) async {
    final matches = tagStats.where((stat) => stat.name.startsWith(prefix)).toList();
    return matches.length > limit ? matches.sublist(0, limit) : matches;
  }

  @override
  Future<List<BunnyTagStat>> topFavoritedTags(BunnySite site, {int limit = 20}) async {
    final matches = topFavoritedTagsBySite[site] ?? const [];
    return matches.length > limit ? matches.sublist(0, limit) : matches;
  }

  BunnyPost _markedSeen(BunnyPost post) => BunnyPost(
    id: post.id,
    site: post.site,
    externalId: post.externalId,
    artist: post.artist,
    title: post.title,
    description: post.description,
    rating: post.rating,
    score: post.score,
    favCount: post.favCount,
    commentCount: post.commentCount,
    fileUrl: post.fileUrl,
    fileExt: post.fileExt,
    fileMd5: post.fileMd5,
    previewUrl: post.previewUrl,
    width: post.width,
    height: post.height,
    createdAtSite: post.createdAtSite,
    cachedAt: post.cachedAt,
    isSeen: true,
    isFavorited: post.isFavorited,
  );

  @override
  Future<void> markPostSeen(int postId) async {
    for (final entry in postsBySearchId.entries) {
      final index = entry.value.indexWhere((post) => post.id == postId);
      if (index == -1) {
        continue;
      }
      entry.value[index] = _markedSeen(entry.value[index]);
    }
  }

  @override
  Future<void> markAllSeen(int searchId) async {
    final posts = postsBySearchId[searchId];
    if (posts == null) {
      return;
    }
    for (var i = 0; i < posts.length; i++) {
      posts[i] = _markedSeen(posts[i]);
    }
  }

  @override
  Future<List<BunnyPostTag>> getPostTagsByCategory(int postId) async => List.of(tagsByPostId[postId] ?? const []);

  @override
  Future<List<String>> getPostSources(int postId) async => List.of(sourcesByPostId[postId] ?? const []);

  @override
  Future<BunnyPostRelationships> getPostRelationships(int postId) async => relationshipsByPostId[postId] ?? const BunnyPostRelationships(hasParent: false, hasActiveChildren: false, children: []);

  @override
  Future<List<int>> getPostPoolIds(int postId) async => List.of(poolIdsByPostId[postId] ?? const []);

  @override
  Future<List<String>> getBlacklist(BunnySite site) async => (blacklistBySite[site] ?? const <String>{}).toList()..sort();

  @override
  Future<void> addBlacklistTag(BunnySite site, String tag) async {
    (blacklistBySite[site] ??= {}).add(tag);
  }

  @override
  Future<void> removeBlacklistTag(BunnySite site, String tag) async {
    blacklistBySite[site]?.remove(tag);
  }

  @override
  Future<int> fetchPost(BunnySite site, int externalId) async {
    final key = '${site.toWireString()}:$externalId';
    final postId = fetchPostResults[key];
    if (postId == null) {
      throw BunnyRepositoryException('no fake fetchPost result registered for $key');
    }
    return postId;
  }

  @override
  Future<BunnyPoolInfo> fetchPool(int poolId) async {
    final info = poolInfoById[poolId];
    if (info == null) {
      throw BunnyRepositoryException('no fake pool registered for $poolId');
    }
    return info;
  }

  @override
  Future<BunnyPost> getPost(int postId) async {
    final direct = postsById[postId];
    if (direct != null) {
      return direct;
    }
    for (final posts in postsBySearchId.values) {
      for (final post in posts) {
        if (post.id == postId) {
          return post;
        }
      }
    }
    throw BunnyRepositoryException('no fake post registered for $postId');
  }

  @override
  Future<List<BunnyPost>> previewSearch(BunnySite site, String query, {int page = 1}) async {
    previewSearchCalls.add((site, query, page));
    return List.of(previewSearchResults['${site.toWireString()}:$query:$page'] ?? const []);
  }

  @override
  Future<List<BunnyPost>> myInkbunnyFavorites({int page = 1}) async {
    myInkbunnyFavoritesCalls.add(page);
    return List.of(myInkbunnyFavoritesResults[page] ?? const []);
  }

  @override
  Future<List<BunnyComment>> getPostComments(int postId) async => List.of(commentsByPostId[postId] ?? const []);

  @override
  Future<int> recordDownload(int postId, String filePath, {String? checksumMd5, bool verified = false}) async {
    recordDownloadCalls.add((postId, filePath, checksumMd5, verified));
    final id = _nextDownloadId++;
    downloadsByPostId.putIfAbsent(postId, () => []).add(BunnyDownload(id: id, postId: postId, filePath: filePath, checksumMd5: checksumMd5, checksumVerified: verified, downloadedAt: '2026-01-01T00:00:00Z'));
    return id;
  }

  @override
  Future<List<BunnyDownload>> listDownloadsForPost(int postId) async => List.of(downloadsByPostId[postId] ?? const []);

  @override
  Future<BunnySyncStats> syncDueSearches() async {
    syncCallCount++;
    return const BunnySyncStats(searchesChecked: 0, searchesSynced: 0, postsUpserted: 0);
  }

  /// Each entry is the `searchId` passed to [syncSearch] (M13.2).
  final List<int> syncSearchCalls = [];

  /// Set here to make [syncSearch] throw for that search id instead of
  /// succeeding -- same per-key-failure convention as [verifyFailures].
  final Map<int, String> syncSearchFailures = {};

  /// If present for a given search id, [syncSearch] awaits this before
  /// resolving (M14.3 test support) -- lets a test pause mid-loop and assert
  /// intermediate UI state, instead of only the state once the whole
  /// "check for updates" run has finished.
  final Map<int, Completer<void>> syncSearchGates = {};

  /// Posts [syncSearch] appends to [postsBySearchId] for that search id once
  /// it resolves, simulating a sync that actually finds something new
  /// (M14.3) -- plain seeding of [postsBySearchId] before the call can't
  /// distinguish "found during this sync" from "was already there".
  final Map<int, List<BunnyPost>> syncSearchNewPosts = {};

  @override
  Future<BunnySyncStats> syncSearch(int searchId) async {
    syncSearchCalls.add(searchId);
    final gate = syncSearchGates[searchId];
    if (gate != null) {
      await gate.future;
    }
    final failure = syncSearchFailures[searchId];
    if (failure != null) {
      throw BunnyRepositoryException(failure);
    }
    final newPosts = syncSearchNewPosts[searchId];
    if (newPosts != null) {
      postsBySearchId.putIfAbsent(searchId, () => []).addAll(newPosts);
    }
    return BunnySyncStats(searchesChecked: 1, searchesSynced: 1, postsUpserted: newPosts?.length ?? 0);
  }

  /// Each entry is the `postId` passed to [queueFavoriteAdd].
  final List<int> favoriteAddCalls = [];

  /// Each entry is the `postId` passed to [queueFavoriteRemove].
  final List<int> favoriteRemoveCalls = [];

  /// Each entry is the `(postId, score)` passed to [queueVote].
  final List<(int, int)> voteCalls = [];

  /// Each entry is the `(postId, body, anonymous)` passed to [queueComment].
  final List<(int, String, bool)> queueCommentCalls = [];
  int processQueueCallCount = 0;

  /// Stats returned by [processQueue] -- defaults to "nothing failed" so
  /// existing tests' favorite/vote optimistic-update assertions keep working
  /// unchanged; set this to a stats value with `actionsFailed > 0` to
  /// simulate a failed queue drain (M9.6.9).
  BunnyQueueStats processQueueResult = const BunnyQueueStats(actionsProcessed: 0, actionsSucceeded: 0, actionsFailed: 0);

  @override
  Future<void> queueFavoriteAdd(int postId, {int? stars}) async {
    favoriteAddCalls.add(postId);
  }

  @override
  Future<void> queueFavoriteRemove(int postId) async {
    favoriteRemoveCalls.add(postId);
  }

  @override
  Future<void> queueVote(int postId, int score, {bool noUnvote = false}) async {
    voteCalls.add((postId, score));
  }

  @override
  Future<void> queueComment(int postId, String body, {bool anonymous = false}) async {
    queueCommentCalls.add((postId, body, anonymous));
  }

  @override
  Future<BunnyQueueStats> processQueue() async {
    processQueueCallCount++;
    return processQueueResult;
  }
}
