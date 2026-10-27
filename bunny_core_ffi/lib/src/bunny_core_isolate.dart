import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import '../bunny_core_ffi_bindings_generated.dart';
import 'dynamic_library.dart';

final BunnyCoreFfiBindings _bindings = BunnyCoreFfiBindings(loadBunnyCoreLibrary());

/// Thrown when a native `bunny_core_*` call fails. "Not found" isn't an
/// error here -- callers get `null` instead, since it's a normal, expected
/// outcome (e.g. no account configured yet).
class BunnyCoreNativeException implements Exception {
  final String message;

  const BunnyCoreNativeException(this.message);

  @override
  String toString() => 'BunnyCoreNativeException: $message';
}

String _resultMessage(bunny_core_result_t result) => _bindings.bunny_core_result_to_string(result).cast<Utf8>().toDartString();

void _check(bunny_core_result_t result) {
  if (result != bunny_core_result_t.BUNNY_CORE_OK) {
    throw BunnyCoreNativeException(_resultMessage(result));
  }
}

String? _readNullableString(Pointer<Char> ptr) => ptr == nullptr ? null : ptr.cast<Utf8>().toDartString();

String _siteWire(bunny_db_site_t site) => site == bunny_db_site_t.BUNNY_DB_SITE_E621 ? 'e621' : 'inkbunny';

bunny_db_site_t _siteFromWire(String site) => switch (site) {
  'e621' => bunny_db_site_t.BUNNY_DB_SITE_E621,
  'inkbunny' => bunny_db_site_t.BUNNY_DB_SITE_INKBUNNY,
  _ => throw ArgumentError.value(site, 'site', 'unknown site'),
};

Map<String, Object?> _accountToMap(bunny_db_account_t account) => {
  'id': account.id,
  // secret is deliberately never surfaced -- see BunnyAccount's doc comment
  // in app/lib/repository/bunny_models.dart.
  'site': _siteWire(account.site),
  'username': _readNullableString(account.username),
  'createdAt': _readNullableString(account.created_at),
};

Map<String, Object?> _searchToMap(bunny_db_search_t search) => {
  'id': search.id,
  'site': _siteWire(search.site),
  'label': _readNullableString(search.label),
  'query': _readNullableString(search.query),
  'intervalHours': search.interval_hours,
  'createdAt': _readNullableString(search.created_at),
  'lastRunAt': _readNullableString(search.last_run_at),
  'unseenCount': search.unseen_count,
  'totalCount': search.total_count,
  'autoFavorite': search.auto_favorite,
  'autoFavoriteStars': search.auto_favorite_stars,
  'autoUpvote': search.auto_upvote,
  'pinned': search.pinned,
  'lastViewedAt': _readNullableString(search.last_viewed_at),
  'usesDefaultInterval': search.uses_default_interval,
  'groupId': search.group_id,
};

Map<String, Object?> _groupToMap(bunny_db_group_t group) => {'id': group.id, 'name': _readNullableString(group.name), 'pinned': group.pinned, 'createdAt': _readNullableString(group.created_at)};

Map<String, Object?> _postToMap(bunny_db_post_t post) => {
  'id': post.id,
  'site': _siteWire(post.site),
  'externalId': post.external_id,
  'artist': _readNullableString(post.artist),
  'title': _readNullableString(post.title),
  'description': _readNullableString(post.description),
  'rating': _readNullableString(post.rating),
  'score': post.score,
  'scoreUp': post.score_up,
  'scoreDown': post.score_down,
  'favCount': post.fav_count,
  'commentCount': post.comment_count,
  'fileUrl': _readNullableString(post.file_url),
  'fileExt': _readNullableString(post.file_ext),
  'fileMd5': _readNullableString(post.file_md5),
  'previewUrl': _readNullableString(post.preview_url),
  'width': post.width,
  'height': post.height,
  'createdAtSite': _readNullableString(post.created_at_site),
  'cachedAt': _readNullableString(post.cached_at),
  'isSeen': post.is_seen,
  'isFavorited': post.is_favorited,
  'sampleUrl': _readNullableString(post.sample_url),
  'userVote': post.user_vote,
  'favoriteStars': post.favorite_stars,
};

Map<String, Object?> _tagStatToMap(bunny_db_tag_stat_t stat) => {'name': _readNullableString(stat.name), 'count': stat.count};

Map<String, Object?> _postTagToMap(bunny_db_post_tag_t tag) => {'name': _readNullableString(tag.name), 'category': _readNullableString(tag.category)};

Map<String, Object?> _syncStatsToMap(bunny_core_sync_stats_t stats) => {'searchesChecked': stats.searches_checked, 'searchesSynced': stats.searches_synced, 'postsUpserted': stats.posts_upserted};

Map<String, Object?> _blacklistSyncStatsToMap(bunny_core_blacklist_sync_stats_t stats) => {'added': stats.added, 'alreadyPresent': stats.already_present, 'skippedMultiTag': stats.skipped_multi_tag};

Map<String, Object?> _queueStatsToMap(bunny_core_queue_stats_t stats) => {'actionsProcessed': stats.actions_processed, 'actionsSucceeded': stats.actions_succeeded, 'actionsFailed': stats.actions_failed};

// --- Isolate request protocol ----------------------------------------------
//
// Every bunny_core_* call does real work (SQLite I/O, and for sync/queue,
// real network I/O), so none of it may run on the main isolate -- it would
// block UI frames. Everything here runs on one dedicated background isolate,
// spawned once and holding the single bunny_core_t handle for the app's
// lifetime, so there's never concurrent native access to worry about (the
// same problem M5's server solved with a mutex; here there's simply only
// ever one caller).

sealed class _Request {
  const _Request();
}

class _OpenRequest extends _Request {
  final String dbPath;
  final String userAgent;

  const _OpenRequest(this.dbPath, this.userAgent);
}

class _CloseRequest extends _Request {
  const _CloseRequest();
}

class _SetAccountRequest extends _Request {
  final String site;
  final String username;
  final String secret;

  const _SetAccountRequest(this.site, this.username, this.secret);
}

