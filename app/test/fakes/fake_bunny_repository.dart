import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/repository/bunny_repository.dart';
import 'package:little_bunny/util/media_type.dart';

/// In-memory fake for widget tests that exercise account login/verify/list/
/// remove and search/post browsing -- fakes the dependency, not the business
/// logic, same philosophy as every C library's own tests. Queue methods are
/// unimplemented since nothing under test (through M8) calls them -- that's
/// M9's scope. [syncDueSearches] just counts calls (M8.3's [PostGridScreen]
/// calls it as a manual "refresh" action, but nothing under test needs it to
/// actually add posts -- tests seed `postsBySearchId` directly instead).
class FakeBunnyRepository implements BunnyRepository {
  final Map<BunnySite, BunnyAccount> accounts = {};
  final List<BunnySearch> searches = [];
  final Map<int, List<BunnyPost>> postsBySearchId = {};
  final List<BunnyTagStat> tagStats = [];
  final Map<int, List<BunnyPostTag>> tagsByPostId = {};
  final Map<int, List<String>> sourcesByPostId = {};
  final Map<int, List<BunnyPostFile>> filesByPostId = {};
  final Map<int, BunnyPostRelationships> relationshipsByPostId = {};
  final Map<int, List<int>> poolIdsByPostId = {};
  final Map<int, List<BunnyInkbunnyPoolRef>> inkbunnyPoolsByPostId = {};
  final Map<int, String> inkbunnyPoolNameById = {};

  /// Per-site tag blacklist (M13.3), as a set so add/remove stay idempotent
  /// the same way the real `bunny_db_blacklist_*` functions are.
  final Map<BunnySite, Set<String>> blacklistBySite = {};

  /// Per-slideshow tag exclusion -- additive to, independent of,
  /// [blacklistBySite] above, same shape/idempotency.
  final Map<int, Set<String>> slideshowBlacklistBySlideshowId = {};
  final Map<int, List<BunnyComment>> commentsByPostId = {};

  /// Keyed by `'${site.toWireString()}:$externalId'` -- the post id
  /// [fetchPost] returns for that (site, externalId) pair.
  final Map<String, int> fetchPostResults = {};
  final Map<int, BunnyPoolInfo> poolInfoById = {};

  /// Extra posts [getPost] can resolve by id, for ones that aren't already
  /// sitting in [postsBySearchId] (e.g. a parent/child/pool-mate post that
  /// was only ever fetched standalone via [fetchPost], never synced into a
  /// saved search's results).
  final Map<int, BunnyPost> postsById = {};

