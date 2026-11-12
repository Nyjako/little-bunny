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
  ///
  /// The `inkbunny*` params (M74) are Inkbunny's own advanced search filters
  /// (api_search.php), ignored entirely for an e621 search:
  /// [inkbunnySearchInMask] -- bitwise-OR of [kInkbunnySearchInKeywords]/
  /// [kInkbunnySearchInTitle]/[kInkbunnySearchInDescription]/
  /// [kInkbunnySearchInMd5], which of the submission's own fields [query] is
  /// matched against (0 defaults to keywords only, matching api_search.php's
  /// own default); [inkbunnyFieldJoinType] -- 0 ("or", the default) matches
  /// text found in any chosen field, 1 ("and") requires every chosen field to
  /// match; [inkbunnyStringJoinType] -- 0 ("and", the default) requires every
  /// word in [query], 1 ("or") matches any word, 2 ("exact") matches the
  /// whole phrase; [inkbunnyUsername] -- limits results to this exact
  /// uploader; [inkbunnySubmissionTypeMask] -- bitwise-OR of
  /// [kInkbunnySubmissionType] bits, 0 for every type; [inkbunnyDaysLimit] --
  /// limits results to the last N days, 0 for no limit; [inkbunnyOrderBy] --
  /// one of api_search.php's own `orderby` values (e.g. "create_datetime",
  /// "views"), null for its default; [inkbunnyRandom] -- shuffles results
  /// after every other filter/sort is applied; [inkbunnyScraps] -- 0 ("both",
  /// the default) includes Scraps alongside the main gallery, 1 excludes
  /// Scraps, 2 returns Scraps only.
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
  });

  Future<List<BunnySearch>> listSearches();

  Future<void> deleteSearch(int searchId);

  /// Folds a pre-existing (site, query) duplicate into [keeperId] (M41 --
  /// M38's own create-time check only stops new ones): [duplicateId]'s
  /// synced posts move over to [keeperId], then [duplicateId] is deleted.
  /// Which of the two to treat as the keeper is the caller's decision --
  /// this doesn't try to reconcile divergent settings (interval, pinned,
  /// group, ...) between them.
  Future<void> mergeDuplicateSearch(int keeperId, int duplicateId);

  /// Pins/unpins a search, toggled directly from the searches list row
  /// (M14.1) rather than through the full edit form.
  Future<void> setSearchPinned(int searchId, bool pinned);

  /// Marks a search/pool as opened right now -- feeds the "last viewed" sort
  /// order (M15).
  Future<void> touchSearchViewed(int searchId);

  /// Moves a search into [groupId]'s group, or ungroups it when [groupId] is
  /// 0 (M21).
  Future<void> setSearchGroup(int searchId, int groupId);

  /// Returns the new group's id (M21).
  Future<int> createGroup(String name, bool pinned);

  Future<List<BunnyGroup>> listGroups();

  Future<void> updateGroup(int groupId, String name, bool pinned);

  /// Deletes the group; member searches are ungrouped, not deleted.
  Future<void> deleteGroup(int groupId);

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
  });

  /// The server-wide default interval (hours) a search follows when its own
  /// `usesDefaultInterval` is set. Standalone (FFI) mode has no "other
  /// devices" to share this with, but still persists it the same way, so
  /// the UI and behavior stay identical across both modes.
  Future<int> getDefaultSyncIntervalHours();

  Future<void> setDefaultSyncIntervalHours(int hours);

  /// Paginated (1-indexed [page]) -- a search can accumulate thousands of
  /// cached posts (e.g. a long-running favorites search), and returning them
  /// all in one unbounded response routinely timed out client-side. Callers
  /// needing every post (e.g. an infinite-scrolling grid) page through this
  /// the same way [previewSearch] already works.
  Future<List<BunnyPost>> listSearchPosts(
    int searchId, {
    bool unseenOnly = false,
    int ratingMask = kRatingMaskAll,
    int mediaMask = kMediaMaskAll,
    int page = 1,
  });

  /// Ranks cached tags starting with [prefix] by usage count, for a search
  /// box's autocomplete.
  Future<List<BunnyTagStat>> tagAutocomplete(
    BunnySite site,
    String prefix, {
    int limit = 10,
  });

  /// The Tag Stats screen's unified report (M40) -- cached for up to 24h.
  /// On [HttpBunnyRepository] (M55), this only ever reads whatever's cached
  /// right now; if it's missing or stale, the server kicks off a background
  /// rebuild and this still returns immediately with the (possibly empty,
  /// possibly stale) data it already had, rather than blocking a civetweb
  /// worker thread until a fresh build finishes -- the problem this exists
  /// to avoid is one slow build blocking *other users'/devices'* unrelated
  /// requests, which only applies to the shared networked server, not
  /// [FfiBunnyRepository]'s single local user, so standalone mode's
  /// `getStatsReport` is likewise cache-only/non-blocking but never
  /// triggers its own rebuild -- only [refreshStatsReport] does, and does
  /// so by blocking (see its own doc comment for why that's fine there).
  /// See [BunnyStatsReport]'s own doc comment for the empty-report shape.
  Future<BunnyStatsReport> getStatsReport();

  /// The screen's manual refresh action. On [HttpBunnyRepository] (M55),
  /// always tells the server to kick off a background rebuild regardless of
  /// the cached report's age, but -- same as [getStatsReport] -- returns
  /// immediately with whatever's cached right now rather than waiting for
  /// that rebuild to finish; a later [getStatsReport] call is what actually
  /// observes the result. [FfiBunnyRepository] has no separate background
  /// worker to delegate to, so it still blocks its own dedicated isolate
  /// until the rebuild finishes and returns the fresh result directly --
  /// acceptable there since it's one explicit action by the one local user,
  /// not a shared server that other requests need to stay responsive
  /// through.
  Future<BunnyStatsReport> refreshStatsReport();

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

  /// Every file on a post, in position order (M28). A single-file post
  /// (including every e621 post) still returns exactly one entry, the same
  /// file [BunnyPost.fileUrl]/[BunnyPost.width]/etc. already represent.
  Future<List<BunnyPostFile>> getPostFiles(int postId);

  /// A post's e621 parent/child relationships (always empty/false for
  /// Inkbunny, which has no such concept).
  Future<BunnyPostRelationships> getPostRelationships(int postId);

  /// The e621 pool ids a post belongs to (empty for Inkbunny, or an e621
  /// post in no pools).
  Future<List<int>> getPostPoolIds(int postId);

  /// The per-site tag blacklist (M13.3), alphabetical. A rule is usually a
  /// single bare tag, but may be a fuller e621-grammar expression (M28/M54,
  /// see [validateTagQuery]) -- `young` and `rating:e young` can both
  /// appear in this list. Applied only to [listSearchPosts] -- tag/pool
  /// browsing and favorites previews are deliberately unaffected, so
  /// nothing is hidden there.
  Future<List<String>> getBlacklist(BunnySite site);

  Future<void> addBlacklistTag(BunnySite site, String tag);

  Future<void> removeBlacklistTag(BunnySite site, String tag);

  /// Pulls the configured e621 account's own blacklist (My Account ->
  /// Blacklisted Tags on e621.net) and imports every single-tag entry not
  /// already present locally (M27). Read-only on e621's side. Requires an
  /// e621 account to already be configured -- throws [BunnyRepositoryException]
  /// otherwise, same as any other e621 call with no usable account.
  Future<BunnyBlacklistSyncStats> syncE621Blacklist();

  /// Syntax-only validation (M28/M54) of a blacklist line or search query
  /// under `site`'s own grammar dialect -- full e621 grammar, or
  /// Inkbunny's narrower AND+exclude-only subset. Returns null if `text`
  /// is valid, otherwise the byte offset of the problem (for highlighting
  /// in a text field). Never touches the DB or a post's tags.
  Future<int?> validateTagQuery(BunnySite site, String text);

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
  ///
  /// The `inkbunny*` params (M74) are the same advanced search filters
  /// [createSearch] documents, applied to this one-off preview instead of a
  /// saved search; ignored entirely for an e621 [site].
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
  });

  /// Inkbunny only -- the equivalent for e621 is just passing `fav:username`
  /// to [previewSearch], since e621's own tag search already supports that
  /// natively. Inkbunny has no such query syntax; it needs the
  /// logged-in account's own numeric user id in a dedicated search param
  /// instead, resolved entirely server/core-side (M10.3) -- this method takes
  /// no username/id itself. Same "stateless fetch and cache" shape as
  /// [previewSearch] otherwise.
  Future<List<BunnyPost>> myInkbunnyFavorites({int page = 1});

  /// A post's existing comments, fetched live (e621 only -- Inkbunny has no
  /// comment concept at all, so this throws [BunnyRepositoryException] for
  /// an Inkbunny post; callers must gate on [BunnyPost.site] themselves, same
  /// as every other e621-only method here). Used to populate the detail
  /// screen's comments section; posting a new one via [queueComment] then
  /// re-calling this is how the new comment appears.
  Future<List<BunnyComment>> getPostComments(int postId);

  /// Tag reference data (M53), fetched live from e621 -- e621-only
  /// regardless of [BunnyPost.site], same reasoning as [getPostComments]
  /// but without the throw: Inkbunny tags fall back to e621's own wiki data
  /// too rather than having no tag info at all (per the user).
  Future<List<BunnyTag>> searchTags(String nameMatches, {int limit = 0});

  /// `null` if [title] doesn't match a wiki page -- not every tag has one.
  Future<BunnyWikiPage?> getWikiPage(String title);

  Future<List<BunnyTagAlias>> searchTagAliases(String nameMatches, {int limit = 0});

  Future<List<BunnyTagImplication>> searchTagImplications(String nameMatches, {int limit = 0});

  /// Manually triggers a sync pass (runs every due search). The server also
  /// does this on its own schedule (M5.3); this is for an explicit
  /// "refresh now" action. Runs in the background (server mode: enqueued
  /// onto the sync worker, M20) -- poll [getSyncStatus] for progress rather
  /// than waiting on this call, which returns as soon as the request is
  /// accepted, not when the sync finishes.
  Future<void> syncDueSearches();

  /// Syncs exactly one search right now, ignoring its own due-interval
  /// (M13.2). Same fire-and-forget shape as [syncDueSearches].
  Future<void> syncSearch(int searchId);

  /// Forces a sync of every search right now, regardless of due status --
  /// the server-side replacement for a client-driven "check for updates"
  /// loop (M20): one call starts the whole pass, and every device (not just
  /// the one that triggered it) sees the same live progress via
  /// [getSyncStatus] instead of tracking it locally. Same fire-and-forget
  /// shape as [syncDueSearches].
  Future<void> syncAllSearches();

  /// What the background sync worker is doing right now (M20) -- see
  /// [BunnySyncStatus]. Meant to be polled periodically while a sync might
  /// be running, from any device, not just the one that started it.
  Future<BunnySyncStatus> getSyncStatus();

  /// Every pending + currently-running task_queue job (M24), in the order
  /// they'll actually run -- the in-app task queue view. Server mode only;
  /// standalone/FFI mode has no background task queue of its own (every
  /// repository call there runs synchronously in-process), so
  /// [FfiBunnyRepository] always returns an empty list.
  Future<List<BunnyTask>> getTasks();

  /// The most recently *finished* task_queue jobs (M68 follow-up), newest
  /// first -- same server-only/standalone-always-empty reasoning as
  /// [getTasks].
  Future<List<BunnyTaskHistoryEntry>> getTaskHistory();

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

  /// Persists a new [DownloadQueueRecord] for [postId], status `'queued'` --
  /// backs [DownloadQueueService]'s own in-memory queue (M62 follow-up) so a
  /// killed/restarted process doesn't lose track of what was queued. Returns
  /// the new row's id, needed by [downloadQueueSetStatus] later. Standalone
  /// mode stores this in the same database as everything else;
  /// [HttpBunnyRepository] keeps its own small dedicated local db for this
  /// one table, since networked mode has no local cache of posts/searches to
  /// share a database with. [poolId]/[poolName]/[poolPage] (M65) mark this
  /// as a pool download -- see [DownloadQueueRecord]'s own doc comment.
  Future<int> downloadQueueAdd(int postId, {int poolId = 0, String? poolName, int poolPage = 0});

  /// Updates [id]'s status in place -- [status] is one of `'queued'`,
  /// `'downloading'`, `'succeeded'`, `'checksum_mismatch'`, or `'failed'`,
  /// matching the database's own CHECK constraint. [failureReason] is
  /// cleared (set to null) when omitted, same as a fresh retry.
  Future<void> downloadQueueSetStatus(int id, String status, {String? failureReason});

  /// Every persisted download-queue row, in insertion order -- read once on
  /// startup by [DownloadQueueService.restore].
  Future<List<DownloadQueueRecord>> downloadQueueList();

  /// Drops every row in a terminal status (`succeeded`/`checksum_mismatch`/
  /// `failed`) -- the persisted counterpart to
  /// [DownloadQueueService.clearFinished].
  Future<void> downloadQueueClearFinished();

  /// Fetches [fileUrl] and writes it to [destDir]/[filename] natively (M66)
  /// -- the actual HTTP fetch + MD5 checksum verification + atomic write
  /// [DownloadManager]'s plain-filesystem-path branch delegates to, for
  /// both standalone and networked mode alike: downloads are never proxied
  /// through the remote server even in networked mode (see
  /// `docs/architecture.md`), so this is always the same local native call
  /// regardless of which [BunnyRepository] implementation it's called on.
  /// [expectedMd5] null/empty means "no checksum to verify, trust as-is."
  /// [onProgress] is called periodically (not necessarily for every byte)
  /// as the fetch progresses; its `total` is null if the server never
  /// reported a Content-Length.
  Future<DownloadFetchResult> downloadFile(
    String fileUrl,
    Map<String, String> extraHeaders,
    String destDir,
    String filename,
    String? expectedMd5,
    void Function(int received, int? total) onProgress,
  );

  /// Releases whatever this implementation holds open -- the FFI isolate
  /// (and the native `bunny_core_t` handle/sqlite connection it owns) or the
  /// HTTP client's connection pool. Previously never called since a
  /// repository lived for the app's entire lifetime; needed now that
  /// switching connection mode from Settings (M15) can discard one mid-run.
  Future<void> close();

  /// Returns the new slideshow's id (M51 v2). `null` [defaultPostsPerSearch]/
  /// [maxTotalPosts] mean "no cap."
  Future<int> slideshowCreate(String label, {int? defaultPostsPerSearch, int? maxTotalPosts});

  Future<void> slideshowUpdate(int slideshowId, String label, {int? defaultPostsPerSearch, int? maxTotalPosts});

  Future<void> slideshowDelete(int slideshowId);

  Future<List<BunnySlideshow>> slideshowList();

  Future<BunnySlideshow> slideshowGet(int slideshowId);

  /// Links [searchId] into [slideshowId] (idempotent -- re-adding an
  /// already-linked search just updates its [overrideCount]) and
  /// immediately commits its initial picks, so the slideshow has posts to
  /// prepare/download right away without a separate reroll call.
  Future<void> slideshowSearchAdd(int slideshowId, int searchId, {int? overrideCount});

  /// Unlinks [searchId] from [slideshowId] and drops its already-committed
  /// posts from the slideshow -- the search itself, and any files already
  /// downloaded for it, are untouched.
  Future<void> slideshowSearchRemove(int slideshowId, int searchId);

  Future<List<BunnySlideshowSearch>> slideshowSearchList(int slideshowId);

  /// Every post currently committed to [slideshowId], optionally scoped to
  /// just [searchId] (omitted or 0 means every search in the slideshow).
  Future<List<BunnySlideshowPost>> slideshowPostsList(int slideshowId, {int? searchId});

  /// Rerolls every search linked to [slideshowId], one at a time -- picks a
  /// fresh set of posts per search, never duplicating a post across
  /// searches within the same slideshow.
  Future<void> slideshowRerollAll(int slideshowId);

  /// Rerolls just [searchId]'s own posts within [slideshowId], leaving
  /// every other linked search's posts untouched.
  Future<void> slideshowRerollSearch(int slideshowId, int searchId);

  /// Self-healing swap (M51 v2): replaces [deadPostId] (e.g. deleted from
  /// the site, so its download keeps failing) with a fresh pick from the
  /// same search. Throws [BunnyRepositoryException] if that search has no
  /// other post left to pick -- the caller should report that as
  /// "couldn't be replaced" rather than retrying forever.
  Future<void> slideshowReplacePost(int slideshowId, int searchId, int deadPostId);

  /// A SECOND, independent tag exclusion scoped to one slideshow -- additive
  /// to, never a replacement for, [getBlacklist] above (both apply at
  /// once), and -- unlike it -- not exempted for a favorites- or pool-
  /// sourced search: a slideshow auto-advances on a timer, so a user
  /// excluding a tag here means "not in THIS slideshow," regardless of
  /// where the post came from. A rule is validated under e621's grammar
  /// always (not per-site, since a slideshow has no single site of its own
  /// -- it can mix e621 and Inkbunny searches); see [validateTagQuery].
  Future<List<String>> getSlideshowBlacklist(int slideshowId);

  Future<void> addSlideshowBlacklistTag(int slideshowId, String tag);

  Future<void> removeSlideshowBlacklistTag(int slideshowId, String tag);
}