class _GetAccountRequest extends _Request {
  final String site;

  const _GetAccountRequest(this.site);
}

class _DeleteAccountRequest extends _Request {
  final String site;

  const _DeleteAccountRequest(this.site);
}

class _VerifyAccountRequest extends _Request {
  final String site;
  final String username;
  final String secret;

  const _VerifyAccountRequest(this.site, this.username, this.secret);
}

class _CreateSearchRequest extends _Request {
  final String site;
  final String label;
  final String query;
  final int intervalHours;
  final bool autoFavorite;
  final int autoFavoriteStars;
  final bool autoUpvote;
  final bool usesDefaultInterval;

  const _CreateSearchRequest(this.site, this.label, this.query, this.intervalHours, this.autoFavorite, this.autoFavoriteStars, this.autoUpvote, this.usesDefaultInterval);
}

class _UpdateSearchRequest extends _Request {
  final int searchId;
  final String label;
  final String query;
  final int intervalHours;
  final bool autoFavorite;
  final int autoFavoriteStars;
  final bool autoUpvote;
  final bool usesDefaultInterval;

  const _UpdateSearchRequest(this.searchId, this.label, this.query, this.intervalHours, this.autoFavorite, this.autoFavoriteStars, this.autoUpvote, this.usesDefaultInterval);
}

class _GetDefaultSyncIntervalHoursRequest extends _Request {
  const _GetDefaultSyncIntervalHoursRequest();
}

class _SetDefaultSyncIntervalHoursRequest extends _Request {
  final int hours;

  const _SetDefaultSyncIntervalHoursRequest(this.hours);
}

class _ListSearchesRequest extends _Request {
  const _ListSearchesRequest();
}

class _DeleteSearchRequest extends _Request {
  final int searchId;

  const _DeleteSearchRequest(this.searchId);
}

class _SetSearchPinnedRequest extends _Request {
  final int searchId;
  final bool pinned;

  const _SetSearchPinnedRequest(this.searchId, this.pinned);
}

class _MergeDuplicateSearchRequest extends _Request {
  final int keeperId;
  final int duplicateId;

  const _MergeDuplicateSearchRequest(this.keeperId, this.duplicateId);
}

class _TouchSearchViewedRequest extends _Request {
  final int searchId;

  const _TouchSearchViewedRequest(this.searchId);
}

class _SetSearchGroupRequest extends _Request {
  final int searchId;
  final int groupId;

  const _SetSearchGroupRequest(this.searchId, this.groupId);
}

class _CreateGroupRequest extends _Request {
  final String name;
  final bool pinned;

  const _CreateGroupRequest(this.name, this.pinned);
}

class _ListGroupsRequest extends _Request {
  const _ListGroupsRequest();
}

class _UpdateGroupRequest extends _Request {
  final int groupId;
  final String name;
  final bool pinned;

  const _UpdateGroupRequest(this.groupId, this.name, this.pinned);
}

class _DeleteGroupRequest extends _Request {
  final int groupId;

  const _DeleteGroupRequest(this.groupId);
}

class _ListSearchPostsRequest extends _Request {
  final int searchId;
  final bool unseenOnly;
  final int page;

  const _ListSearchPostsRequest(this.searchId, this.unseenOnly, this.page);
}

class _GetPostByIdRequest extends _Request {
  final int postId;

  const _GetPostByIdRequest(this.postId);
}

class _SyncDueSearchesRequest extends _Request {
  const _SyncDueSearchesRequest();
}

class _SyncSearchRequest extends _Request {
  final int searchId;

  const _SyncSearchRequest(this.searchId);
}

class _TagAutocompleteRequest extends _Request {
  final String site;
  final String prefix;
  final int limit;

  const _TagAutocompleteRequest(this.site, this.prefix, this.limit);
}

class _TopFavoritedTagsRequest extends _Request {
  final String site;
  final int limit;

  const _TopFavoritedTagsRequest(this.site, this.limit);
}

class _TopUsedTagsRequest extends _Request {
  final String site;
  final int limit;

  const _TopUsedTagsRequest(this.site, this.limit);
}

class _GetStatsReportRequest extends _Request {
  const _GetStatsReportRequest();
}

class _RefreshStatsReportRequest extends _Request {
  const _RefreshStatsReportRequest();
}

class _MarkPostSeenRequest extends _Request {
  final int postId;

  const _MarkPostSeenRequest(this.postId);
}

class _MarkAllSeenRequest extends _Request {
  final int searchId;

  const _MarkAllSeenRequest(this.searchId);
}

class _GetPostTagsByCategoryRequest extends _Request {
  final int postId;

  const _GetPostTagsByCategoryRequest(this.postId);
}

class _GetPostSourcesRequest extends _Request {
  final int postId;

  const _GetPostSourcesRequest(this.postId);
}

class _GetPostRelationshipsRequest extends _Request {
  final int postId;

  const _GetPostRelationshipsRequest(this.postId);
}

class _BlacklistListRequest extends _Request {
  final String site;

  const _BlacklistListRequest(this.site);
}

class _BlacklistAddRequest extends _Request {
  final String site;
  final String tag;

  const _BlacklistAddRequest(this.site, this.tag);
}

class _BlacklistRemoveRequest extends _Request {
  final String site;
  final String tag;

  const _BlacklistRemoveRequest(this.site, this.tag);
}

class _SyncE621BlacklistRequest extends _Request {
  const _SyncE621BlacklistRequest();
}

class _GetPostPoolIdsRequest extends _Request {
  final int postId;

  const _GetPostPoolIdsRequest(this.postId);
}

class _FetchAndCachePostRequest extends _Request {
  final String site;
  final int externalId;

  const _FetchAndCachePostRequest(this.site, this.externalId);
}

class _FetchPoolRequest extends _Request {
  final int poolId;

  const _FetchPoolRequest(this.poolId);
}

class _PreviewSearchRequest extends _Request {
  final String site;
  final String query;
  final int page;

  const _PreviewSearchRequest(this.site, this.query, this.page);
}

class _ListMyInkbunnyFavoritesRequest extends _Request {
  final int page;

