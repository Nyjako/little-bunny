import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/repository/bunny_repository.dart';

/// In-memory fake for widget tests that only exercise account
/// login/verify/list/remove -- fakes the dependency, not the business logic,
/// same philosophy as every C library's own tests. Methods outside that
/// scope (searches, queue) are unimplemented since nothing under test calls
/// them.
class FakeBunnyRepository implements BunnyRepository {
  final Map<BunnySite, BunnyAccount> accounts = {};

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
  Future<int> createSearch(BunnySite site, String label, String query, {int intervalHours = 24}) => throw UnimplementedError();

  @override
  Future<List<BunnySearch>> listSearches() => throw UnimplementedError();

  @override
  Future<void> deleteSearch(int searchId) => throw UnimplementedError();

  @override
  Future<List<BunnyPost>> listSearchPosts(int searchId, {bool unseenOnly = false}) => throw UnimplementedError();

  @override
  Future<BunnySyncStats> syncDueSearches() => throw UnimplementedError();

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
