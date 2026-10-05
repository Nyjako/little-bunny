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
  final bool autoFavorite;

  const BunnySearch({
    required this.id,
    required this.site,
    required this.label,
    required this.query,
    required this.intervalHours,
    required this.createdAt,
    this.lastRunAt,
    this.unseenCount = 0,
    this.autoFavorite = false,
  });
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
/// pool search's label at creation time. Mirrors `bunny_core_pool_info_t`.
class BunnyPoolInfo {
  final int id;
  final String? name;
  final int postCount;

  const BunnyPoolInfo({required this.id, this.name, required this.postCount});
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