  const _ListMyInkbunnyFavoritesRequest(this.page);
}

class _ListCommentsRequest extends _Request {
  final int postId;

  const _ListCommentsRequest(this.postId);
}

class _SearchTagsRequest extends _Request {
  final String nameMatches;
  final int limit;

  const _SearchTagsRequest(this.nameMatches, this.limit);
}

class _GetWikiPageRequest extends _Request {
  final String title;

  const _GetWikiPageRequest(this.title);
}

class _SearchTagAliasesRequest extends _Request {
  final String nameMatches;
  final int limit;

  const _SearchTagAliasesRequest(this.nameMatches, this.limit);
}

class _SearchTagImplicationsRequest extends _Request {
  final String nameMatches;
  final int limit;

  const _SearchTagImplicationsRequest(this.nameMatches, this.limit);
}


class _QueueFavoriteAddRequest extends _Request {
  final int postId;
  final int stars;

  const _QueueFavoriteAddRequest(this.postId, this.stars);
}

class _QueueFavoriteRemoveRequest extends _Request {
  final int postId;

  const _QueueFavoriteRemoveRequest(this.postId);
}

class _QueueVoteRequest extends _Request {
  final int postId;
  final int score;
  final bool noUnvote;

  const _QueueVoteRequest(this.postId, this.score, this.noUnvote);
}

class _QueueCommentRequest extends _Request {
  final int postId;
  final String body;
  final bool anonymous;

  const _QueueCommentRequest(this.postId, this.body, this.anonymous);
}

class _ProcessQueueRequest extends _Request {
  const _ProcessQueueRequest();
}

class _Envelope {
  final int id;
  final _Request request;

  const _Envelope(this.id, this.request);
}

class _Response {
  final int id;
  final Object? value;
  final String? error;

  const _Response(this.id, this.value, this.error);
}

Pointer<bunny_core_t> _handleOpen(_OpenRequest r) {
  return using((arena) {
    final config = arena<bunny_core_config_t>();
    config.ref.db_path = r.dbPath.toNativeUtf8(allocator: arena).cast();
    config.ref.user_agent = r.userAgent.toNativeUtf8(allocator: arena).cast();
    config.ref.e621_transport = nullptr;
    config.ref.inkbunny_transport = nullptr;
    config.ref.min_request_interval_sec = 0;

    final outCore = arena<Pointer<bunny_core_t>>();
    _check(_bindings.bunny_core_open(config, outCore));
    return outCore.value;
  });
}

Map<String, Object?>? _handleGetAccount(Pointer<bunny_core_t> core, _GetAccountRequest r) {
  return using((arena) {
    final out = arena<bunny_db_account_t>();
    final result = _bindings.bunny_core_account_get(core, _siteFromWire(r.site), out);
    if (result == bunny_core_result_t.BUNNY_CORE_ERR_NOT_FOUND) {
      return null;
    }
    _check(result);
    final map = _accountToMap(out.ref);
    _bindings.bunny_db_account_free(out);
    return map;
  });
}

List<Map<String, Object?>> _handleListSearches(Pointer<bunny_core_t> core) {
  return using((arena) {
    final out = arena<bunny_db_search_list_t>();
    _check(_bindings.bunny_core_search_list(core, out));
    final items = <Map<String, Object?>>[];
    for (var i = 0; i < out.ref.count; i++) {
      items.add(_searchToMap(out.ref.items[i]));
    }
    _bindings.bunny_db_search_list_free(out);
    return items;
  });
}

List<Map<String, Object?>> _handleListGroups(Pointer<bunny_core_t> core) {
  return using((arena) {
    final out = arena<bunny_db_group_list_t>();
    _check(_bindings.bunny_core_group_list(core, out));
    final items = <Map<String, Object?>>[];
    for (var i = 0; i < out.ref.count; i++) {
      items.add(_groupToMap(out.ref.items[i]));
    }
    _bindings.bunny_db_group_list_free(out);
    return items;
  });
}

List<Map<String, Object?>> _handleTagAutocomplete(Pointer<bunny_core_t> core, _TagAutocompleteRequest r) {
  return using((arena) {
    final out = arena<bunny_db_tag_stat_list_t>();
    _check(_bindings.bunny_core_tag_autocomplete(core, _siteFromWire(r.site), r.prefix.toNativeUtf8(allocator: arena).cast(), r.limit, out));
    final items = <Map<String, Object?>>[];
    for (var i = 0; i < out.ref.count; i++) {
      items.add(_tagStatToMap(out.ref.items[i]));
    }
    _bindings.bunny_db_tag_stat_list_free(out);
    return items;
  });
}

List<Map<String, Object?>> _handleTopFavoritedTags(Pointer<bunny_core_t> core, _TopFavoritedTagsRequest r) {
  return using((arena) {
    final out = arena<bunny_db_tag_stat_list_t>();
    _check(_bindings.bunny_core_top_favorited_tags(core, _siteFromWire(r.site), r.limit, out));
    final items = <Map<String, Object?>>[];
    for (var i = 0; i < out.ref.count; i++) {
      items.add(_tagStatToMap(out.ref.items[i]));
    }
    _bindings.bunny_db_tag_stat_list_free(out);
    return items;
  });
}

List<Map<String, Object?>> _handleTopUsedTags(Pointer<bunny_core_t> core, _TopUsedTagsRequest r) {
  return using((arena) {
    final out = arena<bunny_db_tag_stat_list_t>();
    _check(_bindings.bunny_core_top_used_tags(core, _siteFromWire(r.site), r.limit, out));
    final items = <Map<String, Object?>>[];
    for (var i = 0; i < out.ref.count; i++) {
      items.add(_tagStatToMap(out.ref.items[i]));
    }
    _bindings.bunny_db_tag_stat_list_free(out);
    return items;
  });
}

List<Map<String, Object?>> _tagStatListToMaps(bunny_db_tag_stat_list_t list) {
  final items = <Map<String, Object?>>[];
  for (var i = 0; i < list.count; i++) {
    items.add(_tagStatToMap(list.items[i]));
  }
  return items;
}

