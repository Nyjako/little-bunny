/// Mirrors `bunny_db_site_t` (libs/db/include/bunny_db/types.h).
enum BunnySite {
  e621,
  inkbunny;

  String toWireString() => switch (this) {
    BunnySite.e621 => 'e621',
    BunnySite.inkbunny => 'inkbunny',
  };

  static BunnySite fromWireString(String value) => switch (value) {
    'e621' => BunnySite.e621,
    'inkbunny' => BunnySite.inkbunny,
    _ => throw ArgumentError.value(value, 'value', 'unknown site'),
  };
}

/// A stored site account, without its secret -- neither implementation of
/// [BunnyRepository] echoes it back (the server never does, per M5's
/// `GET /accounts/{site}`, so the FFI implementation deliberately doesn't
/// either, to keep both implementations behaviorally identical).
class BunnyAccount {
  final int id;
  final BunnySite site;
  final String username;
  final String createdAt;

  const BunnyAccount({
    required this.id,
    required this.site,
    required this.username,
    required this.createdAt,
  });
}

/// Mirrors `bunny_db_search_t`.
class BunnySearch {
  final int id;
  final BunnySite site;
  final String label;
  final String query;
  final int intervalHours;
  final String createdAt;
  final String? lastRunAt;
  final int unseenCount;

  /// Posts linked to this search, seen or not (M14.1) -- shown alongside
  /// [unseenCount] in the searches list, not just the "new" subset.
  final int totalCount;
  final bool autoFavorite;

  /// Inkbunny favorite level (1-3) queued by [autoFavorite]; ignored by e621,
  /// which has no stars concept (M9.7.2).
  final int autoFavoriteStars;

  /// e621 only -- queues an upvote for every post this search finds during
  /// sync (M9.7.2). Always false for Inkbunny, which has no vote API.
  final bool autoUpvote;

  /// Shown first in the searches list, ahead of the normal sort order
  /// (M14.1), toggled directly from the row rather than the edit form.
  final bool pinned;

  /// When this search/pool was last opened, for the "last viewed" sort
  /// order -- null if it's never been opened (M15).
  final String? lastViewedAt;

  /// When true, [intervalHours] is ignored for scheduling -- the search
  /// follows whatever the server-wide default currently is (see
  /// [BunnyRepository.getDefaultSyncIntervalHours]), re-resolved on every
  /// due-check rather than frozen at creation/edit time.
  final bool usesDefaultInterval;

  /// The [BunnyGroup] this search belongs to, or 0 if ungrouped (M21).
  final int groupId;

  /// e621's own tag-search syntax treats `pool:<id>` as a literal query
  /// string -- `bunny_core_search_create(site: e621, query: 'pool:$id')`
  /// already works with no dedicated backend concept of "this is a pool",
  /// so this is the one place that distinguishes a pool search from a
  /// regular one, for anywhere in the UI that needs to tell them apart
  /// (e.g. SearchesScreen's tab split, M9.6.2; PostGridScreen's display
  /// order, M22 -- pools read like comics, oldest page first).
  bool get isPool => site == BunnySite.e621 && query.startsWith('pool:');

  /// Same "just a search with a recognizable query" trick as [isPool] (M27)
  /// -- auto-created once per configured account (SearchesScreen) so a
  /// user's favorites get cached/paginated/synced through the exact same
  /// machinery as any other saved search, instead of a parallel fetch-on-
  /// demand path. e621's query is a real `fav:<username>` tag search (no
  /// backend support needed at all); Inkbunny's is the fixed literal
  /// `favorited_by:me`, resolved to the logged-in account's numeric id at
  /// sync time (see sync_inkbunny_search's own doc comment for why).
  bool get isFavorites => (site == BunnySite.e621 && query.startsWith('fav:')) || (site == BunnySite.inkbunny && query == 'favorited_by:me');

  const BunnySearch({
    required this.id,
    required this.site,
    required this.label,
    required this.query,
    required this.intervalHours,
    required this.createdAt,
    this.lastRunAt,
    this.unseenCount = 0,
    this.totalCount = 0,
    this.autoFavorite = false,
    this.autoFavoriteStars = 1,
    this.autoUpvote = false,
    this.pinned = false,
    this.lastViewedAt,
    this.usesDefaultInterval = false,
    this.groupId = 0,
  });
}

