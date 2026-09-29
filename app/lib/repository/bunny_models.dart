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

  const BunnySearch({
    required this.id,
    required this.site,
    required this.label,
    required this.query,
    required this.intervalHours,
    required this.createdAt,
    this.lastRunAt,
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

  const BunnyPost({
    required this.id,
    required this.site,
    required this.externalId,
    this.artist,
    this.title,
    this.description,
    this.rating,
    required this.score,
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
  });
}

/// Mirrors `bunny_db_tag_stat_t` -- a search box's autocomplete suggestion,
/// ranked by how many cached posts use it.
class BunnyTagStat {
  final String name;
  final int count;

  const BunnyTagStat({required this.name, required this.count});
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