Map<String, Object?> _statsReportToMap(bunny_core_stats_report_t report) => {
  'computedAt': _readNullableString(report.computed_at),
  'topFavoritedTags': _tagStatListToMaps(report.top_favorited_tags),
  'topUsedTags': _tagStatListToMaps(report.top_used_tags),
  'topPools': _tagStatListToMaps(report.top_pools),
  'topViewedSearches': _tagStatListToMaps(report.top_viewed_searches),
};

Map<String, Object?> _handleGetStatsReport(Pointer<bunny_core_t> core) {
  return using((arena) {
    final out = arena<bunny_core_stats_report_t>();
    final hasCache = arena<Bool>();
    final isStale = arena<Bool>();
    _check(_bindings.bunny_core_get_cached_stats_report(core, out, hasCache, isStale));
    final map = _statsReportToMap(out.ref);
    _bindings.bunny_core_stats_report_free(out);
    return map;
  });
}

Map<String, Object?> _handleRefreshStatsReport(Pointer<bunny_core_t> core) {
  return using((arena) {
    final out = arena<bunny_core_stats_report_t>();
    _check(_bindings.bunny_core_refresh_stats_report(core, out));
    final map = _statsReportToMap(out.ref);
    _bindings.bunny_core_stats_report_free(out);
    return map;
  });
}

List<Map<String, Object?>> _handleGetPostTagsByCategory(Pointer<bunny_core_t> core, _GetPostTagsByCategoryRequest r) {
  return using((arena) {
    final out = arena<bunny_db_post_tag_list_t>();
    _check(_bindings.bunny_core_post_get_tags_by_category(core, r.postId, out));
    final items = <Map<String, Object?>>[];
    for (var i = 0; i < out.ref.count; i++) {
      items.add(_postTagToMap(out.ref.items[i]));
    }
    _bindings.bunny_db_post_tag_list_free(out);
    return items;
  });
}

List<String> _handleGetPostSources(Pointer<bunny_core_t> core, _GetPostSourcesRequest r) {
  return using((arena) {
    final out = arena<bunny_db_string_list_t>();
    _check(_bindings.bunny_core_post_get_sources(core, r.postId, out));
    final items = <String>[];
    for (var i = 0; i < out.ref.count; i++) {
      items.add(out.ref.items[i].cast<Utf8>().toDartString());
    }
    _bindings.bunny_db_string_list_free(out);
    return items;
  });
}

List<String> _handleBlacklistList(Pointer<bunny_core_t> core, _BlacklistListRequest r) {
  return using((arena) {
    final out = arena<bunny_db_string_list_t>();
    _check(_bindings.bunny_core_blacklist_list(core, _siteFromWire(r.site), out));
    final items = <String>[];
    for (var i = 0; i < out.ref.count; i++) {
      items.add(out.ref.items[i].cast<Utf8>().toDartString());
    }
    _bindings.bunny_db_string_list_free(out);
    return items;
  });
}

Map<String, Object?> _handleGetPostRelationships(Pointer<bunny_core_t> core, _GetPostRelationshipsRequest r) {
  return using((arena) {
    final out = arena<bunny_db_post_relationships_t>();
    _check(_bindings.bunny_core_post_get_relationships(core, r.postId, out));
    final children = <int>[];
    for (var i = 0; i < out.ref.children.count; i++) {
      children.add(out.ref.children.items[i]);
    }
    final map = {'hasParent': out.ref.has_parent, 'parentExternalId': out.ref.has_parent ? out.ref.parent_external_id : null, 'hasActiveChildren': out.ref.has_active_children, 'children': children};
    _bindings.bunny_db_post_relationships_free(out);
    return map;
  });
}

List<int> _handleGetPostPoolIds(Pointer<bunny_core_t> core, _GetPostPoolIdsRequest r) {
  return using((arena) {
    final out = arena<bunny_db_int64_list_t>();
    _check(_bindings.bunny_core_post_get_pool_ids(core, r.postId, out));
    final items = <int>[];
    for (var i = 0; i < out.ref.count; i++) {
      items.add(out.ref.items[i]);
    }
    _bindings.bunny_db_int64_list_free(out);
    return items;
  });
}

int _handleFetchAndCachePost(Pointer<bunny_core_t> core, _FetchAndCachePostRequest r) {
  return using((arena) {
    final outId = arena<Int64>();
    _check(_bindings.bunny_core_fetch_and_cache_post(core, _siteFromWire(r.site), r.externalId, outId));
    return outId.value;
  });
}

Map<String, Object?> _handleFetchPool(Pointer<bunny_core_t> core, _FetchPoolRequest r) {
  return using((arena) {
    final out = arena<bunny_core_pool_info_t>();
    _check(_bindings.bunny_core_fetch_pool(core, r.poolId, out));
    final referencedPoolIds = <int>[];
    for (var i = 0; i < out.ref.referenced_pool_id_count; i++) {
      referencedPoolIds.add(out.ref.referenced_pool_ids[i]);
    }
    final map = {
      'id': out.ref.id,
      'name': _readNullableString(out.ref.name),
      'description': _readNullableString(out.ref.description),
      'postCount': out.ref.post_count,
      'referencedPoolIds': referencedPoolIds,
    };
    _bindings.bunny_core_pool_info_free(out);
    return map;
  });
}

List<Map<String, Object?>> _handlePreviewSearch(Pointer<bunny_core_t> core, _PreviewSearchRequest r) {
  return using((arena) {
    final out = arena<bunny_db_post_list_t>();
    _check(_bindings.bunny_core_preview_search(core, _siteFromWire(r.site), r.query.toNativeUtf8(allocator: arena).cast(), r.page, out));
    final items = <Map<String, Object?>>[];
    for (var i = 0; i < out.ref.count; i++) {
      items.add(_postToMap(out.ref.items[i]));
    }
    _bindings.bunny_db_post_list_free(out);
    return items;
  });
}

