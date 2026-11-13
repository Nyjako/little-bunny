import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bunny_core_ffi/bunny_core_ffi.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:meta/meta.dart';

import 'bunny_models.dart';
import 'bunny_repository.dart';
import 'download_file_native.dart';

BunnyAccount _accountFromJson(Map<String, Object?> j) => BunnyAccount(
  id: (j['id'] as num).toInt(),
  site: BunnySite.fromWireString(j['site'] as String),
  username: j['username'] as String,
  createdAt: j['created_at'] as String,
);

BunnySearch _searchFromJson(Map<String, Object?> j) => BunnySearch(
  id: (j['id'] as num).toInt(),
  site: BunnySite.fromWireString(j['site'] as String),
  label: j['label'] as String,
  query: j['query'] as String,
  intervalHours: (j['interval_hours'] as num).toInt(),
  createdAt: j['created_at'] as String,
  lastRunAt: j['last_run_at'] as String?,
  unseenCount: (j['unseen_count'] as num?)?.toInt() ?? 0,
  totalCount: (j['total_count'] as num?)?.toInt() ?? 0,
  autoFavorite: j['auto_favorite'] as bool? ?? false,
  autoFavoriteStars: (j['auto_favorite_stars'] as num?)?.toInt() ?? 1,
  autoUpvote: j['auto_upvote'] as bool? ?? false,
  pinned: j['pinned'] as bool? ?? false,
  lastViewedAt: j['last_viewed_at'] as String?,
  usesDefaultInterval: j['uses_default_interval'] as bool? ?? false,
  groupId: (j['group_id'] as num?)?.toInt() ?? 0,
  lastUpdatedAt: j['last_updated_at'] as String?,
  inkbunnySearchInMask: (j['inkbunny_search_in_mask'] as num?)?.toInt() ?? 0,
  inkbunnyFieldJoinType: (j['inkbunny_field_join_type'] as num?)?.toInt() ?? 0,
  inkbunnyStringJoinType: (j['inkbunny_string_join_type'] as num?)?.toInt() ?? 0,
  inkbunnyUsername: j['inkbunny_username'] as String?,
  inkbunnySubmissionTypeMask: (j['inkbunny_submission_type_mask'] as num?)?.toInt() ?? 0,
  inkbunnyDaysLimit: (j['inkbunny_days_limit'] as num?)?.toInt() ?? 0,
  inkbunnyOrderBy: j['inkbunny_order_by'] as String?,
  inkbunnyRandom: j['inkbunny_random'] as bool? ?? false,
  inkbunnyScraps: (j['inkbunny_scraps'] as num?)?.toInt() ?? 0,
);

BunnyGroup _groupFromJson(Map<String, Object?> j) => BunnyGroup(id: (j['id'] as num).toInt(), name: j['name'] as String, pinned: j['pinned'] as bool, createdAt: j['created_at'] as String);

BunnySlideshow _slideshowFromJson(Map<String, Object?> j) => BunnySlideshow(
  id: (j['id'] as num).toInt(),
  label: j['label'] as String,
  defaultPostsPerSearch: (j['default_posts_per_search'] as num?)?.toInt(),
  maxTotalPosts: (j['max_total_posts'] as num?)?.toInt(),
  createdAt: j['created_at'] as String,
);

BunnySlideshowSearch _slideshowSearchFromJson(Map<String, Object?> j) => BunnySlideshowSearch(
  slideshowId: (j['slideshow_id'] as num).toInt(),
  searchId: (j['search_id'] as num).toInt(),
  overrideCount: (j['override_count'] as num?)?.toInt(),
  addedAt: j['added_at'] as String,
);

BunnyPost _postFromJson(Map<String, Object?> j) => BunnyPost(
  id: (j['id'] as num).toInt(),
  site: BunnySite.fromWireString(j['site'] as String),
  externalId: (j['external_id'] as num).toInt(),
  artist: j['artist'] as String?,
  title: j['title'] as String?,
  description: j['description'] as String?,
  rating: j['rating'] as String?,
  score: (j['score'] as num).toInt(),
  scoreUp: (j['score_up'] as num?)?.toInt() ?? 0,
  scoreDown: (j['score_down'] as num?)?.toInt() ?? 0,
  favCount: (j['fav_count'] as num).toInt(),
  commentCount: (j['comment_count'] as num).toInt(),
  fileUrl: j['file_url'] as String?,
  fileExt: j['file_ext'] as String?,
  fileMd5: j['file_md5'] as String?,
  previewUrl: j['preview_url'] as String?,
  width: (j['width'] as num).toInt(),
  height: (j['height'] as num).toInt(),
  createdAtSite: j['created_at_site'] as String?,
  cachedAt: j['cached_at'] as String,
  isSeen: j['is_seen'] as bool,
  isFavorited: j['is_favorited'] as bool,
  // sample_url (M8.5.5a), user_vote (M9.7.1), favorite_stars (M27) were all
  // added to the server's post JSON well after this app's initial release --
  // a server a version or two behind the app simply won't send them yet.
  // Defaulting instead of crashing means an outdated server degrades to
  // "this one feature's data is momentarily unavailable" rather than taking
  // down every single post view (every BunnyPost parse goes through this one
  // function) until the server catches up.
  sampleUrl: j['sample_url'] as String?,
  userVote: (j['user_vote'] as num?)?.toInt() ?? 0,
  favoriteStars: (j['favorite_stars'] as num?)?.toInt() ?? 0,
);

