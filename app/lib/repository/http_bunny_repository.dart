import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:meta/meta.dart';

import 'bunny_models.dart';
import 'bunny_repository.dart';

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
  unseenCount: (j['unseen_count'] as num).toInt(),
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
  scoreUp: (j['score_up'] as num).toInt(),
  scoreDown: (j['score_down'] as num).toInt(),
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
);

BunnyTagStat _tagStatFromJson(Map<String, Object?> j) => BunnyTagStat(name: j['name'] as String, count: (j['count'] as num).toInt());

BunnySyncStats _syncStatsFromJson(Map<String, Object?> j) => BunnySyncStats(
  searchesChecked: (j['searches_checked'] as num).toInt(),
  searchesSynced: (j['searches_synced'] as num).toInt(),
  postsUpserted: (j['posts_upserted'] as num).toInt(),
);

BunnyQueueStats _queueStatsFromJson(Map<String, Object?> j) => BunnyQueueStats(
  actionsProcessed: (j['actions_processed'] as num).toInt(),
  actionsSucceeded: (j['actions_succeeded'] as num).toInt(),
  actionsFailed: (j['actions_failed'] as num).toInt(),
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

  /// [certificateSha256Fingerprint] pins the server's self-signed
  /// certificate (hex, colons optional, case-insensitive) -- the server has
  /// no CA (see `docs/architecture.md`'s TLS section), so normal
  /// certificate-chain validation can't apply. Any certificate that doesn't
  /// match byte-for-byte is rejected.
  // The fields are private but the constructor's parameter names are the
  // deliberate public API, so `this._baseUrl`-style initializing formals
  // (which would require a leading-underscore parameter name) don't apply.
  HttpBunnyRepository({required Uri baseUrl, required String bearerToken, required String certificateSha256Fingerprint})
    : _baseUrl = baseUrl, // ignore: prefer_initializing_formals
      _bearerToken = bearerToken, // ignore: prefer_initializing_formals
      _client = IOClient(HttpClient()..badCertificateCallback = _pinnedCertificateCallback(certificateSha256Fingerprint));

  /// Injects a fake transport for tests -- fakes the transport, not the
  /// business logic, same approach as every C library's own tests. Skips
  /// certificate pinning entirely since a fake [http.Client] never performs
  /// a real TLS handshake.
  @visibleForTesting
  HttpBunnyRepository.withClient({required Uri baseUrl, required String bearerToken, required http.Client client})
    : _baseUrl = baseUrl, // ignore: prefer_initializing_formals
      _bearerToken = bearerToken, // ignore: prefer_initializing_formals
      _client = client; // ignore: prefer_initializing_formals

  static bool Function(X509Certificate cert, String host, int port) _pinnedCertificateCallback(String expectedFingerprint) {
    return (cert, host, port) => matchesPinnedFingerprint(cert.der, expectedFingerprint);
  }

  void close() => _client.close();

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
  Future<int> createSearch(BunnySite site, String label, String query, {int intervalHours = 24}) async {
    final response = await _client.post(_uri('/searches'), headers: _headers, body: jsonEncode({'site': site.toWireString(), 'label': label, 'query': query, 'interval_hours': intervalHours}));
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
  Future<List<BunnyPost>> listSearchPosts(int searchId, {bool unseenOnly = false}) async {
    final response = await _client.get(_uri('/searches/$searchId/posts', {'unseen_only': unseenOnly.toString()}), headers: _headers);
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
  Future<void> markPostSeen(int postId) async {
    final response = await _client.post(_uri('/posts/$postId/seen'), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
  }

  @override
  Future<BunnySyncStats> syncDueSearches() async {
    final response = await _client.post(_uri('/sync'), headers: _headers);
    if (response.statusCode != 200) {
      _throwError(response);
    }
    return _syncStatsFromJson(_decodeObject(response));
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
}