List<Map<String, Object?>> _handleListMyInkbunnyFavorites(Pointer<bunny_core_t> core, _ListMyInkbunnyFavoritesRequest r) {
  return using((arena) {
    final out = arena<bunny_db_post_list_t>();
    _check(_bindings.bunny_core_list_my_inkbunny_favorites(core, r.page, out));
    final items = <Map<String, Object?>>[];
    for (var i = 0; i < out.ref.count; i++) {
      items.add(_postToMap(out.ref.items[i]));
    }
    _bindings.bunny_db_post_list_free(out);
    return items;
  });
}

List<Map<String, Object?>> _handleListComments(Pointer<bunny_core_t> core, _ListCommentsRequest r) {
  return using((arena) {
    final out = arena<bunny_core_comment_list_t>();
    _check(_bindings.bunny_core_list_comments(core, r.postId, out));
    final items = <Map<String, Object?>>[];
    for (var i = 0; i < out.ref.count; i++) {
      final comment = out.ref.items[i];
      items.add({'id': comment.id, 'creatorName': _readNullableString(comment.creator_name), 'body': _readNullableString(comment.body), 'createdAt': _readNullableString(comment.created_at)});
    }
    _bindings.bunny_core_comment_list_free(out);
    return items;
  });
}

Map<String, Object?> _tagToMap(bunny_core_tag_t tag) => {
  'id': tag.id,
  'name': _readNullableString(tag.name),
  'postCount': tag.post_count,
  'category': tag.category.value,
  'relatedTags': _readNullableString(tag.related_tags),
  'isLocked': tag.is_locked,
  'createdAt': _readNullableString(tag.created_at),
  'updatedAt': _readNullableString(tag.updated_at),
};

List<Map<String, Object?>> _handleSearchTags(Pointer<bunny_core_t> core, _SearchTagsRequest r) {
  return using((arena) {
    final out = arena<bunny_core_tag_list_t>();
    _check(_bindings.bunny_core_search_tags(core, r.nameMatches.toNativeUtf8(allocator: arena).cast(), r.limit, out));
    final items = <Map<String, Object?>>[];
    for (var i = 0; i < out.ref.count; i++) {
      items.add(_tagToMap(out.ref.items[i]));
    }
    _bindings.bunny_core_tag_list_free(out);
    return items;
  });
}

Map<String, Object?>? _handleGetWikiPage(Pointer<bunny_core_t> core, _GetWikiPageRequest r) {
  return using((arena) {
    final out = arena<bunny_core_wiki_page_t>();
    final result = _bindings.bunny_core_get_wiki_page(core, r.title.toNativeUtf8(allocator: arena).cast(), out);
    if (result == bunny_core_result_t.BUNNY_CORE_ERR_NOT_FOUND) {
      return null;
    }
    _check(result);
    final otherNames = <String>[];
    for (var i = 0; i < out.ref.other_names.count; i++) {
      otherNames.add(out.ref.other_names.items[i].cast<Utf8>().toDartString());
    }
    final map = {
      'id': out.ref.id,
      'title': _readNullableString(out.ref.title),
      'body': _readNullableString(out.ref.body),
      'otherNames': otherNames,
      'isLocked': out.ref.is_locked,
      'createdAt': _readNullableString(out.ref.created_at),
      'updatedAt': _readNullableString(out.ref.updated_at),
    };
    _bindings.bunny_core_wiki_page_free(out);
    return map;
  });
}

List<Map<String, Object?>> _handleSearchTagAliases(Pointer<bunny_core_t> core, _SearchTagAliasesRequest r) {
  return using((arena) {
    final out = arena<bunny_core_tag_alias_list_t>();
    _check(_bindings.bunny_core_search_tag_aliases(core, r.nameMatches.toNativeUtf8(allocator: arena).cast(), r.limit, out));
    final items = <Map<String, Object?>>[];
    for (var i = 0; i < out.ref.count; i++) {
      final alias = out.ref.items[i];
      items.add({
        'id': alias.id,
        'antecedentName': _readNullableString(alias.antecedent_name),
        'consequentName': _readNullableString(alias.consequent_name),
        'status': _readNullableString(alias.status),
        'postCount': alias.post_count,
      });
    }
    _bindings.bunny_core_tag_alias_list_free(out);
    return items;
  });
}

List<Map<String, Object?>> _handleSearchTagImplications(Pointer<bunny_core_t> core, _SearchTagImplicationsRequest r) {
  return using((arena) {
    final out = arena<bunny_core_tag_implication_list_t>();
    _check(_bindings.bunny_core_search_tag_implications(core, r.nameMatches.toNativeUtf8(allocator: arena).cast(), r.limit, out));
    final items = <Map<String, Object?>>[];
    for (var i = 0; i < out.ref.count; i++) {
      final implication = out.ref.items[i];
      items.add({
        'id': implication.id,
        'antecedentName': _readNullableString(implication.antecedent_name),
        'consequentName': _readNullableString(implication.consequent_name),
        'status': _readNullableString(implication.status),
      });
    }
    _bindings.bunny_core_tag_implication_list_free(out);
    return items;
  });
}

Map<String, Object?> _handleGetPostById(Pointer<bunny_core_t> core, _GetPostByIdRequest r) {
  return using((arena) {
    final out = arena<bunny_db_post_t>();
    _check(_bindings.bunny_core_post_get_by_id(core, r.postId, out));
    final map = _postToMap(out.ref);
    _bindings.bunny_db_post_free(out);
    return map;
  });
}

List<Map<String, Object?>> _handleListSearchPosts(Pointer<bunny_core_t> core, _ListSearchPostsRequest r) {
  return using((arena) {
    final out = arena<bunny_db_post_list_t>();
    _check(_bindings.bunny_core_search_list_posts(core, r.searchId, r.unseenOnly, r.page, out));
    final items = <Map<String, Object?>>[];
    for (var i = 0; i < out.ref.count; i++) {
      items.add(_postToMap(out.ref.items[i]));
    }
    _bindings.bunny_db_post_list_free(out);
    return items;
  });
}

