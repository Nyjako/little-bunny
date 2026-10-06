import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/repository/bunny_repository.dart';
import 'package:little_bunny/repository/http_bunny_repository.dart';

String _colonize(String hex) => [for (var i = 0; i < hex.length; i += 2) hex.substring(i, i + 2)].join(':');

void main() {
  group('matchesPinnedFingerprint', () {
    test('accepts a matching fingerprint', () {
      final bytes = utf8.encode('fake certificate bytes');
      final fingerprint = sha256.convert(bytes).toString();

      expect(matchesPinnedFingerprint(bytes, fingerprint), isTrue);
    });

    test('is case-insensitive and ignores colons', () {
      const bytes = [1, 2, 3, 4];
      final fingerprint = sha256.convert(bytes).toString();

      expect(matchesPinnedFingerprint(bytes, _colonize(fingerprint.toUpperCase())), isTrue);
    });

    test('rejects a mismatched fingerprint', () {
      expect(matchesPinnedFingerprint(utf8.encode('actual cert'), sha256.convert(utf8.encode('different cert')).toString()), isFalse);
    });
  });

  group('HttpBunnyRepository', () {
    late Uri capturedUri;
    late String capturedMethod;
    late Map<String, String> capturedHeaders;
    late String capturedBody;
    late http.Response Function(http.Request) respond;

    HttpBunnyRepository buildRepository() => HttpBunnyRepository.withClient(
      baseUrl: Uri.parse('https://bunny.example:9443'),
      bearerToken: 'test-token',
      client: MockClient((request) async {
        capturedUri = request.url;
        capturedMethod = request.method;
        capturedHeaders = request.headers;
        capturedBody = request.body;
        return respond(request);
      }),
    );

    test('verifyAccount sends the right request and succeeds on 200', () async {
      respond = (_) => http.Response(jsonEncode({'ok': true}), 200);

      await buildRepository().verifyAccount(BunnySite.e621, 'someuser', 'somesecret');

      expect(capturedMethod, 'POST');
      expect(capturedUri.path, '/accounts/verify');
      expect(jsonDecode(capturedBody), {'site': 'e621', 'username': 'someuser', 'secret': 'somesecret'});
    });

    test('verifyAccount throws BunnyRepositoryException when the site rejects it', () async {
      respond = (_) => http.Response(jsonEncode({'error': 'an e621/Inkbunny client call failed (network, auth, ...)'}), 502);

      await expectLater(buildRepository().verifyAccount(BunnySite.e621, 'someuser', 'wrongsecret'), throwsA(isA<BunnyRepositoryException>()));
    });

    test('setAccount sends the right request and succeeds on 200', () async {
      respond = (_) => http.Response(jsonEncode({'ok': true}), 200);

      await buildRepository().setAccount(BunnySite.e621, 'someuser', 'somesecret');

      expect(capturedMethod, 'POST');
      expect(capturedUri.path, '/accounts');
      expect(capturedHeaders['authorization'], 'Bearer test-token');
      expect(capturedHeaders['content-type'], 'application/json');
      expect(jsonDecode(capturedBody), {'site': 'e621', 'username': 'someuser', 'secret': 'somesecret'});
    });

    test('getAccount maps a 200 response into a BunnyAccount', () async {
      respond = (_) => http.Response(jsonEncode({'id': 1, 'site': 'e621', 'username': 'someuser', 'created_at': '2026-01-01T00:00:00Z'}), 200);

      final account = await buildRepository().getAccount(BunnySite.e621);

      expect(capturedMethod, 'GET');
      expect(capturedUri.path, '/accounts/e621');
      expect(account, isNotNull);
      expect(account!.id, 1);
      expect(account.site, BunnySite.e621);
      expect(account.username, 'someuser');
      expect(account.createdAt, '2026-01-01T00:00:00Z');
    });

    test('getAccount returns null on 404', () async {
      respond = (_) => http.Response(jsonEncode({'error': 'not found'}), 404);

      expect(await buildRepository().getAccount(BunnySite.e621), isNull);
    });

    test('deleteAccount succeeds on 200', () async {
      respond = (_) => http.Response(jsonEncode({'ok': true}), 200);

      await buildRepository().deleteAccount(BunnySite.inkbunny);

      expect(capturedMethod, 'DELETE');
      expect(capturedUri.path, '/accounts/inkbunny');
    });

    test('createSearch sends interval_hours and returns the new id', () async {
      respond = (_) => http.Response(jsonEncode({'id': 42}), 201);

      final id = await buildRepository().createSearch(BunnySite.e621, 'my search', 'rating:safe', intervalHours: 12);

      expect(capturedMethod, 'POST');
      expect(capturedUri.path, '/searches');
      expect(jsonDecode(capturedBody), {'site': 'e621', 'label': 'my search', 'query': 'rating:safe', 'interval_hours': 12, 'auto_favorite': false});
      expect(id, 42);
    });

    test('createSearch sends the given auto_favorite value', () async {
      respond = (_) => http.Response(jsonEncode({'id': 42}), 201);

      await buildRepository().createSearch(BunnySite.e621, 'my search', 'rating:safe', autoFavorite: true);

      expect(jsonDecode(capturedBody), containsPair('auto_favorite', true));
    });

    test('listSearches maps a JSON array into BunnySearch objects', () async {
      respond = (_) => http.Response(
        jsonEncode([
          {'id': 1, 'site': 'e621', 'label': 'my search', 'query': 'rating:safe', 'interval_hours': 24, 'created_at': '2026-01-01T00:00:00Z', 'last_run_at': null, 'unseen_count': 3, 'auto_favorite': true},
        ]),
        200,
      );

      final searches = await buildRepository().listSearches();

      expect(searches, hasLength(1));
      expect(searches.single.id, 1);
      expect(searches.single.label, 'my search');
      expect(searches.single.lastRunAt, isNull);
      expect(searches.single.unseenCount, 3);
      expect(searches.single.autoFavorite, isTrue);
    });

    test('deleteSearch sends DELETE to the right path', () async {
      respond = (_) => http.Response(jsonEncode({'ok': true}), 200);

      await buildRepository().deleteSearch(7);

      expect(capturedMethod, 'DELETE');
      expect(capturedUri.path, '/searches/7');
    });

    test('setSearchAutoFavorite sends POST with the new value', () async {
      respond = (_) => http.Response(jsonEncode({'ok': true}), 200);

      await buildRepository().setSearchAutoFavorite(7, true);

      expect(capturedMethod, 'POST');
      expect(capturedUri.path, '/searches/7/auto_favorite');
      expect(jsonDecode(capturedBody), {'auto_favorite': true});
    });

    test('listSearchPosts sends unseen_only as a query parameter', () async {
      respond = (_) => http.Response(jsonEncode([]), 200);

      await buildRepository().listSearchPosts(7, unseenOnly: true);

      expect(capturedMethod, 'GET');
      expect(capturedUri.path, '/searches/7/posts');
      expect(capturedUri.queryParameters['unseen_only'], 'true');
    });

    test('listSearchPosts maps a JSON array into BunnyPost objects', () async {
      respond = (_) => http.Response(
        jsonEncode([
          {
            'id': 1,
            'site': 'e621',
            'external_id': 100,
            'artist': 'someartist',
            'title': null,
            'description': null,
            'rating': 's',
            'score': 5,
            'score_up': 6,
            'score_down': 1,
            'fav_count': 2,
            'comment_count': 0,
            'file_url': 'https://example.com/1.png',
            'file_ext': 'png',
            'file_md5': 'abc',
            'preview_url': null,
            'width': 100,
            'height': 200,
            'created_at_site': null,
            'cached_at': '2026-01-01T00:00:00Z',
            'is_seen': false,
            'is_favorited': true,
            'user_vote': 1,
            'sample_url': 'https://example.com/1_sample.png',
          },
        ]),
        200,
      );

      final posts = await buildRepository().listSearchPosts(7);

      expect(posts, hasLength(1));
      expect(posts.single.externalId, 100);
      expect(posts.single.isFavorited, isTrue);
      expect(posts.single.title, isNull);
      expect(posts.single.scoreUp, 6);
      expect(posts.single.scoreDown, 1);
      expect(posts.single.sampleUrl, 'https://example.com/1_sample.png');
      expect(posts.single.userVote, 1);
    });

    test('tagAutocomplete sends site/prefix/limit as query params and maps results', () async {
      respond = (_) => http.Response(
        jsonEncode([
          {'name': 'one', 'count': 3},
          {'name': 'onomatopoeia', 'count': 1},
        ]),
        200,
      );

      final stats = await buildRepository().tagAutocomplete(BunnySite.e621, 'on', limit: 5);

      expect(capturedMethod, 'GET');
      expect(capturedUri.path, '/tags/autocomplete');
      expect(capturedUri.queryParameters, {'site': 'e621', 'prefix': 'on', 'limit': '5'});
      expect(stats, hasLength(2));
      expect(stats.first.name, 'one');
      expect(stats.first.count, 3);
    });

    test('getPostTagsByCategory sends GET to the right path and maps results', () async {
      respond = (_) => http.Response(
        jsonEncode([
          {'name': 'one', 'category': 'general'},
          {'name': 'someartist', 'category': 'artist'},
          {'name': 'some_keyword', 'category': null},
        ]),
        200,
      );

      final tags = await buildRepository().getPostTagsByCategory(5);

      expect(capturedMethod, 'GET');
      expect(capturedUri.path, '/posts/5/tags');
      expect(tags, hasLength(3));
      expect(tags[0].name, 'one');
      expect(tags[0].category, 'general');
      expect(tags[2].category, isNull);
    });

    test('getPostSources sends GET to the right path and returns a list of strings', () async {
      respond = (_) => http.Response(jsonEncode(['https://example.com/a', 'https://example.com/b']), 200);

      final sources = await buildRepository().getPostSources(5);

      expect(capturedMethod, 'GET');
      expect(capturedUri.path, '/posts/5/sources');
      expect(sources, ['https://example.com/a', 'https://example.com/b']);
    });

    test('getPostRelationships sends GET to the right path and maps the response', () async {
      respond = (_) => http.Response(
        jsonEncode({'has_parent': true, 'parent_external_id': 999, 'has_active_children': true, 'children': [101, 102]}),
        200,
      );

      final relationships = await buildRepository().getPostRelationships(5);

      expect(capturedMethod, 'GET');
      expect(capturedUri.path, '/posts/5/relationships');
      expect(relationships.hasParent, isTrue);
      expect(relationships.parentExternalId, 999);
      expect(relationships.hasActiveChildren, isTrue);
      expect(relationships.children, [101, 102]);
    });

    test('getPostPoolIds sends GET to the right path and returns a list of ints', () async {
      respond = (_) => http.Response(jsonEncode([5, 9]), 200);

      final poolIds = await buildRepository().getPostPoolIds(5);

      expect(capturedMethod, 'GET');
      expect(capturedUri.path, '/posts/5/pools');
      expect(poolIds, [5, 9]);
    });

    test('fetchPost sends POST with site/external_id query params and returns the id', () async {
      respond = (_) => http.Response(jsonEncode({'id': 7}), 200);

      final postId = await buildRepository().fetchPost(BunnySite.e621, 42);

      expect(capturedMethod, 'POST');
      expect(capturedUri.path, '/posts/fetch');
      expect(capturedUri.queryParameters, {'site': 'e621', 'external_id': '42'});
      expect(postId, 7);
    });

    test('fetchPool sends GET to the right path and maps the response', () async {
      respond = (_) => http.Response(jsonEncode({'id': 5, 'name': 'a_test_pool', 'post_count': 3}), 200);

      final info = await buildRepository().fetchPool(5);

      expect(capturedMethod, 'GET');
      expect(capturedUri.path, '/pools/5');
      expect(info.id, 5);
      expect(info.name, 'a_test_pool');
      expect(info.postCount, 3);
    });

    test('getPost sends GET to the right path and maps the response', () async {
      respond = (_) => http.Response(
        jsonEncode({
          'id': 2,
          'site': 'e621',
          'external_id': 42,
          'artist': 'anotherartist',
          'title': null,
          'description': null,
          'rating': 's',
          'score': 1,
          'score_up': 2,
          'score_down': 1,
          'fav_count': 0,
          'comment_count': 0,
          'file_url': 'https://example.com/2.png',
          'file_ext': 'png',
          'file_md5': 'def',
          'preview_url': null,
          'width': 50,
          'height': 60,
          'created_at_site': null,
          'cached_at': '2026-01-01T00:00:00Z',
          'is_seen': false,
          'is_favorited': false,
          'user_vote': 0,
          'sample_url': null,
        }),
        200,
      );

      final post = await buildRepository().getPost(2);

      expect(capturedMethod, 'GET');
      expect(capturedUri.path, '/posts/2');
      expect(post.id, 2);
      expect(post.externalId, 42);
      expect(post.artist, 'anotherartist');
    });

    test('previewSearch sends POST with site/query query params and maps the response', () async {
      respond = (_) => http.Response(
        jsonEncode([
          {
            'id': 1,
            'site': 'e621',
            'external_id': 7,
            'artist': 'someartist',
            'title': null,
            'description': null,
            'rating': 's',
            'score': 5,
            'score_up': 5,
            'score_down': 0,
            'fav_count': 2,
            'comment_count': 0,
            'file_url': 'https://example.com/7.png',
            'file_ext': 'png',
            'file_md5': 'abc',
            'preview_url': null,
            'width': 100,
            'height': 200,
            'created_at_site': null,
            'cached_at': '2026-01-01T00:00:00Z',
            'is_seen': false,
            'is_favorited': false,
            'user_vote': 0,
            'sample_url': null,
          },
        ]),
        200,
      );

      final posts = await buildRepository().previewSearch(BunnySite.e621, 'someartist');

      expect(capturedMethod, 'POST');
      expect(capturedUri.path, '/search/preview');
      expect(capturedUri.queryParameters, {'site': 'e621', 'query': 'someartist', 'page': '1'});
      expect(posts, hasLength(1));
      expect(posts.single.externalId, 7);
    });

    test('previewSearch sends the given page number', () async {
      respond = (_) => http.Response(jsonEncode(<Object?>[]), 200);

      await buildRepository().previewSearch(BunnySite.e621, 'someartist', page: 3);

      expect(capturedUri.queryParameters, {'site': 'e621', 'query': 'someartist', 'page': '3'});
    });

    test('getPostComments sends GET to the right path and maps the response', () async {
      respond = (_) => http.Response(
        jsonEncode([
          {'id': 1, 'creator_name': 'someone', 'body': 'Nice pic!', 'created_at': '2026-01-01T00:00:00Z'},
        ]),
        200,
      );

      final comments = await buildRepository().getPostComments(2);

      expect(capturedMethod, 'GET');
      expect(capturedUri.path, '/posts/2/comments');
      expect(comments, hasLength(1));
      expect(comments.single.creatorName, 'someone');
      expect(comments.single.body, 'Nice pic!');
    });

    test('recordDownload sends POST with the download fields and returns the new id', () async {
      respond = (_) => http.Response(jsonEncode({'id': 9}), 200);

      final id = await buildRepository().recordDownload(2, '/downloads/wolf/1.png', checksumMd5: 'aaa', verified: true);

      expect(capturedMethod, 'POST');
      expect(capturedUri.path, '/posts/2/downloads');
      expect(jsonDecode(capturedBody), {'file_path': '/downloads/wolf/1.png', 'checksum_md5': 'aaa', 'verified': true});
      expect(id, 9);
    });

    test('listDownloadsForPost sends GET to the right path and maps the response', () async {
      respond = (_) => http.Response(
        jsonEncode([
          {'id': 9, 'post_id': 2, 'file_path': '/downloads/wolf/1.png', 'checksum_md5': 'aaa', 'checksum_verified': true, 'downloaded_at': '2026-01-01T00:00:00Z'},
        ]),
        200,
      );

      final downloads = await buildRepository().listDownloadsForPost(2);

      expect(capturedMethod, 'GET');
      expect(capturedUri.path, '/posts/2/downloads');
      expect(downloads, hasLength(1));
      expect(downloads.single.filePath, '/downloads/wolf/1.png');
      expect(downloads.single.checksumVerified, isTrue);
    });

    test('markPostSeen sends POST to the right path', () async {
      respond = (_) => http.Response(jsonEncode({'ok': true}), 200);

      await buildRepository().markPostSeen(5);

      expect(capturedMethod, 'POST');
      expect(capturedUri.path, '/posts/5/seen');
    });

    test('markAllSeen sends POST to the right path', () async {
      respond = (_) => http.Response(jsonEncode({'ok': true}), 200);

      await buildRepository().markAllSeen(7);

      expect(capturedMethod, 'POST');
      expect(capturedUri.path, '/searches/7/mark_all_seen');
    });

    test('syncDueSearches maps the stats response', () async {
      respond = (_) => http.Response(jsonEncode({'searches_checked': 3, 'searches_synced': 2, 'posts_upserted': 10}), 200);

      final stats = await buildRepository().syncDueSearches();

      expect(capturedMethod, 'POST');
      expect(capturedUri.path, '/sync');
      expect(stats.searchesChecked, 3);
      expect(stats.searchesSynced, 2);
      expect(stats.postsUpserted, 10);
    });

    test('queueFavoriteAdd omits the body when stars is null', () async {
      respond = (_) => http.Response(jsonEncode({'queued': true}), 202);

      await buildRepository().queueFavoriteAdd(5);

      expect(capturedMethod, 'POST');
      expect(capturedUri.path, '/posts/5/favorite');
      expect(capturedBody, isEmpty);
    });

    test('queueFavoriteAdd sends stars when given', () async {
      respond = (_) => http.Response(jsonEncode({'queued': true}), 202);

      await buildRepository().queueFavoriteAdd(5, stars: 3);

      expect(jsonDecode(capturedBody), {'stars': 3});
    });

    test('queueFavoriteRemove sends DELETE', () async {
      respond = (_) => http.Response(jsonEncode({'queued': true}), 202);

      await buildRepository().queueFavoriteRemove(5);

      expect(capturedMethod, 'DELETE');
      expect(capturedUri.path, '/posts/5/favorite');
    });

    test('queueVote sends score and no_unvote', () async {
      respond = (_) => http.Response(jsonEncode({'queued': true}), 202);

      await buildRepository().queueVote(5, 1, noUnvote: true);

      expect(capturedUri.path, '/posts/5/vote');
      expect(jsonDecode(capturedBody), {'score': 1, 'no_unvote': true});
    });

    test('queueComment sends body and anonymous', () async {
      respond = (_) => http.Response(jsonEncode({'queued': true}), 202);

      await buildRepository().queueComment(5, 'nice post', anonymous: true);

      expect(capturedUri.path, '/posts/5/comment');
      expect(jsonDecode(capturedBody), {'body': 'nice post', 'anonymous': true});
    });

    test('processQueue maps the stats response', () async {
      respond = (_) => http.Response(jsonEncode({'actions_processed': 4, 'actions_succeeded': 3, 'actions_failed': 1}), 200);

      final stats = await buildRepository().processQueue();

      expect(capturedUri.path, '/queue/process');
      expect(stats.actionsProcessed, 4);
      expect(stats.actionsSucceeded, 3);
      expect(stats.actionsFailed, 1);
    });

    test('a JSON error body surfaces its message in BunnyRepositoryException', () async {
      respond = (_) => http.Response(jsonEncode({'error': 'missing or invalid bearer token'}), 401);

      await expectLater(buildRepository().setAccount(BunnySite.e621, 'u', 's'), throwsA(isA<BunnyRepositoryException>().having((e) => e.message, 'message', 'missing or invalid bearer token')));
    });

    test('a non-JSON error body falls back to a generic message', () async {
      respond = (_) => http.Response('not json', 500);

      await expectLater(buildRepository().setAccount(BunnySite.e621, 'u', 's'), throwsA(isA<BunnyRepositoryException>().having((e) => e.message, 'message', 'HTTP 500')));
    });
  });
}
