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

  /// Returns the new search's id. [autoFavorite] (M9.6.8) queues a favorite
  /// for every post this search finds during sync, starting with the very
  /// next sync pass; [autoFavoriteStars] is Inkbunny's 1-3 favorite level
  /// (ignored by e621); [autoUpvote] (M9.7.2, e621 only) queues an upvote the
  /// same way. All three are editable afterward too, via [updateSearch].
  Future<int> createSearch(
    BunnySite site,
    String label,
    String query, {
    int intervalHours = 24,
    bool autoFavorite = false,
    int autoFavoriteStars = 1,
    bool autoUpvote = false,
  });

  Future<List<BunnySearch>> listSearches();

  Future<void> deleteSearch(int searchId);

  /// Updates a search's editable fields in place (M9.7.2) -- replaces the
  /// narrower setSearchAutoFavorite (M9.6.8), so a search's label/query/
  /// interval/auto-favorite/auto-upvote settings can all be changed from one
  /// edit screen. The site itself is not editable.
  Future<void> updateSearch(
    int searchId,
    String label,
    String query, {
    int intervalHours = 24,
    bool autoFavorite = false,
    int autoFavoriteStars = 1,
    bool autoUpvote = false,
  });

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

  /// Ranks tags of currently-favorited [site] posts by how many favorited
  /// posts carry them, descending -- feeds a "most favorited tags" browse
  /// screen (M10.2). Scoped to one site at a time, same as [tagAutocomplete].
  Future<List<BunnyTagStat>> topFavoritedTags(
    BunnySite site, {
    int limit = 20,
  });

  /// Marks a post seen (global per post, not per search) -- clears the
  /// unseen marker [listSearchPosts]'s `unseenOnly` filter and
  /// `BunnyPost.isSeen` are based on.
  Future<void> markPostSeen(int postId);

  /// Bulk counterpart to [markPostSeen] -- marks every post currently linked
  /// to [searchId] as seen in one call, for a post grid's "mark all as seen"
  /// action.
  Future<void> markAllSeen(int searchId);

  /// A post's tags with their categories, for a post detail view's
  /// sectioned tag display (Artists/Characters/Copyrights/Species/General/
  /// Meta for e621; a single uncategorized group for Inkbunny, whose
  /// keywords have no category concept at all).
  Future<List<BunnyPostTag>> getPostTagsByCategory(int postId);

  /// A post's source URLs, in the site's own order. Empty for a post with
  /// none (e.g. every Inkbunny submission -- no such field there).
  Future<List<String>> getPostSources(int postId);

  /// A post's e621 parent/child relationships (always empty/false for
  /// Inkbunny, which has no such concept).
  Future<BunnyPostRelationships> getPostRelationships(int postId);

  /// The e621 pool ids a post belongs to (empty for Inkbunny, or an e621
  /// post in no pools).
  Future<List<int>> getPostPoolIds(int postId);

  /// Fetches a single post live from its site and caches it, without
  /// requiring it to already be linked to any saved search -- used when a
  /// parent/child/pool chip points at a post that was never independently
  /// synced. Returns the (possibly pre-existing) local post id.
  Future<int> fetchPost(BunnySite site, int externalId);

  /// A pool's own metadata, fetched live (e621 only) -- used only to
  /// auto-fill a pool search's label at creation time.
  Future<BunnyPoolInfo> fetchPool(int poolId);

  /// A single cached post by its local id -- used to open a *different*
  /// post's detail view (e.g. after [fetchPost] caches a parent/child/
  /// pool-mate post, this is how its full data gets loaded for display).
  Future<BunnyPost> getPost(int postId);

  /// Runs one 1-indexed [page] of [query] live against [site] and caches
  /// whatever comes back (so thumbnails/ids work immediately), without
  /// creating a saved search -- used by the tag/artist click-through browse
  /// screen, which shows results for a query the user hasn't (yet) chosen to
  /// save. [page] beyond 1 drives that screen's infinite scroll (M9.6.2).
  Future<List<BunnyPost>> previewSearch(BunnySite site, String query, {int page = 1});

  /// A post's existing comments, fetched live (e621 only -- Inkbunny has no
  /// comment concept at all, so this throws [BunnyRepositoryException] for
  /// an Inkbunny post; callers must gate on [BunnyPost.site] themselves, same
  /// as every other e621-only method here). Used to populate the detail
  /// screen's comments section; posting a new one via [queueComment] then
  /// re-calling this is how the new comment appears.
  Future<List<BunnyComment>> getPostComments(int postId);

  /// Records that [filePath] was downloaded for a post, for the download
  /// manager's "already downloaded" indicator and history. This is pure
  /// bookkeeping -- the actual HTTP fetch, disk write, and checksum
  /// computation happen entirely client-side (never proxied through the
  /// server) before this is called. Returns the new download row's id.
  Future<int> recordDownload(int postId, String filePath, {String? checksumMd5, bool verified = false});

  /// A post's download history, newest first. Empty for a post never
  /// downloaded.
  Future<List<BunnyDownload>> listDownloadsForPost(int postId);

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