Object? _dispatch(Pointer<bunny_core_t>? core, _Request request, void Function(Pointer<bunny_core_t>?) setCore) {
  if (request is _OpenRequest) {
    final opened = _handleOpen(request);
    setCore(opened);
    return null;
  }
  if (request is _CloseRequest) {
    if (core != null) {
      _bindings.bunny_core_close(core);
      setCore(null);
    }
    return null;
  }

  final c = core ?? (throw StateError('bunny_core_ffi: not open'));

  return using((arena) {
    switch (request) {
      case _OpenRequest():
      case _CloseRequest():
        throw StateError('unreachable'); // handled above
      case _SetAccountRequest r:
        _check(_bindings.bunny_core_account_set(c, _siteFromWire(r.site), r.username.toNativeUtf8(allocator: arena).cast(), r.secret.toNativeUtf8(allocator: arena).cast()));
        return null;
      case _GetAccountRequest r:
        return _handleGetAccount(c, r);
      case _DeleteAccountRequest r:
        _check(_bindings.bunny_core_account_delete(c, _siteFromWire(r.site)));
        return null;
      case _VerifyAccountRequest r:
        _check(_bindings.bunny_core_account_verify(c, _siteFromWire(r.site), r.username.toNativeUtf8(allocator: arena).cast(), r.secret.toNativeUtf8(allocator: arena).cast()));
        return null;
      case _CreateSearchRequest r:
        final outId = arena<Int64>();
        final options = arena<bunny_db_search_options_t>();
        options.ref.auto_favorite = r.autoFavorite;
        options.ref.auto_favorite_stars = r.autoFavoriteStars;
        options.ref.auto_upvote = r.autoUpvote;
        options.ref.uses_default_interval = r.usesDefaultInterval;
        _check(_bindings.bunny_core_search_create(c, _siteFromWire(r.site), r.label.toNativeUtf8(allocator: arena).cast(), r.query.toNativeUtf8(allocator: arena).cast(), r.intervalHours, options, outId));
        return outId.value;
      case _ListSearchesRequest():
        return _handleListSearches(c);
      case _DeleteSearchRequest r:
        _check(_bindings.bunny_core_search_delete(c, r.searchId));
        return null;
      case _SetSearchPinnedRequest r:
        _check(_bindings.bunny_core_search_set_pinned(c, r.searchId, r.pinned));
        return null;
      case _MergeDuplicateSearchRequest r:
        _check(_bindings.bunny_core_search_merge_duplicate(c, r.keeperId, r.duplicateId));
        return null;
      case _TouchSearchViewedRequest r:
        _check(_bindings.bunny_core_search_touch_last_viewed(c, r.searchId));
        return null;
      case _SetSearchGroupRequest r:
        _check(_bindings.bunny_core_search_set_group(c, r.searchId, r.groupId));
        return null;
      case _CreateGroupRequest r:
        final outId = arena<Int64>();
        _check(_bindings.bunny_core_group_create(c, r.name.toNativeUtf8(allocator: arena).cast(), r.pinned, outId));
        return outId.value;
      case _ListGroupsRequest():
        return _handleListGroups(c);
      case _UpdateGroupRequest r:
        _check(_bindings.bunny_core_group_update(c, r.groupId, r.name.toNativeUtf8(allocator: arena).cast(), r.pinned));
        return null;
      case _DeleteGroupRequest r:
        _check(_bindings.bunny_core_group_delete(c, r.groupId));
        return null;
      case _UpdateSearchRequest r:
        final options = arena<bunny_db_search_options_t>();
        options.ref.auto_favorite = r.autoFavorite;
        options.ref.auto_favorite_stars = r.autoFavoriteStars;
        options.ref.auto_upvote = r.autoUpvote;
        options.ref.uses_default_interval = r.usesDefaultInterval;
        _check(_bindings.bunny_core_search_update(c, r.searchId, r.label.toNativeUtf8(allocator: arena).cast(), r.query.toNativeUtf8(allocator: arena).cast(), r.intervalHours, options));
        return null;
      case _ListSearchPostsRequest r:
        return _handleListSearchPosts(c, r);
      case _GetPostByIdRequest r:
        return _handleGetPostById(c, r);
      case _SyncDueSearchesRequest():
        final outStats = arena<bunny_core_sync_stats_t>();
        _check(_bindings.bunny_core_sync_due_searches(c, outStats));
        return _syncStatsToMap(outStats.ref);
      case _SyncSearchRequest r:
        final outStats = arena<bunny_core_sync_stats_t>();
        _check(_bindings.bunny_core_sync_search(c, r.searchId, outStats));
        return _syncStatsToMap(outStats.ref);
      case _TagAutocompleteRequest r:
        return _handleTagAutocomplete(c, r);
      case _TopFavoritedTagsRequest r:
        return _handleTopFavoritedTags(c, r);
      case _TopUsedTagsRequest r:
        return _handleTopUsedTags(c, r);
      case _GetStatsReportRequest():
        return _handleGetStatsReport(c);
      case _RefreshStatsReportRequest():
        return _handleRefreshStatsReport(c);
      case _MarkPostSeenRequest r:
        _check(_bindings.bunny_core_post_mark_seen(c, r.postId));
        return null;
      case _MarkAllSeenRequest r:
        _check(_bindings.bunny_core_search_mark_all_seen(c, r.searchId));
        return null;
      case _GetPostTagsByCategoryRequest r:
        return _handleGetPostTagsByCategory(c, r);
      case _GetPostSourcesRequest r:
        return _handleGetPostSources(c, r);
      case _GetPostRelationshipsRequest r:
        return _handleGetPostRelationships(c, r);
      case _BlacklistListRequest r:
        return _handleBlacklistList(c, r);
      case _BlacklistAddRequest r:
        _check(_bindings.bunny_core_blacklist_add(c, _siteFromWire(r.site), r.tag.toNativeUtf8(allocator: arena).cast()));
        return null;
      case _BlacklistRemoveRequest r:
        _check(_bindings.bunny_core_blacklist_remove(c, _siteFromWire(r.site), r.tag.toNativeUtf8(allocator: arena).cast()));
        return null;
      case _SyncE621BlacklistRequest():
        final outStats = arena<bunny_core_blacklist_sync_stats_t>();
        _check(_bindings.bunny_core_sync_e621_blacklist(c, outStats));
        return _blacklistSyncStatsToMap(outStats.ref);
      case _GetPostPoolIdsRequest r:
        return _handleGetPostPoolIds(c, r);
      case _FetchAndCachePostRequest r:
        return _handleFetchAndCachePost(c, r);
      case _FetchPoolRequest r:
        return _handleFetchPool(c, r);
      case _PreviewSearchRequest r:
        return _handlePreviewSearch(c, r);
      case _ListMyInkbunnyFavoritesRequest r:
        return _handleListMyInkbunnyFavorites(c, r);
      case _ListCommentsRequest r:
        return _handleListComments(c, r);
      case _SearchTagsRequest r:
        return _handleSearchTags(c, r);
      case _GetWikiPageRequest r:
        return _handleGetWikiPage(c, r);
      case _SearchTagAliasesRequest r:
        return _handleSearchTagAliases(c, r);
      case _SearchTagImplicationsRequest r:
        return _handleSearchTagImplications(c, r);
      case _QueueFavoriteAddRequest r:
        _check(_bindings.bunny_core_queue_favorite_add(c, r.postId, r.stars));
        return null;
      case _QueueFavoriteRemoveRequest r:
        _check(_bindings.bunny_core_queue_favorite_remove(c, r.postId));
        return null;
      case _QueueVoteRequest r:
        _check(_bindings.bunny_core_queue_vote(c, r.postId, r.score, r.noUnvote));
        return null;
      case _QueueCommentRequest r:
        _check(_bindings.bunny_core_queue_comment(c, r.postId, r.body.toNativeUtf8(allocator: arena).cast(), r.anonymous));
        return null;
      case _ProcessQueueRequest():
        final outStats = arena<bunny_core_queue_stats_t>();
        _check(_bindings.bunny_core_process_queue(c, outStats));
        return _queueStatsToMap(outStats.ref);
      case _GetDefaultSyncIntervalHoursRequest():
        final outHours = arena<Int>();
        _check(_bindings.bunny_core_get_default_sync_interval_hours(c, outHours));
        return outHours.value;
      case _SetDefaultSyncIntervalHoursRequest r:
        _check(_bindings.bunny_core_set_default_sync_interval_hours(c, r.hours));
        return null;
    }
  });
}