  /// Number of times [getPost] should throw for a given post id before
  /// resolving normally -- simulates a transient failure (e.g. the network
  /// not being up yet), for exercising [DownloadQueueService]'s retry logic.
  /// Decrements on each call; once it reaches 0, [getPost] resolves as usual.
  final Map<int, int> getPostFailuresRemaining = {};

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
  final List<BunnyGroup> groups = [];
  int _nextGroupId = 1;
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
  Future<int> createSearch(
    BunnySite site,
    String label,
    String query, {
    int intervalHours = 24,
    bool autoFavorite = false,
    int autoFavoriteStars = 1,
    bool autoUpvote = false,
    bool usesDefaultInterval = false,
    int inkbunnySearchInMask = 0,
    int inkbunnyFieldJoinType = 0,
    int inkbunnyStringJoinType = 0,
    String? inkbunnyUsername,
    int inkbunnySubmissionTypeMask = 0,
    int inkbunnyDaysLimit = 0,
    String? inkbunnyOrderBy,
    bool inkbunnyRandom = false,
    int inkbunnyScraps = 0,
  }) async {
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
        usesDefaultInterval: usesDefaultInterval,
        inkbunnySearchInMask: inkbunnySearchInMask,
        inkbunnyFieldJoinType: inkbunnyFieldJoinType,
        inkbunnyStringJoinType: inkbunnyStringJoinType,
        inkbunnyUsername: inkbunnyUsername,
        inkbunnySubmissionTypeMask: inkbunnySubmissionTypeMask,
        inkbunnyDaysLimit: inkbunnyDaysLimit,
        inkbunnyOrderBy: inkbunnyOrderBy,
        inkbunnyRandom: inkbunnyRandom,
        inkbunnyScraps: inkbunnyScraps,
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
          lastViewedAt: search.lastViewedAt,
          usesDefaultInterval: search.usesDefaultInterval,
          groupId: search.groupId,
          lastUpdatedAt: search.lastUpdatedAt,
          inkbunnySearchInMask: search.inkbunnySearchInMask,
          inkbunnyFieldJoinType: search.inkbunnyFieldJoinType,
          inkbunnyStringJoinType: search.inkbunnyStringJoinType,
          inkbunnyUsername: search.inkbunnyUsername,
          inkbunnySubmissionTypeMask: search.inkbunnySubmissionTypeMask,
          inkbunnyDaysLimit: search.inkbunnyDaysLimit,
          inkbunnyOrderBy: search.inkbunnyOrderBy,
          inkbunnyRandom: search.inkbunnyRandom,
          inkbunnyScraps: search.inkbunnyScraps,
        ),
      )
      .toList();

  @override
  Future<void> deleteSearch(int searchId) async {
    searches.removeWhere((search) => search.id == searchId);
    postsBySearchId.remove(searchId);
  }

  /// Each entry is the `(keeperId, duplicateId)` passed to
  /// [mergeDuplicateSearch].
  final List<(int, int)> mergeDuplicateSearchCalls = [];

  @override
  Future<void> mergeDuplicateSearch(int keeperId, int duplicateId) async {
    mergeDuplicateSearchCalls.add((keeperId, duplicateId));
    final duplicatePosts = postsBySearchId.remove(duplicateId) ?? const [];
    final keeperPosts = postsBySearchId.putIfAbsent(keeperId, () => []);
    final keeperPostIds = keeperPosts.map((post) => post.id).toSet();
    for (final post in duplicatePosts) {
      if (keeperPostIds.add(post.id)) {
        keeperPosts.add(post);
      }
    }
    searches.removeWhere((search) => search.id == duplicateId);
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
      lastViewedAt: search.lastViewedAt,
      usesDefaultInterval: search.usesDefaultInterval,
      groupId: search.groupId,
      lastUpdatedAt: search.lastUpdatedAt,
    );
  }

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
    int inkbunnySearchInMask = 0,
    int inkbunnyFieldJoinType = 0,
    int inkbunnyStringJoinType = 0,
    String? inkbunnyUsername,
    int inkbunnySubmissionTypeMask = 0,
    int inkbunnyDaysLimit = 0,
    String? inkbunnyOrderBy,
    bool inkbunnyRandom = false,
    int inkbunnyScraps = 0,
  }) async {
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
      usesDefaultInterval: usesDefaultInterval,
      groupId: search.groupId,
      inkbunnySearchInMask: inkbunnySearchInMask,
      inkbunnyFieldJoinType: inkbunnyFieldJoinType,
      inkbunnyStringJoinType: inkbunnyStringJoinType,
      inkbunnyUsername: inkbunnyUsername,
      inkbunnySubmissionTypeMask: inkbunnySubmissionTypeMask,
      inkbunnyDaysLimit: inkbunnyDaysLimit,
      inkbunnyOrderBy: inkbunnyOrderBy,
      inkbunnyRandom: inkbunnyRandom,
      inkbunnyScraps: inkbunnyScraps,
    );
  }

  /// Posts per page for [listSearchPosts] -- defaults large enough that
  /// every existing test registering a full post list via [postsBySearchId]
  /// still gets it all back on page 1 without having to know this exists.
  /// Narrow this in a test to exercise `PostGridScreen`'s own infinite
  /// scroll with a manageable post count, instead of constructing hundreds
  /// of posts to hit a realistic page size.
  int searchPostsPageSize = 1000000;

  /// Each entry is the `(searchId, unseenOnly, ratingMask, mediaMask, page)`
  /// passed to [listSearchPosts].
  final List<(int, bool, int, int, int)> listSearchPostsCalls = [];

  /// Mirrors [ratingBadgeFor]'s own per-site bucketing (rating_badge.dart) --
  /// an unrecognized rating string always lands in [kRatingMaskUnknown].
  static int _ratingMaskFor(BunnyPost post) {
    final rating = post.rating;
    if (rating == null || rating.isEmpty) {
      return kRatingMaskUnknown;
    }
    if (post.site == BunnySite.e621) {
      switch (rating.toLowerCase()) {
        case 's':
          return kRatingMaskSafe;
        case 'q':
          return kRatingMaskQuestionable;
        case 'e':
          return kRatingMaskExplicit;
        default:
          return kRatingMaskUnknown;
      }
    }
    final normalized = rating.toLowerCase();
    if (normalized.contains('general') || normalized.contains('safe')) {
      return kRatingMaskSafe;
    }
    if (normalized.contains('mature') || normalized.contains('moderate') || normalized.contains('questionable')) {
      return kRatingMaskQuestionable;
    }
    if (normalized.contains('explicit') || normalized.contains('adult')) {
      return kRatingMaskExplicit;
    }
    return kRatingMaskUnknown;
  }

  /// Mirrors [isVideoExt]/[isGifExt] (util/media_type.dart) -- anything else
  /// (including a null extension) buckets as an image.
  static int _mediaMaskFor(BunnyPost post) {
    if (isVideoExt(post.fileExt)) {
      return kMediaMaskVideo;
    }
    if (isGifExt(post.fileExt)) {
      return kMediaMaskGif;
    }
    return kMediaMaskImage;
  }

  /// Set by a test to pause each [listSearchPosts] call until it completes --
  /// lets a test catch "select entire search"-style multi-page fetching
  /// mid-flight (e.g. to exercise a cancel button) without a real network
  /// delay. `null` (the default) means no pause at all.
  Completer<void>? pauseBeforePage;

  @override
  Future<List<BunnyPost>> listSearchPosts(int searchId, {bool unseenOnly = false, int ratingMask = kRatingMaskAll, int mediaMask = kMediaMaskAll, int page = 1}) async {
    if (pauseBeforePage != null) {
      await pauseBeforePage!.future;
    }
    listSearchPostsCalls.add((searchId, unseenOnly, ratingMask, mediaMask, page));
    final posts = postsBySearchId[searchId] ?? const [];
    var filtered = unseenOnly ? posts.where((post) => !post.isSeen).toList() : List.of(posts);
    filtered = filtered.where((post) => (_ratingMaskFor(post) & ratingMask) != 0 && (_mediaMaskFor(post) & mediaMask) != 0).toList();
    final start = (page - 1) * searchPostsPageSize;
    if (start >= filtered.length) {
      return [];
    }
    final end = (start + searchPostsPageSize < filtered.length) ? start + searchPostsPageSize : filtered.length;
    return filtered.sublist(start, end);
  }

  @override
  Future<List<BunnyTagStat>> tagAutocomplete(BunnySite site, String prefix, {int limit = 10}) async {
    final matches = tagStats.where((stat) => stat.name.startsWith(prefix)).toList();
    return matches.length > limit ? matches.sublist(0, limit) : matches;
  }

  /// Defaults to an empty report with a fixed [BunnyStatsReport.computedAt]
  /// -- tests that care about specific sections overwrite this wholesale
  /// rather than building it up field-by-field, since M40's report is a
  /// single opaque unit server-side too (no per-section fetch/refresh).
  BunnyStatsReport statsReport = const BunnyStatsReport(
    computedAt: '2026-01-01T00:00:00Z',
    topFavoritedTags: [],
    topUsedTags: [],
    topPools: [],
    topViewedSearches: [],
    topTagPairs: [],
  );

  /// Set by [refreshStatsReport] -- lets a test assert a manual refresh
  /// actually happened (distinct from [getStatsReport], which never mutates
  /// this) without needing a real cache/TTL to observe the difference.
  int refreshStatsReportCallCount = 0;

  @override
  Future<BunnyStatsReport> getStatsReport() async => statsReport;

  @override
  Future<BunnyStatsReport> refreshStatsReport() async {
    refreshStatsReportCallCount++;
    return statsReport;
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

  /// Post ids whose NEXT markPostSeen call should throw once -- removed
  /// from this set as soon as it does, so a retry (or a second real call)
  /// succeeds normally. Simulates a transient failure (M26's retry test).
  final Set<int> markPostSeenTransientFailures = {};

  final List<int> markPostSeenCalls = [];

  @override
  Future<void> markPostSeen(int postId) async {
    markPostSeenCalls.add(postId);
    if (markPostSeenTransientFailures.remove(postId)) {
      throw BunnyRepositoryException('transient failure');
    }
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
  Future<List<BunnyPostFile>> getPostFiles(int postId) async => List.of(filesByPostId[postId] ?? const []);

  @override
  Future<BunnyPostRelationships> getPostRelationships(int postId) async => relationshipsByPostId[postId] ?? const BunnyPostRelationships(hasParent: false, hasActiveChildren: false, children: []);

  @override
  Future<List<int>> getPostPoolIds(int postId) async => List.of(poolIdsByPostId[postId] ?? const []);

  @override
  Future<List<BunnyInkbunnyPoolRef>> getInkbunnyPostPools(int postId) async => List.of(inkbunnyPoolsByPostId[postId] ?? const []);

  @override
  Future<String?> getInkbunnyPoolName(int poolId) async => inkbunnyPoolNameById[poolId];

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

  int syncE621BlacklistCallCount = 0;

  /// Result returned by [syncE621Blacklist]; set this to simulate a sync
  /// outcome. Throws [syncE621BlacklistError] instead, if set (simulates no
  /// e621 account configured).
  BunnyBlacklistSyncStats syncE621BlacklistResult = const BunnyBlacklistSyncStats(added: 0, alreadyPresent: 0, skippedInvalid: 0);
  Object? syncE621BlacklistError;

  @override
  Future<BunnyBlacklistSyncStats> syncE621Blacklist() async {
    syncE621BlacklistCallCount++;
    if (syncE621BlacklistError != null) {
      throw syncE621BlacklistError!;
    }
    return syncE621BlacklistResult;
  }

  /// Result returned by [validateTagQuery] regardless of `text` -- doesn't
  /// re-implement the real grammar (libs/tag_query) in Dart just for the
  /// fake; a test drives a "type invalid, see error, then fix it" flow by
  /// setting this to the value the real validator would return for each
  /// piece of text right before triggering that text change. Defaults to
  /// "always valid," matching the common case most tests don't care about.
  int? validateTagQueryResult;

  @override
  Future<int?> validateTagQuery(BunnySite site, String text) async => validateTagQueryResult;

  @override
  Future<int> fetchPost(BunnySite site, int externalId) async {
    final key = '${site.toWireString()}:$externalId';
    final postId = fetchPostResults[key];
    if (postId == null) {
      throw BunnyRepositoryException('no fake fetchPost result registered for $key');
    }
    return postId;
  }

  int fetchPoolCallCount = 0;

  @override
  Future<BunnyPoolInfo> fetchPool(int poolId) async {
    fetchPoolCallCount++;
    final info = poolInfoById[poolId];
    if (info == null) {
      throw BunnyRepositoryException('no fake pool registered for $poolId');
    }
    return info;
  }

  @override
  Future<BunnyPost> getPost(int postId) async {
    final remaining = getPostFailuresRemaining[postId];
    if (remaining != null && remaining > 0) {
      getPostFailuresRemaining[postId] = remaining - 1;
      throw BunnyRepositoryException('simulated transient getPost failure for $postId');
    }
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
  Future<List<BunnyPost>> previewSearch(
    BunnySite site,
    String query, {
    int page = 1,
    int inkbunnySearchInMask = 0,
    int inkbunnyFieldJoinType = 0,
    int inkbunnyStringJoinType = 0,
    String? inkbunnyUsername,
    int inkbunnySubmissionTypeMask = 0,
    int inkbunnyDaysLimit = 0,
    String? inkbunnyOrderBy,
    bool inkbunnyRandom = false,
    int inkbunnyScraps = 0,
  }) async {
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

  final Map<String, List<BunnyTag>> tagsByNameMatches = {};
  final Map<String, BunnyWikiPage?> wikiPageByTitle = {};
  final Map<String, List<BunnyTagAlias>> tagAliasesByNameMatches = {};
  final Map<String, List<BunnyTagImplication>> tagImplicationsByNameMatches = {};

  @override
  Future<List<BunnyTag>> searchTags(String nameMatches, {int limit = 0}) async => List.of(tagsByNameMatches[nameMatches] ?? const []);

  @override
  Future<BunnyWikiPage?> getWikiPage(String title) async => wikiPageByTitle[title];

  @override
  Future<List<BunnyTagAlias>> searchTagAliases(String nameMatches, {int limit = 0}) async => List.of(tagAliasesByNameMatches[nameMatches] ?? const []);

  @override
  Future<List<BunnyTagImplication>> searchTagImplications(String nameMatches, {int limit = 0}) async => List.of(tagImplicationsByNameMatches[nameMatches] ?? const []);

  @override
  Future<void> syncDueSearches() async {
    syncCallCount++;
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
  Future<void> syncSearch(int searchId) async {
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
  }

  /// Simulates the server-side "sync all searches now, regardless of due
  /// status" job (M20): loops over [searches] calling [syncSearch] for
  /// each, same as the real FfiBunnyRepository/the server's sync_worker --
  /// so existing per-search test hooks ([syncSearchGates],
  /// [syncSearchFailures], [syncSearchNewPosts]) keep working unchanged
  /// when triggered through this entry point instead of individual
  /// [syncSearch] calls. Failures on one search don't stop the rest, same
  /// as the real implementations.
  BunnySyncStatus syncStatus = BunnySyncStatus.inactive;
  int syncAllSearchesCallCount = 0;

  @override
  Future<void> syncAllSearches() async {
    syncAllSearchesCallCount++;
    final snapshot = List.of(searches);
    syncStatus = BunnySyncStatus(active: true, source: 'manual', position: 0, total: snapshot.length);
    try {
      for (var i = 0; i < snapshot.length; i++) {
        syncStatus = BunnySyncStatus(active: true, source: 'manual', searchLabel: snapshot[i].label, position: i + 1, total: snapshot.length);
        try {
          await syncSearch(snapshot[i].id);
        } catch (_) {
          // Same "keep going" behavior as the real implementations.
        }
      }
    } finally {
      syncStatus = BunnySyncStatus.inactive;
    }
  }

  @override
  Future<BunnySyncStatus> getSyncStatus() async => syncStatus;

  /// Set by a test to simulate task_queue entries (M24) -- empty by default,
  /// same as the real FfiBunnyRepository.
  List<BunnyTask> tasks = [];

  @override
  Future<List<BunnyTask>> getTasks() async => List.of(tasks);

  /// Set by a test to simulate task_queue history entries (M68 follow-up) --
  /// empty by default, same as the real FfiBunnyRepository.
  List<BunnyTaskHistoryEntry> taskHistory = [];

  @override
  Future<List<BunnyTaskHistoryEntry>> getTaskHistory() async => List.of(taskHistory);

  int defaultSyncIntervalHours = 24;

  @override
  Future<int> getDefaultSyncIntervalHours() async => defaultSyncIntervalHours;

  @override
  Future<void> setDefaultSyncIntervalHours(int hours) async => defaultSyncIntervalHours = hours;

  /// Each entry is the `postId` passed to [queueFavoriteAdd].
  final List<int> favoriteAddCalls = [];

  /// Each entry is the `stars` passed to [queueFavoriteAdd], parallel-indexed
  /// with [favoriteAddCalls] (M27's Inkbunny heart-tier favorites).
  final List<int?> favoriteAddStarsCalls = [];

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
    favoriteAddStarsCalls.add(stars);
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

  /// Overrides [processQueue]'s default behavior when set -- lets a test
  /// gate/delay a drain (e.g. via a `Completer`) to prove a caller doesn't
  /// block on it, without needing to touch [processQueueCallCount]/
  /// [processQueueResult] bookkeeping itself (still does so, see below).
  Future<BunnyQueueStats> Function()? processQueueImpl;

  @override
  Future<BunnyQueueStats> processQueue() async {
    processQueueCallCount++;
    if (processQueueImpl != null) {
      return processQueueImpl!();
    }
    return processQueueResult;
  }

  /// Stateful, keyed by the id [downloadQueueAdd] hands back -- a test
  /// drives the real [DownloadQueueService] against this fake and then
  /// inspects [downloadQueueList] directly, same as reading the real
  /// SQLite-backed table back.
  final Map<int, DownloadQueueRecord> _downloadQueueRows = {};
  int _nextDownloadQueueId = 1;

  /// Seeds a row as if it had been persisted by a previous run -- for tests
  /// of [DownloadQueueService.restore], which never goes through
  /// [downloadQueueAdd] itself.
  void seedDownloadQueueRow({required int postId, required String status, String? failureReason, int poolId = 0, String? poolName, int poolPage = 0}) {
    final id = _nextDownloadQueueId++;
    _downloadQueueRows[id] = DownloadQueueRecord(id: id, postId: postId, status: status, failureReason: failureReason, createdAt: '2026-01-01T00:00:00Z', poolId: poolId, poolName: poolName, poolPage: poolPage);
  }

  @override
  Future<int> downloadQueueAdd(int postId, {int poolId = 0, String? poolName, int poolPage = 0}) async {
    final id = _nextDownloadQueueId++;
    _downloadQueueRows[id] = DownloadQueueRecord(id: id, postId: postId, status: 'queued', createdAt: '2026-01-01T00:00:00Z', poolId: poolId, poolName: poolName, poolPage: poolPage);
    return id;
  }

  @override
  Future<void> downloadQueueSetStatus(int id, String status, {String? failureReason}) async {
    final existing = _downloadQueueRows[id];
    if (existing == null) {
      return;
    }
    _downloadQueueRows[id] = DownloadQueueRecord(
      id: existing.id,
      postId: existing.postId,
      status: status,
      failureReason: failureReason,
      createdAt: existing.createdAt,
      poolId: existing.poolId,
      poolName: existing.poolName,
      poolPage: existing.poolPage,
    );
  }

  @override
  Future<List<DownloadQueueRecord>> downloadQueueList() async => _downloadQueueRows.values.toList(growable: false);

  @override
  Future<void> downloadQueueClearFinished() async {
    _downloadQueueRows.removeWhere((_, row) => row.status == 'succeeded' || row.status == 'checksum_mismatch' || row.status == 'failed');
  }

  /// Overrides [downloadFile]'s simulated fetch (M66) -- the real native
  /// implementation this replaces hands tests nothing to inject a fake
  /// transport into (it's curl-specific), so this fake instead mirrors the
  /// old fake-[http.Client]-based tests as closely as possible: supply a
  /// function (given the requested URL, same as a `MockClient` handler
  /// would see it, for tests that branch per-URL) returning an
  /// [http.Response], and this writes whatever bytes it returns to
  /// `destDir/filename` for real, then verifies/reports the outcome
  /// exactly like the real implementation does (including the
  /// skip-fetch-if-already-verified fast path below). Defaults to a
  /// successful empty-body fetch.
  Future<http.Response> Function(String fileUrl)? downloadFileFetchImpl;

  /// Full override of [downloadFile] itself, for a test that needs to drive
  /// `onProgress` on its own timeline (e.g. simulating bytes arriving in
  /// separate chunks over time) rather than the one-shot-response shape
  /// [downloadFileFetchImpl] covers -- takes priority over it when set.
  Future<DownloadFetchResult> Function(String fileUrl, String destDir, String filename, String? expectedMd5, void Function(int received, int? total) onProgress)? downloadFileImpl;

  @override
  Future<DownloadFetchResult> downloadFile(String fileUrl, Map<String, String> extraHeaders, String destDir, String filename, String? expectedMd5, void Function(int received, int? total) onProgress) async {
    if (downloadFileImpl != null) {
      return downloadFileImpl!(fileUrl, destDir, filename, expectedMd5, onProgress);
    }
    final file = File('$destDir/$filename');
    if (await file.exists()) {
      final existingBytes = await file.readAsBytes();
      final matchesAlready = expectedMd5 == null || expectedMd5.isEmpty || expectedMd5.toLowerCase() == md5.convert(existingBytes).toString();
      if (matchesAlready) {
        return const DownloadFetchResult(outcome: 'verified');
      }
    }

    final response = downloadFileFetchImpl != null ? await downloadFileFetchImpl!(fileUrl) : http.Response.bytes(const [], 200);
    if (response.statusCode != 200) {
      return DownloadFetchResult(outcome: 'failed', errorMessage: 'HTTP ${response.statusCode}');
    }

    final bytes = response.bodyBytes;
    onProgress(bytes.length, bytes.length);
    await Directory(destDir).create(recursive: true);
    await file.writeAsBytes(bytes);

    final checksum = md5.convert(bytes).toString();
    final verified = expectedMd5 == null || expectedMd5.isEmpty || expectedMd5.toLowerCase() == checksum;
    return DownloadFetchResult(outcome: verified ? 'verified' : 'checksumMismatch');
  }

  @override
  Future<void> touchSearchViewed(int searchId) async {
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
      pinned: search.pinned,
      lastViewedAt: DateTime.now().toUtc().toIso8601String(),
      usesDefaultInterval: search.usesDefaultInterval,
      groupId: search.groupId,
      lastUpdatedAt: search.lastUpdatedAt,
    );
  }

  @override
  Future<void> setSearchGroup(int searchId, int groupId) async {
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
      pinned: search.pinned,
      lastViewedAt: search.lastViewedAt,
      usesDefaultInterval: search.usesDefaultInterval,
      groupId: groupId,
      lastUpdatedAt: search.lastUpdatedAt,
    );
  }

  @override
  Future<int> createGroup(String name, bool pinned) async {
    final id = _nextGroupId++;
    groups.add(BunnyGroup(id: id, name: name, pinned: pinned, createdAt: '2026-01-01T00:00:00Z'));
    return id;
  }

  @override
  Future<List<BunnyGroup>> listGroups() async => List.of(groups);

  @override
  Future<void> updateGroup(int groupId, String name, bool pinned) async {
    final index = groups.indexWhere((group) => group.id == groupId);
    if (index == -1) {
      return;
    }
    groups[index] = BunnyGroup(id: groupId, name: name, pinned: pinned, createdAt: groups[index].createdAt);
  }

  @override
  Future<void> deleteGroup(int groupId) async {
    groups.removeWhere((group) => group.id == groupId);
    for (var i = 0; i < searches.length; i++) {
      if (searches[i].groupId == groupId) {
        await setSearchGroup(searches[i].id, 0);
      }
    }
  }

  final List<BunnySlideshow> slideshows = [];
  int _nextSlideshowId = 1;
  final List<BunnySlideshowSearch> slideshowSearches = [];

  /// Committed posts per slideshow -- not a real random pick (deterministic:
  /// takes [postsBySearchId] in order, trimmed to whatever count applies),
  /// same "fake the dependency, not the logic" philosophy as the rest of
  /// this class; good enough for tests that only care about the end state
  /// (which posts ended up committed), not which ones a real reroll would
  /// have picked.
  final Map<int, List<BunnySlideshowPost>> slideshowPostsBySlideshowId = {};

  void _commitSlideshowSearchPicks(int slideshowId, int searchId) {
    final slideshow = slideshows.firstWhere((s) => s.id == slideshowId);
    final link = slideshowSearches.firstWhere((l) => l.slideshowId == slideshowId && l.searchId == searchId);
    final effectiveCount = link.overrideCount ?? slideshow.defaultPostsPerSearch;
    final committed = slideshowPostsBySlideshowId.putIfAbsent(slideshowId, () => []);
    final otherEntries = committed.where((p) => p.searchId != searchId).toList();
    final excludedIds = otherEntries.map((p) => p.post.id).toSet();
    var available = (postsBySearchId[searchId] ?? []).where((p) => !excludedIds.contains(p.id)).toList();
    if (effectiveCount != null && available.length > effectiveCount) {
      available = available.sublist(0, effectiveCount);
    }
    if (slideshow.maxTotalPosts != null) {
      final allowedForThisSearch = slideshow.maxTotalPosts! - otherEntries.length;
      available = allowedForThisSearch <= 0 ? [] : available.take(allowedForThisSearch).toList();
    }
    committed.removeWhere((p) => p.searchId == searchId);
    committed.addAll(available.map((post) => BunnySlideshowPost(searchId: searchId, post: post)));
  }

  @override
  Future<int> slideshowCreate(String label, {int? defaultPostsPerSearch, int? maxTotalPosts}) async {
    final id = _nextSlideshowId++;
    slideshows.add(BunnySlideshow(id: id, label: label, defaultPostsPerSearch: defaultPostsPerSearch, maxTotalPosts: maxTotalPosts, createdAt: '2026-01-01T00:00:00Z'));
    slideshowPostsBySlideshowId[id] = [];
    return id;
  }

  @override
  Future<void> slideshowUpdate(int slideshowId, String label, {int? defaultPostsPerSearch, int? maxTotalPosts}) async {
    final index = slideshows.indexWhere((s) => s.id == slideshowId);
    if (index == -1) {
      throw const BunnyRepositoryException('slideshow not found');
    }
    slideshows[index] = BunnySlideshow(id: slideshowId, label: label, defaultPostsPerSearch: defaultPostsPerSearch, maxTotalPosts: maxTotalPosts, createdAt: slideshows[index].createdAt);
  }

  @override
  Future<void> slideshowDelete(int slideshowId) async {
    slideshows.removeWhere((s) => s.id == slideshowId);
    slideshowSearches.removeWhere((l) => l.slideshowId == slideshowId);
    slideshowPostsBySlideshowId.remove(slideshowId);
  }

  @override
  Future<List<BunnySlideshow>> slideshowList() async => List.of(slideshows);

  @override
  Future<BunnySlideshow> slideshowGet(int slideshowId) async {
    return slideshows.firstWhere((s) => s.id == slideshowId, orElse: () => throw const BunnyRepositoryException('slideshow not found'));
  }

  @override
  Future<void> slideshowSearchAdd(int slideshowId, int searchId, {int? overrideCount}) async {
    final index = slideshowSearches.indexWhere((l) => l.slideshowId == slideshowId && l.searchId == searchId);
    final link = BunnySlideshowSearch(slideshowId: slideshowId, searchId: searchId, overrideCount: overrideCount, addedAt: '2026-01-01T00:00:00Z');
    if (index == -1) {
      slideshowSearches.add(link);
    } else {
      slideshowSearches[index] = link;
    }
    _commitSlideshowSearchPicks(slideshowId, searchId);
  }

  @override
  Future<void> slideshowSearchRemove(int slideshowId, int searchId) async {
    slideshowSearches.removeWhere((l) => l.slideshowId == slideshowId && l.searchId == searchId);
    slideshowPostsBySlideshowId[slideshowId]?.removeWhere((p) => p.searchId == searchId);
  }

  @override
  Future<List<BunnySlideshowSearch>> slideshowSearchList(int slideshowId) async => slideshowSearches.where((l) => l.slideshowId == slideshowId).toList();

  @override
  Future<List<BunnySlideshowPost>> slideshowPostsList(int slideshowId, {int? searchId}) async {
    final all = slideshowPostsBySlideshowId[slideshowId] ?? [];
    if (searchId == null || searchId == 0) {
      return List.of(all);
    }
    return all.where((p) => p.searchId == searchId).toList();
  }

  @override
  Future<void> slideshowRerollAll(int slideshowId) async {
    for (final link in slideshowSearches.where((l) => l.slideshowId == slideshowId).toList()) {
      _commitSlideshowSearchPicks(slideshowId, link.searchId);
    }
  }

  @override
  Future<void> slideshowRerollSearch(int slideshowId, int searchId) async => _commitSlideshowSearchPicks(slideshowId, searchId);

  @override
  Future<void> slideshowReplacePost(int slideshowId, int searchId, int deadPostId) async {
    final committed = slideshowPostsBySlideshowId.putIfAbsent(slideshowId, () => []);
    final excludedIds = committed.map((p) => p.post.id).toSet();
    final replacement = (postsBySearchId[searchId] ?? []).where((p) => !excludedIds.contains(p.id)).firstOrNull;
    if (replacement == null) {
      throw const BunnyRepositoryException('search has no other post to replace with');
    }
    final deadIndex = committed.indexWhere((p) => p.searchId == searchId && p.post.id == deadPostId);
    if (deadIndex == -1) {
      throw const BunnyRepositoryException('post not committed to this search');
    }
    committed[deadIndex] = BunnySlideshowPost(searchId: searchId, post: replacement);
  }

  @override
  Future<List<String>> getSlideshowBlacklist(int slideshowId) async => (slideshowBlacklistBySlideshowId[slideshowId] ?? const <String>{}).toList()..sort();

  @override
  Future<void> addSlideshowBlacklistTag(int slideshowId, String tag) async {
    (slideshowBlacklistBySlideshowId[slideshowId] ??= {}).add(tag);
  }

  @override
  Future<void> removeSlideshowBlacklistTag(int slideshowId, String tag) async {
    slideshowBlacklistBySlideshowId[slideshowId]?.remove(tag);
  }

  @override
  Future<void> close() async {}
}