BunnySlideshowPost _slideshowPostFromJson(Map<String, Object?> j) => BunnySlideshowPost(searchId: (j['search_id'] as num).toInt(), post: _postFromJson(j['post'] as Map<String, Object?>));

BunnyTagStat _tagStatFromJson(Map<String, Object?> j) => BunnyTagStat(name: j['name'] as String, count: (j['count'] as num).toInt());

List<BunnyTagStat> _tagStatListFromJson(Object? list) => (list as List).cast<Map<String, Object?>>().map(_tagStatFromJson).toList();

BunnyStatsReport _statsReportFromJson(Map<String, Object?> j) => BunnyStatsReport(
  computedAt: j['computed_at'] as String?,
  topFavoritedTags: _tagStatListFromJson(j['top_favorited_tags']),
  topUsedTags: _tagStatListFromJson(j['top_used_tags']),
  topPools: _tagStatListFromJson(j['top_pools']),
  topViewedSearches: _tagStatListFromJson(j['top_viewed_searches']),
  topTagPairs: _tagStatListFromJson(j['top_tag_pairs']),
);

BunnyPostTag _postTagFromJson(Map<String, Object?> j) => BunnyPostTag(name: j['name'] as String, category: j['category'] as String?);

BunnyPostFile _postFileFromJson(Map<String, Object?> j) => BunnyPostFile(
  fileUrl: j['file_url'] as String,
  sampleUrl: j['sample_url'] as String?,
  previewUrl: j['preview_url'] as String?,
  fileExt: j['file_ext'] as String?,
  fileMd5: j['file_md5'] as String?,
  width: (j['width'] as num).toInt(),
  height: (j['height'] as num).toInt(),
  mimetype: j['mimetype'] as String?,
);

BunnyPostRelationships _relationshipsFromJson(Map<String, Object?> j) => BunnyPostRelationships(
  hasParent: j['has_parent'] as bool,
  parentExternalId: (j['parent_external_id'] as num?)?.toInt(),
  hasActiveChildren: j['has_active_children'] as bool,
  children: (j['children'] as List).map((e) => (e as num).toInt()).toList(),
);

BunnyPoolInfo _poolInfoFromJson(Map<String, Object?> j) => BunnyPoolInfo(
  id: (j['id'] as num).toInt(),
  name: j['name'] as String?,
  description: j['description'] as String?,
  postCount: (j['post_count'] as num).toInt(),
  referencedPoolIds: (j['referenced_pool_ids'] as List? ?? const []).map((e) => (e as num).toInt()).toList(),
);

BunnyComment _commentFromJson(Map<String, Object?> j) =>
    BunnyComment(id: (j['id'] as num).toInt(), creatorName: j['creator_name'] as String?, body: j['body'] as String?, createdAt: j['created_at'] as String?);

BunnyTag _tagFromJson(Map<String, Object?> j) => BunnyTag(
  id: (j['id'] as num).toInt(),
  name: j['name'] as String?,
  postCount: (j['post_count'] as num).toInt(),
  category: BunnyTagCategory.values[(j['category'] as num).toInt()],
  relatedTags: j['related_tags'] as String?,
  isLocked: j['is_locked'] as bool,
  createdAt: j['created_at'] as String?,
  updatedAt: j['updated_at'] as String?,
);

BunnyWikiPage _wikiPageFromJson(Map<String, Object?> j) => BunnyWikiPage(
  id: (j['id'] as num).toInt(),
  title: j['title'] as String?,
  body: j['body'] as String?,
  otherNames: (j['other_names'] as List? ?? const []).cast<String>(),
  isLocked: j['is_locked'] as bool,
  createdAt: j['created_at'] as String?,
  updatedAt: j['updated_at'] as String?,
);

BunnyTagAlias _tagAliasFromJson(Map<String, Object?> j) => BunnyTagAlias(
  id: (j['id'] as num).toInt(),
  antecedentName: j['antecedent_name'] as String?,
  consequentName: j['consequent_name'] as String?,
  status: j['status'] as String?,
  postCount: (j['post_count'] as num).toInt(),
);

BunnyTagImplication _tagImplicationFromJson(Map<String, Object?> j) =>
    BunnyTagImplication(id: (j['id'] as num).toInt(), antecedentName: j['antecedent_name'] as String?, consequentName: j['consequent_name'] as String?, status: j['status'] as String?);

BunnyQueueStats _queueStatsFromJson(Map<String, Object?> j) => BunnyQueueStats(
  actionsProcessed: (j['actions_processed'] as num).toInt(),
  actionsSucceeded: (j['actions_succeeded'] as num).toInt(),
  actionsFailed: (j['actions_failed'] as num).toInt(),
);

BunnyBlacklistSyncStats _blacklistSyncStatsFromJson(Map<String, Object?> j) => BunnyBlacklistSyncStats(
  added: (j['added'] as num).toInt(),
  alreadyPresent: (j['already_present'] as num).toInt(),
  skippedInvalid: (j['skipped_invalid'] as num).toInt(),
);

