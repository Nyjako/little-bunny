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
};

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
};

Map<String, Object?> _tagStatToMap(bunny_db_tag_stat_t stat) => {'name': _readNullableString(stat.name), 'count': stat.count};

Map<String, Object?> _postTagToMap(bunny_db_post_tag_t tag) => {'name': _readNullableString(tag.name), 'category': _readNullableString(tag.category)};

Map<String, Object?> _syncStatsToMap(bunny_core_sync_stats_t stats) => {'searchesChecked': stats.searches_checked, 'searchesSynced': stats.searches_synced, 'postsUpserted': stats.posts_upserted};

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

  const _CreateSearchRequest(this.site, this.label, this.query, this.intervalHours);
}

class _ListSearchesRequest extends _Request {
  const _ListSearchesRequest();
}

class _DeleteSearchRequest extends _Request {
  final int searchId;

  const _DeleteSearchRequest(this.searchId);
}

class _ListSearchPostsRequest extends _Request {
  final int searchId;
  final bool unseenOnly;

  const _ListSearchPostsRequest(this.searchId, this.unseenOnly);
}

class _SyncDueSearchesRequest extends _Request {
  const _SyncDueSearchesRequest();
}

class _TagAutocompleteRequest extends _Request {
  final String site;
  final String prefix;
  final int limit;

  const _TagAutocompleteRequest(this.site, this.prefix, this.limit);
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

List<Map<String, Object?>> _handleListSearchPosts(Pointer<bunny_core_t> core, _ListSearchPostsRequest r) {
  return using((arena) {
    final out = arena<bunny_db_post_list_t>();
    _check(_bindings.bunny_core_search_list_posts(core, r.searchId, r.unseenOnly, out));
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
        _check(_bindings.bunny_core_search_create(c, _siteFromWire(r.site), r.label.toNativeUtf8(allocator: arena).cast(), r.query.toNativeUtf8(allocator: arena).cast(), r.intervalHours, outId));
        return outId.value;
      case _ListSearchesRequest():
        return _handleListSearches(c);
      case _DeleteSearchRequest r:
        _check(_bindings.bunny_core_search_delete(c, r.searchId));
        return null;
      case _ListSearchPostsRequest r:
        return _handleListSearchPosts(c, r);
      case _SyncDueSearchesRequest():
        final outStats = arena<bunny_core_sync_stats_t>();
        _check(_bindings.bunny_core_sync_due_searches(c, outStats));
        return _syncStatsToMap(outStats.ref);
      case _TagAutocompleteRequest r:
        return _handleTagAutocomplete(c, r);
      case _MarkPostSeenRequest r:
        _check(_bindings.bunny_core_post_mark_seen(c, r.postId));
        return null;
      case _MarkAllSeenRequest r:
        _check(_bindings.bunny_core_search_mark_all_seen(c, r.searchId));
        return null;
      case _GetPostTagsByCategoryRequest r:
        return _handleGetPostTagsByCategory(c, r);
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

  Future<int> createSearch(String site, String label, String query, int intervalHours) => _send<int>(_CreateSearchRequest(site, label, query, intervalHours));

  Future<List<Map<String, Object?>>> listSearches() => _send<List<Map<String, Object?>>>(const _ListSearchesRequest());

  Future<void> deleteSearch(int searchId) => _send<void>(_DeleteSearchRequest(searchId));

  Future<List<Map<String, Object?>>> listSearchPosts(int searchId, bool unseenOnly) => _send<List<Map<String, Object?>>>(_ListSearchPostsRequest(searchId, unseenOnly));

  Future<Map<String, Object?>> syncDueSearches() => _send<Map<String, Object?>>(const _SyncDueSearchesRequest());

  Future<List<Map<String, Object?>>> tagAutocomplete(String site, String prefix, int limit) => _send<List<Map<String, Object?>>>(_TagAutocompleteRequest(site, prefix, limit));

  Future<void> markPostSeen(int postId) => _send<void>(_MarkPostSeenRequest(postId));

  Future<void> markAllSeen(int searchId) => _send<void>(_MarkAllSeenRequest(searchId));

  Future<List<Map<String, Object?>>> getPostTagsByCategory(int postId) => _send<List<Map<String, Object?>>>(_GetPostTagsByCategoryRequest(postId));

  Future<void> queueFavoriteAdd(int postId, int stars) => _send<void>(_QueueFavoriteAddRequest(postId, stars));

  Future<void> queueFavoriteRemove(int postId) => _send<void>(_QueueFavoriteRemoveRequest(postId));

  Future<void> queueVote(int postId, int score, bool noUnvote) => _send<void>(_QueueVoteRequest(postId, score, noUnvote));

  Future<void> queueComment(int postId, String body, bool anonymous) => _send<void>(_QueueCommentRequest(postId, body, anonymous));

  Future<Map<String, Object?>> processQueue() => _send<Map<String, Object?>>(const _ProcessQueueRequest());
}