/// A flat, non-nested way to organize saved searches in the UI's tree view
/// (M21) -- mirrors `bunny_db_group_t`. A search's own membership lives on
/// [BunnySearch.groupId], not here.
class BunnyGroup {
  final int id;
  final String name;
  final bool pinned;
  final String createdAt;

  const BunnyGroup({required this.id, required this.name, this.pinned = false, required this.createdAt});
}

/// Mirrors `bunny_db_post_t`.
class BunnyPost {
  final int id;
  final BunnySite site;
  final int externalId;
  final String? artist;
  final String? title;
  final String? description;
  final String? rating;
  final int score;
  final int scoreUp;
  final int scoreDown;
  final int favCount;
  final int commentCount;
  final String? fileUrl;
  final String? fileExt;
  final String? fileMd5;
  final String? previewUrl;
  final int width;
  final int height;
  final String? createdAtSite;
  final String cachedAt;
  final bool isSeen;
  final bool isFavorited;
  /// The medium-quality image variant (e621's "sample", Inkbunny's "screen");
  /// null if the site didn't provide one, or it was never fetched (Inkbunny
  /// only populates this via a full submission fetch, not a search sync).
  final String? sampleUrl;
  /// -1, 0 (no vote), or 1 -- the caller's own most recently successfully
  /// sent vote direction (M9.7.1). Always 0 for Inkbunny (no vote API).
  final int userVote;
  /// Inkbunny's 1-3 favorite rating; 0 if not favorited or e621's plain favorite.
  final int favoriteStars;

  const BunnyPost({
    required this.id,
    required this.site,
    required this.externalId,
    this.artist,
    this.title,
    this.description,
    this.rating,
    required this.score,
    this.scoreUp = 0,
    this.scoreDown = 0,
    required this.favCount,
    required this.commentCount,
    this.fileUrl,
    this.fileExt,
    this.fileMd5,
    this.previewUrl,
    required this.width,
    required this.height,
    this.createdAtSite,
    required this.cachedAt,
    required this.isSeen,
    required this.isFavorited,
    this.sampleUrl,
    this.userVote = 0,
    this.favoriteStars = 0,
  });
}

/// Mirrors `bunny_db_tag_stat_t` -- a search box's autocomplete suggestion,
/// ranked by how many cached posts use it.
class BunnyTagStat {
  final String name;
  final int count;

  const BunnyTagStat({required this.name, required this.count});
}

/// One of a post's tags, with its category (e621: general/artist/copyright/
/// character/species/invalid/lore/meta; `null` for Inkbunny keywords, which
/// have no category concept at all). Mirrors `bunny_db_post_tag_t`.
class BunnyPostTag {
  final String name;
  final String? category;

  const BunnyPostTag({required this.name, this.category});
}

/// A post's e621 parent/child relationships (site's own external ids --
/// always empty/false for Inkbunny). Mirrors `bunny_db_post_relationships_t`.
class BunnyPostRelationships {
  final bool hasParent;
  final int? parentExternalId;
  final bool hasActiveChildren;
  final List<int> children;

  const BunnyPostRelationships({
    required this.hasParent,
    this.parentExternalId,
    required this.hasActiveChildren,
    required this.children,
  });
}

/// One of a post's existing comments, fetched live (e621 only, no
/// persistence -- same reasoning as [BunnyPoolInfo]). Mirrors
/// `bunny_core_comment_t`.
class BunnyComment {
  final int id;
  final String? creatorName;
  final String? body;
  final String? createdAt;

  const BunnyComment({required this.id, this.creatorName, this.body, this.createdAt});
}

/// A record that a post's file was downloaded to disk -- bookkeeping only,
/// the actual HTTP fetch/disk write/checksum computation never go through
/// this (see [BunnyRepository.recordDownload]'s doc comment). Mirrors
/// `bunny_db_download_t`.
class BunnyDownload {
  final int id;
  final int postId;
  final String? filePath;
  final String? checksumMd5;
  final bool checksumVerified;
  final String? downloadedAt;

  const BunnyDownload({required this.id, required this.postId, this.filePath, this.checksumMd5, required this.checksumVerified, this.downloadedAt});
}