/// True if [certificateDerBytes]' SHA-256 hash matches
/// [expectedSha256Fingerprint] (hex, colons optional, case-insensitive). A
/// pure function separate from the `X509Certificate`-accepting callback
/// below so it can be tested with synthetic bytes, without a real TLS
/// handshake.
@visibleForTesting
bool matchesPinnedFingerprint(List<int> certificateDerBytes, String expectedSha256Fingerprint) {
  final expected = expectedSha256Fingerprint.toLowerCase().replaceAll(':', '');
  return sha256.convert(certificateDerBytes).toString() == expected;
}

/// [BunnyRepository] for networked mode: HTTPS against a `bunny_server`
/// instance, the exact same REST surface documented in `docs/
/// architecture.md`'s "C server (M5)" section. The server has no base path
/// prefix (e.g. `/accounts`, not `/api/v1/accounts`) and expects
/// `Authorization: Bearer <token>` on every request.
class HttpBunnyRepository implements BunnyRepository {
  final Uri _baseUrl;
  final String _bearerToken;
  final http.Client _client;

  /// Networked mode has no local cache of posts/searches/etc. to share a
  /// database with (everything else goes through the REST calls below) --
  /// the download queue (M62 follow-up) is the one piece of state this
  /// implementation still needs to persist on-device, so it gets its own
  /// small dedicated local `bunny_core`-backed db, opened lazily on first
  /// use via [_ensureDownloadQueueNative].
  final String _downloadQueueDbPath;
  final String _downloadQueueUserAgent;
  BunnyCoreNative? _downloadQueueNative;

  /// [certificateSha256Fingerprint] pins the server's self-signed
  /// certificate (hex, colons optional, case-insensitive) -- the server has
  /// no CA (see `docs/architecture.md`'s TLS section), so normal
  /// certificate-chain validation can't apply. Any certificate that doesn't
  /// match byte-for-byte is rejected.
  // The fields are private but the constructor's parameter names are the
  // deliberate public API, so `this._baseUrl`-style initializing formals
  // (which would require a leading-underscore parameter name) don't apply.
  HttpBunnyRepository({required Uri baseUrl, required String bearerToken, required String certificateSha256Fingerprint, required String downloadQueueDbPath, required String downloadQueueUserAgent})
    : _baseUrl = baseUrl, // ignore: prefer_initializing_formals
      _bearerToken = bearerToken, // ignore: prefer_initializing_formals
      _client = IOClient(HttpClient()..badCertificateCallback = _pinnedCertificateCallback(certificateSha256Fingerprint)),
      _downloadQueueDbPath = downloadQueueDbPath, // ignore: prefer_initializing_formals
      _downloadQueueUserAgent = downloadQueueUserAgent; // ignore: prefer_initializing_formals

  /// Injects a fake transport for tests -- fakes the transport, not the
  /// business logic, same approach as every C library's own tests. Skips
  /// certificate pinning entirely since a fake [http.Client] never performs
  /// a real TLS handshake. The download queue still goes through a real
  /// (in-memory) `bunny_core` db -- that part has nothing to do with HTTP.
  @visibleForTesting
  HttpBunnyRepository.withClient({required Uri baseUrl, required String bearerToken, required http.Client client, String downloadQueueDbPath = ':memory:', String downloadQueueUserAgent = 'bunny-tests/1.0 (unit tests)'})
    : _baseUrl = baseUrl, // ignore: prefer_initializing_formals
      _bearerToken = bearerToken, // ignore: prefer_initializing_formals
      _client = client, // ignore: prefer_initializing_formals
      _downloadQueueDbPath = downloadQueueDbPath, // ignore: prefer_initializing_formals
      _downloadQueueUserAgent = downloadQueueUserAgent; // ignore: prefer_initializing_formals

  static bool Function(X509Certificate cert, String host, int port) _pinnedCertificateCallback(String expectedFingerprint) {
    return (cert, host, port) => matchesPinnedFingerprint(cert.der, expectedFingerprint);
  }

  Future<BunnyCoreNative> _ensureDownloadQueueNative() async {
    final existing = _downloadQueueNative;
    if (existing != null) {
      return existing;
    }
    final native = BunnyCoreNative();
    await native.open(_downloadQueueDbPath, _downloadQueueUserAgent);
    _downloadQueueNative = native;
    return native;
  }

  @override
  Future<void> close() async {
    _client.close();
    await _downloadQueueNative?.close();
  }

  Uri _uri(String path, [Map<String, String>? query]) => _baseUrl.replace(path: path, queryParameters: query);

  Map<String, String> get _headers => {'Authorization': 'Bearer $_bearerToken', 'Content-Type': 'application/json'};

