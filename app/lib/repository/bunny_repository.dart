import 'bunny_models.dart';

/// Thrown by a [BunnyRepository] implementation when an operation fails for
/// a reason other than "not found" (which is represented by a `null` return
/// instead, since it's an expected, normal outcome -- e.g. no account
/// configured yet).
class BunnyRepositoryException implements Exception {
  final String message;

  const BunnyRepositoryException(this.message);

  @override
  String toString() => 'BunnyRepositoryException: $message';
}

/// The one interface the UI layer talks to, regardless of whether the app is
/// running standalone (FFI into `bunny_core`, see `bunny_core_ffi/`) or
/// networked (HTTPS against a `bunny_server` instance, see `docs/
/// architecture.md`'s "C server (M5)" section for the exact REST surface
/// this mirrors). Every method is a `Future` since both implementations are
/// inherently asynchronous -- the FFI implementation hops to a dedicated
/// background isolate so native calls never block the UI thread, and the
/// HTTP implementation makes a real network call.
abstract interface class BunnyRepository {
  /// Tests [username]/[secret] against the real site without persisting
  /// anything. Throws [BunnyRepositoryException] if the site rejected them
  /// or the request otherwise failed -- neither this interface nor the
  /// server distinguishes "bad credentials" from "site unreachable" here,
  /// so unlike [getAccount] there's no meaningful non-exceptional failure
  /// case to return instead.
  Future<void> verifyAccount(BunnySite site, String username, String secret);

  /// Stores or replaces the account for `site`. `secret` is the e621 API key
  /// or the Inkbunny password, depending on `site`.
  Future<void> setAccount(BunnySite site, String username, String secret);

  /// Returns the stored account for `site`, or `null` if none is configured.
  Future<BunnyAccount?> getAccount(BunnySite site);

  Future<void> deleteAccount(BunnySite site);

  /// Returns the new search's id.
  Future<int> createSearch(
    BunnySite site,
    String label,
    String query, {
    int intervalHours = 24,
  });

  Future<List<BunnySearch>> listSearches();

  Future<void> deleteSearch(int searchId);

  Future<List<BunnyPost>> listSearchPosts(
    int searchId, {
    bool unseenOnly = false,
  });

  /// Ranks cached tags starting with [prefix] by usage count, for a search
  /// box's autocomplete.
  Future<List<BunnyTagStat>> tagAutocomplete(
    BunnySite site,
    String prefix, {
    int limit = 10,
  });

  /// Marks a post seen (global per post, not per search) -- clears the
  /// unseen marker [listSearchPosts]'s `unseenOnly` filter and
  /// `BunnyPost.isSeen` are based on.
  Future<void> markPostSeen(int postId);

  /// Manually triggers a sync pass (runs every due search). The server also
  /// does this on its own schedule (M5.3); this is for an explicit
  /// "refresh now" action.
  Future<BunnySyncStats> syncDueSearches();

  /// Enqueues a favorite-add action; it isn't sent to the site until
  /// [processQueue] runs. `stars` is Inkbunny's 1-3 rating, or omitted for
  /// e621's plain favorite.
  Future<void> queueFavoriteAdd(int postId, {int? stars});

  Future<void> queueFavoriteRemove(int postId);

  Future<void> queueVote(int postId, int score, {bool noUnvote = false});

  Future<void> queueComment(int postId, String body, {bool anonymous = false});

  /// Manually drains the action queue. Same relationship to the server's own
  /// schedule as [syncDueSearches].
  Future<BunnyQueueStats> processQueue();
}