/// A pool's own metadata, fetched live (e621 only) -- used to auto-fill a
/// pool search's label at creation time, and to show the pool's own
/// description (M26). Mirrors `bunny_core_pool_info_t`.
class BunnyPoolInfo {
  final int id;
  final String? name;
  final String? description;
  final int postCount;

  /// Every pool id mentioned via e621's own "pool #`<N>`" dtext convention
  /// in [description] -- e621 pool descriptions routinely cross-reference
  /// related/continuation pools this way. Empty when there are none.
  final List<int> referencedPoolIds;

  const BunnyPoolInfo({required this.id, this.name, this.description, required this.postCount, this.referencedPoolIds = const []});
}

/// Mirrors `bunny_core_sync_stats_t`.
class BunnySyncStats {
  final int searchesChecked;
  final int searchesSynced;
  final int postsUpserted;

  const BunnySyncStats({
    required this.searchesChecked,
    required this.searchesSynced,
    required this.postsUpserted,
  });
}

/// What the background sync worker is doing right now, if anything -- see
/// `GET /sync/status` (server mode) / the equivalent locally-tracked state
/// (standalone mode). Any device polling this sees the same state, whether
/// the sync was triggered by this device, another one, or the scheduler.
class BunnySyncStatus {
  final bool active;

  /// "scheduler", "manual", or "queue" -- null when [active] is false.
  final String? source;

  /// The search currently being synced, if this update is granular enough
  /// to know one (e.g. a forced "sync all" pass) -- null otherwise, even
  /// while [active] is true (e.g. a coarse scheduler/queue pass).
  final String? searchLabel;

  /// 1-indexed position within a batch ("sync all") pass; 0 when not
  /// applicable.
  final int position;

  /// Total searches in the current batch pass; 0 when not applicable.
  final int total;

  const BunnySyncStatus({
    required this.active,
    this.source,
    this.searchLabel,
    this.position = 0,
    this.total = 0,
  });

  static const BunnySyncStatus inactive = BunnySyncStatus(active: false);
}

/// Priority level task_queue dispatches by -- see `GET /tasks` (M24).
/// HIGH is a direct user interaction (manual sync, "check for updates");
/// MEDIUM is the background favorite/vote/comment queue drain; LOW is the
/// scheduler's own periodic due-search sync. Ordered so `index` sorts
/// highest-first the same way the server's own dispatch order does.
enum BunnyTaskPriority {
  low,
  medium,
  high;

  static BunnyTaskPriority fromWireString(String value) => switch (value) {
    'high' => BunnyTaskPriority.high,
    'medium' => BunnyTaskPriority.medium,
    'low' => BunnyTaskPriority.low,
    _ => throw ArgumentError.value(value, 'value', 'unknown task priority'),
  };
}

/// Mirrors task_queue.c's `task_status_t`.
enum BunnyTaskStatus {
  pending,
  running;

  static BunnyTaskStatus fromWireString(String value) => switch (value) {
    'running' => BunnyTaskStatus.running,
    'pending' => BunnyTaskStatus.pending,
    _ => throw ArgumentError.value(value, 'value', 'unknown task status'),
  };
}

/// One entry from `GET /tasks` (M24) -- the in-app task queue view, as
/// opposed to [BunnySyncStatus]'s single "what's running right now"
/// snapshot. The list this appears in is already server-sorted in dispatch
/// order (highest priority first, then FIFO within a priority).
class BunnyTask {
  final int id;
  final BunnyTaskPriority priority;
  final BunnyTaskStatus status;

  /// Human-readable, e.g. "Sync: my search" or "Process favorite/vote/
  /// comment queue" -- display-only, not meant to be parsed.
  final String label;

  final DateTime enqueuedAt;

  const BunnyTask({required this.id, required this.priority, required this.status, required this.label, required this.enqueuedAt});
}

/// Mirrors `bunny_core_queue_stats_t`.
class BunnyQueueStats {
  final int actionsProcessed;
  final int actionsSucceeded;
  final int actionsFailed;

  const BunnyQueueStats({
    required this.actionsProcessed,
    required this.actionsSucceeded,
    required this.actionsFailed,
  });
}