void _isolateEntry(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  Pointer<bunny_core_t>? core;

  receivePort.listen((dynamic message) {
    final envelope = message as _Envelope;
    try {
      final value = _dispatch(core, envelope.request, (c) => core = c);
      mainSendPort.send(_Response(envelope.id, value, null));
    } catch (e) {
      mainSendPort.send(_Response(envelope.id, null, e.toString()));
    }
  });
}

/// Dispatches every `bunny_core_*` operation to one dedicated background
/// isolate. Call [open] once before anything else and [close] when done;
/// every other method requires an open core (matching `bunny_core_open`'s
/// own precondition).
class BunnyCoreNative {
  Isolate? _isolate;
  SendPort? _isolateSendPort;
  final _pending = <int, Completer<Object?>>{};
  var _nextRequestId = 0;
  late final StreamSubscription<dynamic> _subscription;

  Future<void> _ensureIsolateStarted() async {
    if (_isolateSendPort != null) {
      return;
    }
    final receivePort = ReceivePort();
    final sendPortCompleter = Completer<SendPort>();
    _subscription = receivePort.listen((dynamic message) {
      if (message is SendPort) {
        sendPortCompleter.complete(message);
        return;
      }
      final response = message as _Response;
      final completer = _pending.remove(response.id);
      if (completer == null) {
        return;
      }
      if (response.error != null) {
        completer.completeError(BunnyCoreNativeException(response.error!));
      } else {
        completer.complete(response.value);
      }
    });
    _isolate = await Isolate.spawn(_isolateEntry, receivePort.sendPort);
    _isolateSendPort = await sendPortCompleter.future;
  }

  Future<T> _send<T>(_Request request) async {
    await _ensureIsolateStarted();
    final id = _nextRequestId++;
    final completer = Completer<T>();
    _pending[id] = completer as Completer<Object?>;
    _isolateSendPort!.send(_Envelope(id, request));
    return completer.future;
  }

  Future<void> open(String dbPath, String userAgent) => _send<void>(_OpenRequest(dbPath, userAgent));

  Future<void> close() async {
    if (_isolateSendPort == null) {
      return;
    }
    await _send<void>(const _CloseRequest());
    await _subscription.cancel();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _isolateSendPort = null;
  }

  Future<void> setAccount(String site, String username, String secret) => _send<void>(_SetAccountRequest(site, username, secret));

  Future<Map<String, Object?>?> getAccount(String site) => _send<Map<String, Object?>?>(_GetAccountRequest(site));

  Future<void> deleteAccount(String site) => _send<void>(_DeleteAccountRequest(site));

  Future<void> verifyAccount(String site, String username, String secret) => _send<void>(_VerifyAccountRequest(site, username, secret));

  Future<int> createSearch(String site, String label, String query, int intervalHours, {bool autoFavorite = false, int autoFavoriteStars = 1, bool autoUpvote = false, bool usesDefaultInterval = false}) =>
      _send<int>(_CreateSearchRequest(site, label, query, intervalHours, autoFavorite, autoFavoriteStars, autoUpvote, usesDefaultInterval));

  Future<List<Map<String, Object?>>> listSearches() => _send<List<Map<String, Object?>>>(const _ListSearchesRequest());

  Future<void> deleteSearch(int searchId) => _send<void>(_DeleteSearchRequest(searchId));

  Future<void> setSearchPinned(int searchId, bool pinned) => _send<void>(_SetSearchPinnedRequest(searchId, pinned));

  Future<void> mergeDuplicateSearch(int keeperId, int duplicateId) => _send<void>(_MergeDuplicateSearchRequest(keeperId, duplicateId));

  Future<void> touchSearchViewed(int searchId) => _send<void>(_TouchSearchViewedRequest(searchId));

  Future<void> setSearchGroup(int searchId, int groupId) => _send<void>(_SetSearchGroupRequest(searchId, groupId));