  Never _throwError(http.Response response) {
    var message = 'HTTP ${response.statusCode}';
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['error'] is String) {
        message = body['error'] as String;
      }
    } on FormatException {
      // Non-JSON error body -- fall back to the generic message above.
    }
    throw BunnyRepositoryException(message);
  }

  Map<String, Object?> _decodeObject(http.Response response) => jsonDecode(response.body) as Map<String, Object?>;

  List<Map<String, Object?>> _decodeList(http.Response response) => (jsonDecode(response.body) as List).cast<Map<String, Object?>>();

  @override
  Future<void> verifyAccount(BunnySite site, String username, String secret) async {
    final response = await _client.post(_uri('/accounts/verify'), headers: _headers, body: jsonEncode({'site': site.toWireString(), 'username': username, 'secret': secret}));
    if (response.statusCode != 200) {
      _throwError(response);
    }
  }

  @override
  Future<void> setAccount(BunnySite site, String username, String secret) async {
    final response = await _client.post(_uri('/accounts'), headers: _headers, body: jsonEncode({'site': site.toWireString(), 'username': username, 'secret': secret}));
    if (response.statusCode != 200) {
      _throwError(response);
    }
  }

  @override
  Future<BunnyAccount?> getAccount(BunnySite site) async {
    final response = await _client.get(_uri('/accounts/${site.toWireString()}'), headers: _headers);
    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode != 200) {
      _throwError(response);
    }
    return _accountFromJson(_decodeObject(response));
  }

  @override
  Future<void> deleteAccount(BunnySite site) async {
    final response = await _client.delete(_uri('/accounts/${site.toWireString()}'), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
  }

  @override
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
  }) async {
    final response = await _client.post(
      _uri('/searches'),
      headers: _headers,
      body: jsonEncode({
        'site': site.toWireString(),
        'label': label,
        'query': query,
        'interval_hours': intervalHours,
        'auto_favorite': autoFavorite,
        'auto_favorite_stars': autoFavoriteStars,
        'auto_upvote': autoUpvote,
        'uses_default_interval': usesDefaultInterval,
        'inkbunny_search_in_mask': inkbunnySearchInMask,
        'inkbunny_field_join_type': inkbunnyFieldJoinType,
        'inkbunny_string_join_type': inkbunnyStringJoinType,
        'inkbunny_username': inkbunnyUsername,
        'inkbunny_submission_type_mask': inkbunnySubmissionTypeMask,
        'inkbunny_days_limit': inkbunnyDaysLimit,
        'inkbunny_order_by': inkbunnyOrderBy,
        'inkbunny_random': inkbunnyRandom,
        'inkbunny_scraps': inkbunnyScraps,
      }),
    );
    if (response.statusCode != 201) {
      _throwError(response);
    }
    return (_decodeObject(response)['id'] as num).toInt();
  }

  @override
  Future<List<BunnySearch>> listSearches() async {
    final response = await _client.get(_uri('/searches'), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
    return _decodeList(response).map(_searchFromJson).toList();
  }

  @override
  Future<void> deleteSearch(int searchId) async {
    final response = await _client.delete(_uri('/searches/$searchId'), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
  }

  @override
  Future<void> setSearchPinned(int searchId, bool pinned) async {
    final response = await _client.post(_uri('/searches/$searchId/pin'), headers: _headers, body: jsonEncode({'pinned': pinned}));
    if (response.statusCode != 200) {
      _throwError(response);
    }
  }

  @override
  Future<void> mergeDuplicateSearch(int keeperId, int duplicateId) async {
    final response = await _client.post(_uri('/searches/$keeperId/merge_duplicate'), headers: _headers, body: jsonEncode({'duplicate_id': duplicateId}));
    if (response.statusCode != 200) {
      _throwError(response);
    }
  }

  @override
  Future<void> touchSearchViewed(int searchId) async {
    final response = await _client.post(_uri('/searches/$searchId/viewed'), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
  }

  @override
  Future<void> setSearchGroup(int searchId, int groupId) async {
    final response = await _client.post(_uri('/searches/$searchId/group'), headers: _headers, body: jsonEncode({'group_id': groupId}));
    if (response.statusCode != 200) {
      _throwError(response);
    }
  }

  @override
  Future<int> createGroup(String name, bool pinned) async {
    final response = await _client.post(_uri('/groups'), headers: _headers, body: jsonEncode({'name': name, 'pinned': pinned}));
    if (response.statusCode != 201) {
      _throwError(response);
    }
    return (_decodeObject(response)['id'] as num).toInt();
  }

  @override
  Future<List<BunnyGroup>> listGroups() async {
    final response = await _client.get(_uri('/groups'), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
    return _decodeList(response).map(_groupFromJson).toList();
  }

  @override
  Future<void> updateGroup(int groupId, String name, bool pinned) async {
    final response = await _client.put(_uri('/groups/$groupId'), headers: _headers, body: jsonEncode({'name': name, 'pinned': pinned}));
    if (response.statusCode != 200) {
      _throwError(response);
    }
  }

  @override
  Future<void> deleteGroup(int groupId) async {
    final response = await _client.delete(_uri('/groups/$groupId'), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
  }

  @override
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
  }) async {
    final response = await _client.put(
      _uri('/searches/$searchId'),
      headers: _headers,
      body: jsonEncode({
        'label': label,
        'query': query,
        'interval_hours': intervalHours,
        'auto_favorite': autoFavorite,
        'auto_favorite_stars': autoFavoriteStars,
        'auto_upvote': autoUpvote,
        'uses_default_interval': usesDefaultInterval,
        'inkbunny_search_in_mask': inkbunnySearchInMask,
        'inkbunny_field_join_type': inkbunnyFieldJoinType,
        'inkbunny_string_join_type': inkbunnyStringJoinType,
        'inkbunny_username': inkbunnyUsername,
        'inkbunny_submission_type_mask': inkbunnySubmissionTypeMask,
        'inkbunny_days_limit': inkbunnyDaysLimit,
        'inkbunny_order_by': inkbunnyOrderBy,
        'inkbunny_random': inkbunnyRandom,
        'inkbunny_scraps': inkbunnyScraps,
      }),
    );
    if (response.statusCode != 200) {
      _throwError(response);
    }
  }

  @override
  Future<int> getDefaultSyncIntervalHours() async {
    final response = await _client.get(_uri('/settings'), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
    return (_decodeObject(response)['default_sync_interval_hours'] as num).toInt();
  }

  @override
  Future<void> setDefaultSyncIntervalHours(int hours) async {
    final response = await _client.put(_uri('/settings'), headers: _headers, body: jsonEncode({'default_sync_interval_hours': hours}));
    if (response.statusCode != 200) {
      _throwError(response);
    }
  }

  @override
  Future<List<BunnyPost>> listSearchPosts(int searchId, {bool unseenOnly = false, int ratingMask = kRatingMaskAll, int mediaMask = kMediaMaskAll, int page = 1}) async {
    final response = await _client.get(
      _uri('/searches/$searchId/posts', {'unseen_only': unseenOnly.toString(), 'rating_mask': '$ratingMask', 'media_mask': '$mediaMask', 'page': '$page'}),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      _throwError(response);
    }
    return _decodeList(response).map(_postFromJson).toList();
  }

  @override
  Future<List<BunnyTagStat>> tagAutocomplete(BunnySite site, String prefix, {int limit = 10}) async {
    final response = await _client.get(_uri('/tags/autocomplete', {'site': site.toWireString(), 'prefix': prefix, 'limit': limit.toString()}), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
    return _decodeList(response).map(_tagStatFromJson).toList();
  }

  @override
  Future<BunnyStatsReport> getStatsReport() async {
    final response = await _client.get(_uri('/stats_report'), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
    return _statsReportFromJson(_decodeObject(response));
  }

  @override
  Future<BunnyStatsReport> refreshStatsReport() async {
    final response = await _client.post(_uri('/stats_report'), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
    return _statsReportFromJson(_decodeObject(response));
  }

  @override
  Future<void> markPostSeen(int postId) async {
    final response = await _client.post(_uri('/posts/$postId/seen'), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
  }

  @override
  Future<void> markAllSeen(int searchId) async {
    final response = await _client.post(_uri('/searches/$searchId/mark_all_seen'), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
  }

  @override
  Future<List<BunnyPostTag>> getPostTagsByCategory(int postId) async {
    final response = await _client.get(_uri('/posts/$postId/tags'), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
    return _decodeList(response).map(_postTagFromJson).toList();
  }

  @override
  Future<List<String>> getPostSources(int postId) async {
    final response = await _client.get(_uri('/posts/$postId/sources'), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
    return (jsonDecode(response.body) as List).cast<String>();
  }

  @override
  Future<List<BunnyPostFile>> getPostFiles(int postId) async {
    final response = await _client.get(_uri('/posts/$postId/files'), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
    return _decodeList(response).map(_postFileFromJson).toList();
  }

  @override
  Future<BunnyPostRelationships> getPostRelationships(int postId) async {
    final response = await _client.get(_uri('/posts/$postId/relationships'), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
    return _relationshipsFromJson(_decodeObject(response));
  }

  @override
  Future<List<int>> getPostPoolIds(int postId) async {
    final response = await _client.get(_uri('/posts/$postId/pools'), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
    return (jsonDecode(response.body) as List).map((e) => (e as num).toInt()).toList();
  }

  @override
  Future<List<BunnyInkbunnyPoolRef>> getInkbunnyPostPools(int postId) async {
    final response = await _client.get(_uri('/posts/$postId/inkbunny_pools'), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
    return (jsonDecode(response.body) as List).map((e) {
      final map = e as Map<String, dynamic>;
      return BunnyInkbunnyPoolRef(id: (map['pool_id'] as num).toInt(), name: map['name'] as String?);
    }).toList();
  }

  @override
  Future<String?> getInkbunnyPoolName(int poolId) async {
    final response = await _client.get(_uri('/inkbunny_pools/$poolId'), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
    return _decodeObject(response)['name'] as String?;
  }

  @override
  Future<int> fetchPost(BunnySite site, int externalId) async {
    final response = await _client.post(_uri('/posts/fetch', {'site': site.toWireString(), 'external_id': externalId.toString()}), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
    return (_decodeObject(response)['id'] as num).toInt();
  }

  @override
  Future<List<String>> getBlacklist(BunnySite site) async {
    final response = await _client.get(_uri('/blacklist', {'site': site.toWireString()}), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
    return (jsonDecode(response.body) as List).cast<String>();
  }

  @override
  Future<void> addBlacklistTag(BunnySite site, String tag) async {
    final response = await _client.post(_uri('/blacklist'), headers: _headers, body: jsonEncode({'site': site.toWireString(), 'tag': tag}));
    if (response.statusCode != 200) {
      _throwError(response);
    }
  }

  @override
  Future<void> removeBlacklistTag(BunnySite site, String tag) async {
    final response = await _client.delete(_uri('/blacklist', {'site': site.toWireString(), 'tag': tag}), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
  }

  @override
  Future<BunnyBlacklistSyncStats> syncE621Blacklist() async {
    final response = await _client.post(_uri('/blacklist/e621/sync'), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
    return _blacklistSyncStatsFromJson(_decodeObject(response));
  }

  @override
  Future<int?> validateTagQuery(BunnySite site, String text) async {
    final response = await _client.get(_uri('/tag_query/validate', {'site': site.toWireString(), 'text': text}), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
    final json = _decodeObject(response);
    return json['valid'] == true ? null : (json['error_pos'] as num).toInt();
  }

  @override
  Future<BunnyPoolInfo> fetchPool(int poolId) async {
    final response = await _client.get(_uri('/pools/$poolId'), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
    return _poolInfoFromJson(_decodeObject(response));
  }

  @override
  Future<BunnyPost> getPost(int postId) async {
    final response = await _client.get(_uri('/posts/$postId'), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
    return _postFromJson(_decodeObject(response));
  }

  @override
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
  }) async {
    final response = await _client.post(
      _uri('/search/preview', {
        'site': site.toWireString(),
        'query': query,
        'page': '$page',
        'ib_search_in_mask': '$inkbunnySearchInMask',
        'ib_field_join_type': '$inkbunnyFieldJoinType',
        'ib_string_join_type': '$inkbunnyStringJoinType',
        'ib_username': ?inkbunnyUsername,
        'ib_submission_type_mask': '$inkbunnySubmissionTypeMask',
        'ib_days_limit': '$inkbunnyDaysLimit',
        'ib_order_by': ?inkbunnyOrderBy,
        'ib_random': inkbunnyRandom ? '1' : '0',
        'ib_scraps': '$inkbunnyScraps',
      }),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      _throwError(response);
    }
    return _decodeList(response).map(_postFromJson).toList();
  }

  @override
  Future<List<BunnyPost>> myInkbunnyFavorites({int page = 1}) async {
    final response = await _client.post(_uri('/favorites/inkbunny/mine', {'page': '$page'}), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
    return _decodeList(response).map(_postFromJson).toList();
  }

  @override
  Future<List<BunnyComment>> getPostComments(int postId) async {
    final response = await _client.get(_uri('/posts/$postId/comments'), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
    return _decodeList(response).map(_commentFromJson).toList();
  }

  @override
  Future<List<BunnyTag>> searchTags(String nameMatches, {int limit = 0}) async {
    final response = await _client.get(_uri('/tags/search', {'name_matches': nameMatches, if (limit > 0) 'limit': '$limit'}), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
    return _decodeList(response).map(_tagFromJson).toList();
  }

  @override
  Future<BunnyWikiPage?> getWikiPage(String title) async {
    final response = await _client.get(_uri('/wiki_pages', {'title': title}), headers: _headers);
    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode != 200) {
      _throwError(response);
    }
    return _wikiPageFromJson(_decodeObject(response));
  }

  @override
  Future<List<BunnyTagAlias>> searchTagAliases(String nameMatches, {int limit = 0}) async {
    final response = await _client.get(_uri('/tag_aliases', {'name_matches': nameMatches, if (limit > 0) 'limit': '$limit'}), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
    return _decodeList(response).map(_tagAliasFromJson).toList();
  }

  @override
  Future<List<BunnyTagImplication>> searchTagImplications(String nameMatches, {int limit = 0}) async {
    final response = await _client.get(_uri('/tag_implications', {'name_matches': nameMatches, if (limit > 0) 'limit': '$limit'}), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
    return _decodeList(response).map(_tagImplicationFromJson).toList();
  }

  @override
  Future<void> syncDueSearches() async {
    final response = await _client.post(_uri('/sync'), headers: _headers);
    if (response.statusCode != 202) {
      _throwError(response);
    }
  }

  @override
  Future<void> syncSearch(int searchId) async {
    final response = await _client.post(_uri('/searches/$searchId/sync'), headers: _headers);
    if (response.statusCode != 202) {
      _throwError(response);
    }
  }

  @override
  Future<void> syncAllSearches() async {
    final response = await _client.post(_uri('/sync/all'), headers: _headers);
    if (response.statusCode != 202) {
      _throwError(response);
    }
  }

  @override
  Future<BunnySyncStatus> getSyncStatus() async {
    final response = await _client.get(_uri('/sync/status'), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
    final j = _decodeObject(response);
    return BunnySyncStatus(
      active: j['active'] as bool,
      source: j['source'] as String?,
      searchLabel: j['search_label'] as String?,
      position: (j['position'] as num).toInt(),
      total: (j['total'] as num).toInt(),
    );
  }

  @override
  Future<List<BunnyTask>> getTasks() async {
    final response = await _client.get(_uri('/tasks'), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
    final list = (_decodeObject(response)['tasks'] as List).cast<Map<String, Object?>>();
    return list
        .map(
          (e) => BunnyTask(
            id: (e['id'] as num).toInt(),
            priority: BunnyTaskPriority.fromWireString(e['priority'] as String),
            status: BunnyTaskStatus.fromWireString(e['status'] as String),
            label: e['label'] as String,
            enqueuedAt: DateTime.parse(e['enqueued_at'] as String),
          ),
        )
        .toList();
  }

  @override
  Future<List<BunnyTaskHistoryEntry>> getTaskHistory() async {
    final response = await _client.get(_uri('/tasks'), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
    final list = (_decodeObject(response)['history'] as List).cast<Map<String, Object?>>();
    return list
        .map(
          (e) => BunnyTaskHistoryEntry(
            id: (e['id'] as num).toInt(),
            priority: BunnyTaskPriority.fromWireString(e['priority'] as String),
            label: e['label'] as String,
            enqueuedAt: DateTime.parse(e['enqueued_at'] as String),
            finishedAt: DateTime.parse(e['finished_at'] as String),
            succeeded: e['succeeded'] as bool,
          ),
        )
        .toList();
  }

  @override
  Future<void> queueFavoriteAdd(int postId, {int? stars}) async {
    final response = await _client.post(_uri('/posts/$postId/favorite'), headers: _headers, body: stars == null ? null : jsonEncode({'stars': stars}));
    if (response.statusCode != 202) {
      _throwError(response);
    }
  }

  @override
  Future<void> queueFavoriteRemove(int postId) async {
    final response = await _client.delete(_uri('/posts/$postId/favorite'), headers: _headers);
    if (response.statusCode != 202) {
      _throwError(response);
    }
  }

  @override
  Future<void> queueVote(int postId, int score, {bool noUnvote = false}) async {
    final response = await _client.post(_uri('/posts/$postId/vote'), headers: _headers, body: jsonEncode({'score': score, 'no_unvote': noUnvote}));
    if (response.statusCode != 202) {
      _throwError(response);
    }
  }

  @override
  Future<void> queueComment(int postId, String body, {bool anonymous = false}) async {
    final response = await _client.post(_uri('/posts/$postId/comment'), headers: _headers, body: jsonEncode({'body': body, 'anonymous': anonymous}));
    if (response.statusCode != 202) {
      _throwError(response);
    }
  }

  @override
  Future<BunnyQueueStats> processQueue() async {
    final response = await _client.post(_uri('/queue/process'), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
    return _queueStatsFromJson(_decodeObject(response));
  }

  @override
  Future<int> downloadQueueAdd(int postId, {int poolId = 0, String? poolName, int poolPage = 0}) async {
    final native = await _ensureDownloadQueueNative();
    try {
      return await native.downloadQueueAdd(postId, poolId: poolId, poolName: poolName, poolPage: poolPage);
    } on BunnyCoreNativeException catch (e) {
      throw BunnyRepositoryException(e.message);
    }
  }

  @override
  Future<void> downloadQueueSetStatus(int id, String status, {String? failureReason}) async {
    final native = await _ensureDownloadQueueNative();
    try {
      await native.downloadQueueSetStatus(id, status, failureReason: failureReason);
    } on BunnyCoreNativeException catch (e) {
      throw BunnyRepositoryException(e.message);
    }
  }

  @override
  Future<List<DownloadQueueRecord>> downloadQueueList() async {
    final native = await _ensureDownloadQueueNative();
    try {
      final list = await native.downloadQueueList();
      return list
          .map(
            (m) => DownloadQueueRecord(
              id: m['id'] as int,
              postId: m['postId'] as int,
              status: m['status'] as String,
              failureReason: m['failureReason'] as String?,
              createdAt: m['createdAt'] as String,
              poolId: m['poolId'] as int,
              poolName: m['poolName'] as String?,
              poolPage: m['poolPage'] as int,
            ),
          )
          .toList(growable: false);
    } on BunnyCoreNativeException catch (e) {
      throw BunnyRepositoryException(e.message);
    }
  }

  @override
  Future<void> downloadQueueClearFinished() async {
    final native = await _ensureDownloadQueueNative();
    try {
      await native.downloadQueueClearFinished();
    } on BunnyCoreNativeException catch (e) {
      throw BunnyRepositoryException(e.message);
    }
  }

  @override
  Future<DownloadFetchResult> downloadFile(String fileUrl, Map<String, String> extraHeaders, String destDir, String filename, String? expectedMd5, void Function(int received, int? total) onProgress) async {
    final native = await _ensureDownloadQueueNative();
    return downloadFileViaNative(native, fileUrl, extraHeaders, destDir, filename, expectedMd5, onProgress);
  }

  @override
  Future<int> slideshowCreate(String label, {int? defaultPostsPerSearch, int? maxTotalPosts}) async {
    final response = await _client.post(
      _uri('/slideshows'),
      headers: _headers,
      body: jsonEncode({'label': label, 'default_posts_per_search': ?defaultPostsPerSearch, 'max_total_posts': ?maxTotalPosts}),
    );
    if (response.statusCode != 201) {
      _throwError(response);
    }
    return (_decodeObject(response)['id'] as num).toInt();
  }

  @override
  Future<void> slideshowUpdate(int slideshowId, String label, {int? defaultPostsPerSearch, int? maxTotalPosts}) async {
    final response = await _client.put(
      _uri('/slideshows/$slideshowId'),
      headers: _headers,
      body: jsonEncode({'label': label, 'default_posts_per_search': ?defaultPostsPerSearch, 'max_total_posts': ?maxTotalPosts}),
    );
    if (response.statusCode != 200) {
      _throwError(response);
    }
  }

  @override
  Future<void> slideshowDelete(int slideshowId) async {
    final response = await _client.delete(_uri('/slideshows/$slideshowId'), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
  }

  @override
  Future<List<BunnySlideshow>> slideshowList() async {
    final response = await _client.get(_uri('/slideshows'), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
    return _decodeList(response).map(_slideshowFromJson).toList();
  }

  @override
  Future<BunnySlideshow> slideshowGet(int slideshowId) async {
    final response = await _client.get(_uri('/slideshows/$slideshowId'), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
    return _slideshowFromJson(_decodeObject(response));
  }

  @override
  Future<void> slideshowSearchAdd(int slideshowId, int searchId, {int? overrideCount}) async {
    final response = await _client.post(
      _uri('/slideshows/$slideshowId/searches'),
      headers: _headers,
      body: jsonEncode({'search_id': searchId, 'override_count': ?overrideCount}),
    );
    if (response.statusCode != 201) {
      _throwError(response);
    }
  }

  @override
  Future<void> slideshowSearchRemove(int slideshowId, int searchId) async {
    final response = await _client.delete(_uri('/slideshows/$slideshowId/searches/$searchId'), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
  }

  @override
  Future<List<BunnySlideshowSearch>> slideshowSearchList(int slideshowId) async {
    final response = await _client.get(_uri('/slideshows/$slideshowId/searches'), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
    return _decodeList(response).map(_slideshowSearchFromJson).toList();
  }

  @override
  Future<List<BunnySlideshowPost>> slideshowPostsList(int slideshowId, {int? searchId}) async {
    final response = await _client.get(_uri('/slideshows/$slideshowId/posts', searchId != null ? {'search_id': '$searchId'} : null), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
    return _decodeList(response).map(_slideshowPostFromJson).toList();
  }

  @override
  Future<void> slideshowRerollAll(int slideshowId) async {
    final response = await _client.post(_uri('/slideshows/$slideshowId/reroll'), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
  }

  @override
  Future<void> slideshowRerollSearch(int slideshowId, int searchId) async {
    final response = await _client.post(_uri('/slideshows/$slideshowId/searches/$searchId/reroll'), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
  }

  @override
  Future<void> slideshowReplacePost(int slideshowId, int searchId, int deadPostId) async {
    final response = await _client.post(_uri('/slideshows/$slideshowId/searches/$searchId/replace'), headers: _headers, body: jsonEncode({'dead_post_id': deadPostId}));
    if (response.statusCode != 200) {
      _throwError(response);
    }
  }

  @override
  Future<List<String>> getSlideshowBlacklist(int slideshowId) async {
    final response = await _client.get(_uri('/slideshows/$slideshowId/blacklist'), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
    return (jsonDecode(response.body) as List).cast<String>();
  }

  @override
  Future<void> addSlideshowBlacklistTag(int slideshowId, String tag) async {
    final response = await _client.post(_uri('/slideshows/$slideshowId/blacklist'), headers: _headers, body: jsonEncode({'tag': tag}));
    if (response.statusCode != 200) {
      _throwError(response);
    }
  }

  @override
  Future<void> removeSlideshowBlacklistTag(int slideshowId, String tag) async {
    final response = await _client.delete(_uri('/slideshows/$slideshowId/blacklist', {'tag': tag}), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
  }

  /// Recent server log lines (oldest-first), for diagnosing a stuck/slow
  /// server without SSH access to the box -- see `server/src/log.c`. Not a
  /// [BunnyRepository] interface method, same reasoning as
  /// [checkServerConnection]'s doc comment: standalone/FFI mode has no
  /// server process to have logs from.
  Future<List<String>> getServerLogs() async {
    final response = await _client.get(_uri('/logs'), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
    return (jsonDecode(response.body) as List).cast<String>();
  }

  /// Renders this device's own already-configured connection info
  /// (server_url/bearer_token/cert_sha256, whatever the caller already has
  /// from [NetworkedConfig]) as a PNG QR code, via the server's `/qr`
  /// route (server/src/routes_qr.c) -- so a second device can scan it to
  /// connect, without this app needing its own QR-rendering library. Not a
  /// [BunnyRepository] interface method, same reasoning as
  /// [getServerLogs]'s doc comment above.
  Future<Uint8List> fetchConnectionQrPng({required Uri serverUrl, required String bearerToken, required String certSha256}) async {
    final response = await _client.post(
      _uri('/qr'),
      headers: _headers,
      body: jsonEncode({'server_url': serverUrl.toString(), 'bearer_token': bearerToken, 'cert_sha256': certSha256}),
    );
    if (response.statusCode != 200) {
      _throwError(response);
    }
    return response.bodyBytes;
  }
}
