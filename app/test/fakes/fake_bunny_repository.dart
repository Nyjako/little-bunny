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

  @override
  Future<void> markPostSeen(int postId) async {
    for (final entry in postsBySearchId.entries) {
      final index = entry.value.indexWhere((post) => post.id == postId);
      if (index == -1) {
        continue;
      }
      final post = entry.value[index];
      entry.value[index] = BunnyPost(
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
    }
  }

  @override
  Future<BunnySyncStats> syncDueSearches() async {
    syncCallCount++;
    return const BunnySyncStats(searchesChecked: 0, searchesSynced: 0, postsUpserted: 0);
  }

  @override
  Future<void> queueFavoriteAdd(int postId, {int? stars}) => throw UnimplementedError();

  @override
  Future<void> queueFavoriteRemove(int postId) => throw UnimplementedError();

  @override
  Future<void> queueVote(int postId, int score, {bool noUnvote = false}) => throw UnimplementedError();

  @override
  Future<void> queueComment(int postId, String body, {bool anonymous = false}) => throw UnimplementedError();

  @override
  Future<BunnyQueueStats> processQueue() => throw UnimplementedError();
}