  Future<int> createGroup(String name, bool pinned) => _send<int>(_CreateGroupRequest(name, pinned));

  Future<List<Map<String, Object?>>> listGroups() => _send<List<Map<String, Object?>>>(const _ListGroupsRequest());

  Future<void> updateGroup(int groupId, String name, bool pinned) => _send<void>(_UpdateGroupRequest(groupId, name, pinned));

  Future<void> deleteGroup(int groupId) => _send<void>(_DeleteGroupRequest(groupId));

  Future<void> updateSearch(int searchId, String label, String query, int intervalHours, {bool autoFavorite = false, int autoFavoriteStars = 1, bool autoUpvote = false, bool usesDefaultInterval = false}) =>
      _send<void>(_UpdateSearchRequest(searchId, label, query, intervalHours, autoFavorite, autoFavoriteStars, autoUpvote, usesDefaultInterval));

  Future<int> getDefaultSyncIntervalHours() => _send<int>(const _GetDefaultSyncIntervalHoursRequest());

  Future<void> setDefaultSyncIntervalHours(int hours) => _send<void>(_SetDefaultSyncIntervalHoursRequest(hours));

  Future<List<Map<String, Object?>>> listSearchPosts(int searchId, bool unseenOnly, int page) => _send<List<Map<String, Object?>>>(_ListSearchPostsRequest(searchId, unseenOnly, page));

  Future<Map<String, Object?>> getPostById(int postId) => _send<Map<String, Object?>>(_GetPostByIdRequest(postId));

  Future<Map<String, Object?>> syncDueSearches() => _send<Map<String, Object?>>(const _SyncDueSearchesRequest());

  Future<Map<String, Object?>> syncSearch(int searchId) => _send<Map<String, Object?>>(_SyncSearchRequest(searchId));

  Future<List<Map<String, Object?>>> tagAutocomplete(String site, String prefix, int limit) => _send<List<Map<String, Object?>>>(_TagAutocompleteRequest(site, prefix, limit));

  Future<List<Map<String, Object?>>> topFavoritedTags(String site, int limit) => _send<List<Map<String, Object?>>>(_TopFavoritedTagsRequest(site, limit));

  Future<List<Map<String, Object?>>> topUsedTags(String site, int limit) => _send<List<Map<String, Object?>>>(_TopUsedTagsRequest(site, limit));

  Future<Map<String, Object?>> getStatsReport() => _send<Map<String, Object?>>(const _GetStatsReportRequest());

  Future<Map<String, Object?>> refreshStatsReport() => _send<Map<String, Object?>>(const _RefreshStatsReportRequest());

  Future<void> markPostSeen(int postId) => _send<void>(_MarkPostSeenRequest(postId));

  Future<void> markAllSeen(int searchId) => _send<void>(_MarkAllSeenRequest(searchId));

  Future<List<Map<String, Object?>>> getPostTagsByCategory(int postId) => _send<List<Map<String, Object?>>>(_GetPostTagsByCategoryRequest(postId));

  Future<List<String>> getPostSources(int postId) => _send<List<String>>(_GetPostSourcesRequest(postId));

  Future<List<String>> blacklistList(String site) => _send<List<String>>(_BlacklistListRequest(site));

  Future<void> blacklistAdd(String site, String tag) => _send<void>(_BlacklistAddRequest(site, tag));

  Future<void> blacklistRemove(String site, String tag) => _send<void>(_BlacklistRemoveRequest(site, tag));

  Future<Map<String, Object?>> syncE621Blacklist() => _send<Map<String, Object?>>(const _SyncE621BlacklistRequest());

  Future<Map<String, Object?>> getPostRelationships(int postId) => _send<Map<String, Object?>>(_GetPostRelationshipsRequest(postId));

  Future<List<int>> getPostPoolIds(int postId) => _send<List<int>>(_GetPostPoolIdsRequest(postId));

  Future<int> fetchAndCachePost(String site, int externalId) => _send<int>(_FetchAndCachePostRequest(site, externalId));

  Future<Map<String, Object?>> fetchPool(int poolId) => _send<Map<String, Object?>>(_FetchPoolRequest(poolId));

  Future<List<Map<String, Object?>>> previewSearch(String site, String query, {int page = 1}) => _send<List<Map<String, Object?>>>(_PreviewSearchRequest(site, query, page));

  Future<List<Map<String, Object?>>> listMyInkbunnyFavorites({int page = 1}) => _send<List<Map<String, Object?>>>(_ListMyInkbunnyFavoritesRequest(page));

  Future<List<Map<String, Object?>>> listComments(int postId) => _send<List<Map<String, Object?>>>(_ListCommentsRequest(postId));

  Future<List<Map<String, Object?>>> searchTags(String nameMatches, {int limit = 0}) => _send<List<Map<String, Object?>>>(_SearchTagsRequest(nameMatches, limit));

  /// `null` if `title` doesn't match a wiki page -- not every tag has one.
  Future<Map<String, Object?>?> getWikiPage(String title) => _send<Map<String, Object?>?>(_GetWikiPageRequest(title));

  Future<List<Map<String, Object?>>> searchTagAliases(String nameMatches, {int limit = 0}) => _send<List<Map<String, Object?>>>(_SearchTagAliasesRequest(nameMatches, limit));

  Future<List<Map<String, Object?>>> searchTagImplications(String nameMatches, {int limit = 0}) => _send<List<Map<String, Object?>>>(_SearchTagImplicationsRequest(nameMatches, limit));

  Future<void> queueFavoriteAdd(int postId, int stars) => _send<void>(_QueueFavoriteAddRequest(postId, stars));

  Future<void> queueFavoriteRemove(int postId) => _send<void>(_QueueFavoriteRemoveRequest(postId));

  Future<void> queueVote(int postId, int score, bool noUnvote) => _send<void>(_QueueVoteRequest(postId, score, noUnvote));

  Future<void> queueComment(int postId, String body, bool anonymous) => _send<void>(_QueueCommentRequest(postId, body, anonymous));

  Future<Map<String, Object?>> processQueue() => _send<Map<String, Object?>>(const _ProcessQueueRequest());
}
