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
  final Map<int, List<BunnyPostTag>> tagsByPostId = {};
  final Map<int, List<String>> sourcesByPostId = {};
  final Map<int, BunnyPostRelationships> relationshipsByPostId = {};
  final Map<int, List<int>> poolIdsByPostId = {};

  /// Keyed by `'${site.toWireString()}:$externalId'` -- the post id
  /// [fetchPost] returns for that (site, externalId) pair.
  final Map<String, int> fetchPostResults = {};
  final Map<int, BunnyPoolInfo> poolInfoById = {};

  /// Extra posts [getPost] can resolve by id, for ones that aren't already
  /// sitting in [postsBySearchId] (e.g. a parent/child/pool-mate post that
  /// was only ever fetched standalone via [fetchPost], never synced into a
  /// saved search's results).
  final Map<int, BunnyPost> postsById = {};

  /// Keyed by `'${site.toWireString()}:$query'` -- the posts [previewSearch]
  /// returns for that (site, query) pair; an unregistered pair returns an
  /// empty list (a search genuinely matching nothing is a normal, non-error
  /// outcome, same convention as every other list-returning fake here).
  final Map<String, List<BunnyPost>> previewSearchResults = {};
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
  Future<int> createSearch(BunnySite site, String label, String query, {int intervalHours = 24}) async {
    final id = _nextSearchId++;
    searches.add(BunnySearch(id: id, site: site, label: label, query: query, intervalHours: intervalHours, createdAt: '2026-01-01T00:00:00Z'));
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
        ),
      )
      .toList();

  @override
  Future<void> deleteSearch(int searchId) async {
    searches.removeWhere((search) => search.id == searchId);
    postsBySearchId.remove(searchId);
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
  Future<List<BunnyPost>> previewSearch(BunnySite site, String query) async => List.of(previewSearchResults['${site.toWireString()}:$query'] ?? const []);

  @override
  Future<BunnySyncStats> syncDueSearches() async {
    syncCallCount++;
    return const BunnySyncStats(searchesChecked: 0, searchesSynced: 0, postsUpserted: 0);
  }

  /// Each entry is the `postId` passed to [queueFavoriteAdd].
  final List<int> favoriteAddCalls = [];

  /// Each entry is the `postId` passed to [queueFavoriteRemove].
  final List<int> favoriteRemoveCalls = [];

  /// Each entry is the `(postId, score)` passed to [queueVote].
  final List<(int, int)> voteCalls = [];
  int processQueueCallCount = 0;

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
  Future<void> queueComment(int postId, String body, {bool anonymous = false}) => throw UnimplementedError();

  @override
  Future<BunnyQueueStats> processQueue() async {
    processQueueCallCount++;
    return const BunnyQueueStats(actionsProcessed: 0, actionsSucceeded: 0, actionsFailed: 0);
  }
}
