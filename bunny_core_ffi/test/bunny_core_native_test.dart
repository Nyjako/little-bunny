import 'dart:io';

import 'package:bunny_core_ffi/bunny_core_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

// Runs against the real compiled bunny_core_ffi shared library (built for the
// host platform by `flutter test`'s ffiPlugin support), backed by an
// in-memory SQLite database -- real behavior over a fake, same approach as
// bunny_db's own C tests.
void main() {
  late BunnyCoreNative native;

  setUp(() async {
    native = BunnyCoreNative();
    await native.open(':memory:', 'bunny_core_ffi_test/0.0.1');
  });

  tearDown(() => native.close());

  test('getAccount returns null when none is configured', () async {
    expect(await native.getAccount('e621'), isNull);
  });

  test('setAccount then getAccount round-trips (without the secret)', () async {
    await native.setAccount('e621', 'someuser', 'somesecret');

    final account = await native.getAccount('e621');

    expect(account, isNotNull);
    expect(account!['site'], 'e621');
    expect(account['username'], 'someuser');
    expect(account.containsKey('secret'), isFalse);
  });

  test('deleteAccount removes it', () async {
    await native.setAccount('e621', 'someuser', 'somesecret');
    await native.deleteAccount('e621');

    expect(await native.getAccount('e621'), isNull);
  });

  test('createSearch then listSearches round-trips', () async {
    final id = await native.createSearch('e621', 'my search', 'rating:safe', 24);

    final searches = await native.listSearches();

    expect(searches, hasLength(1));
    expect(searches.single['id'], id);
    expect(searches.single['label'], 'my search');
    expect(searches.single['query'], 'rating:safe');
    expect(searches.single['intervalHours'], 24);
    // Only ever set by a sync that actually finds a new post (M69) -- never
    // populated here, no sync has run.
    expect(searches.single['lastUpdatedAt'], isNull);
  });

  test('createGroup then listGroups round-trips, and setSearchGroup/deleteGroup ungroups', () async {
    final groupId = await native.createGroup('Wolves', true);
    var groups = await native.listGroups();
    expect(groups, hasLength(1));
    expect(groups.single['id'], groupId);
    expect(groups.single['name'], 'Wolves');
    expect(groups.single['pinned'], isTrue);

    await native.updateGroup(groupId, 'Canines', false);
    groups = await native.listGroups();
    expect(groups.single['name'], 'Canines');
    expect(groups.single['pinned'], isFalse);

    final searchId = await native.createSearch('e621', 'my search', 'rating:safe', 24);
    var searches = await native.listSearches();
    expect(searches.single['groupId'], 0);

    await native.setSearchGroup(searchId, groupId);
    searches = await native.listSearches();
    expect(searches.single['groupId'], groupId);

    await native.deleteGroup(groupId);
    expect(await native.listGroups(), isEmpty);
    searches = await native.listSearches();
    expect(searches.single['groupId'], 0);
  });

  test('deleteSearch removes it', () async {
    final id = await native.createSearch('e621', 'my search', 'rating:safe', 24);
    await native.deleteSearch(id);

    expect(await native.listSearches(), isEmpty);
  });

  test('mergeDuplicateSearch deletes the duplicate and keeps the keeper', () async {
    final keeperId = await native.createSearch('e621', 'wolves', 'wolf', 24);
    final duplicateId = await native.createSearch('e621', 'wolves (dupe)', 'wolf', 48);

    await native.mergeDuplicateSearch(keeperId, duplicateId);

    final searches = await native.listSearches();
    expect(searches.single['id'], keeperId);
  });

  test('listSearchPosts is empty for a freshly created search', () async {
    final id = await native.createSearch('e621', 'my search', 'rating:safe', 24);

    // 15/7 == BUNNY_DB_RATING_MASK_ALL/BUNNY_DB_MEDIA_MASK_ALL (unfiltered).
    expect(await native.listSearchPosts(id, false, 15, 7, 1), isEmpty);
  });

  test('slideshowPickPostsForSearch is empty for a freshly created search (M51 v2)', () async {
    final id = await native.createSearch('e621', 'wolves', 'wolf', 24);

    // 15/7 == BUNNY_DB_RATING_MASK_ALL/BUNNY_DB_MEDIA_MASK_ALL (unfiltered).
    expect(await native.slideshowPickPostsForSearch(id, 10, [], 15, 7), isEmpty);
  });

  test('slideshowPickPostsForSearch rejects a nonexistent search id (M51 v2)', () async {
    await expectLater(native.slideshowPickPostsForSearch(999999, 10, [], 15, 7), throwsA(isA<BunnyCoreNativeException>()));
  });

  test('slideshowCreate/slideshowList/slideshowGet/slideshowUpdate/slideshowDelete round-trip (M51 v2)', () async {
    final id = await native.slideshowCreate('my slideshow', 5, null);

    var slideshows = await native.slideshowList();
    expect(slideshows, hasLength(1));
    expect(slideshows.single['id'], id);
    expect(slideshows.single['label'], 'my slideshow');
    expect(slideshows.single['defaultPostsPerSearch'], 5);
    expect(slideshows.single['maxTotalPosts'], isNull);

    await native.slideshowUpdate(id, 'renamed', null, 10);
    final slideshow = await native.slideshowGet(id);
    expect(slideshow['label'], 'renamed');
    expect(slideshow['defaultPostsPerSearch'], isNull);
    expect(slideshow['maxTotalPosts'], 10);

    await native.slideshowDelete(id);
    expect(await native.slideshowList(), isEmpty);
  });

  test('slideshowSearchAdd/slideshowSearchCommitPicks/slideshowPostsList/slideshowSearchRemove round-trip (M51 v2)', () async {
    final searchId = await native.createSearch('e621', 'wolves', 'wolf', 24);
    final slideshowId = await native.slideshowCreate('my slideshow', null, null);

    await native.slideshowSearchAdd(slideshowId, searchId, 3);
    var links = await native.slideshowSearchList(slideshowId);
    expect(links, hasLength(1));
    expect(links.single['searchId'], searchId);
    expect(links.single['overrideCount'], 3);

    // Nothing's actually been synced for this search, so there's nothing to
    // commit -- this just proves the round trip doesn't throw.
    await native.slideshowSearchCommitPicks(slideshowId, searchId);
    expect(await native.slideshowPostsList(slideshowId, 0), isEmpty);

    await native.slideshowRerollAll(slideshowId);
    await native.slideshowRerollSearch(slideshowId, searchId);

    await native.slideshowSearchRemove(slideshowId, searchId);
    expect(await native.slideshowSearchList(slideshowId), isEmpty);
  });

  test('slideshowBlacklistAdd/slideshowBlacklistList/slideshowBlacklistRemove round-trip', () async {
    final slideshowId = await native.slideshowCreate('my slideshow', null, null);

    expect(await native.slideshowBlacklistList(slideshowId), isEmpty);

    await native.slideshowBlacklistAdd(slideshowId, 'comic');
    await native.slideshowBlacklistAdd(slideshowId, 'gore');
    expect(await native.slideshowBlacklistList(slideshowId), ['comic', 'gore']); // alphabetical

    await native.slideshowBlacklistRemove(slideshowId, 'comic');
    expect(await native.slideshowBlacklistList(slideshowId), ['gore']);
  });

  test('slideshowReplacePost throws when the search has nothing to replace with (M51 v2)', () async {
    final searchId = await native.createSearch('e621', 'wolves', 'wolf', 24);
    final slideshowId = await native.slideshowCreate('my slideshow', null, null);
    await native.slideshowSearchAdd(slideshowId, searchId, null);

    await expectLater(native.slideshowReplacePost(slideshowId, searchId, 1), throwsA(isA<BunnyCoreNativeException>()));
  });

  test('syncDueSearches with no searches is a no-op', () async {
    final stats = await native.syncDueSearches();

    expect(stats['searchesChecked'], 0);
    expect(stats['searchesSynced'], 0);
    expect(stats['postsUpserted'], 0);
  });

  test('processQueue with nothing queued is a no-op', () async {
    final stats = await native.processQueue();

    expect(stats['actionsProcessed'], 0);
    expect(stats['actionsSucceeded'], 0);
    expect(stats['actionsFailed'], 0);
  });

  test('downloadQueueAdd/downloadQueueList/downloadQueueSetStatus/downloadQueueClearFinished round-trip', () async {
    // No posts(id) foreign key on this table (unlike queueFavoriteAdd below)
    // -- a networked-mode client's own dedicated local db never has a
    // populated posts table, so an arbitrary post id must be accepted here.
    final id = await native.downloadQueueAdd(42);
    expect(id, greaterThan(0));

    var items = await native.downloadQueueList();
    expect(items, hasLength(1));
    expect(items[0]['id'], id);
    expect(items[0]['postId'], 42);
    expect(items[0]['status'], 'queued');
    expect(items[0]['failureReason'], isNull);
    expect(items[0]['poolId'], 0);
    expect(items[0]['poolName'], isNull);
    expect(items[0]['poolPage'], 0);

    await native.downloadQueueSetStatus(id, 'failed', failureReason: 'HTTP 500');
    items = await native.downloadQueueList();
    expect(items[0]['status'], 'failed');
    expect(items[0]['failureReason'], 'HTTP 500');

    await native.downloadQueueClearFinished();
    expect(await native.downloadQueueList(), isEmpty);
  });

  test('downloadQueueAdd persists pool context (M65)', () async {
    final id = await native.downloadQueueAdd(99, poolId: 1234, poolName: 'My Comic', poolPage: 7);

    final items = await native.downloadQueueList();
    expect(items, hasLength(1));
    expect(items[0]['id'], id);
    expect(items[0]['poolId'], 1234);
    expect(items[0]['poolName'], 'My Comic');
    expect(items[0]['poolPage'], 7);
  });

  test('downloadStart/downloadPoll/downloadRelease round-trips a real fetch (M66)', () async {
    const body = 'the quick brown fox jumps over the lazy dog';
    final server = await HttpServer.bind('127.0.0.1', 0);
    final tempDir = await Directory.systemTemp.createTemp('bunny_core_ffi_download_test');
    try {
      server.listen((request) async {
        request.response.statusCode = 200;
        request.response.write(body);
        await request.response.close();
      });

      final handle = await native.downloadStart('http://127.0.0.1:${server.port}/', const {}, tempDir.path, 'test.bin', null);
      expect(handle, greaterThanOrEqualTo(0));

      Map<String, Object?> result;
      do {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        result = await native.downloadPoll(handle);
      } while (result['done'] != true);
      await native.downloadRelease(handle);

      expect(result['outcome'], 'verified');
      expect(result['received'], body.length);
      expect(await File('${tempDir.path}/test.bin').readAsString(), body);
    } finally {
      await server.close(force: true);
      await tempDir.delete(recursive: true);
    }
  });

  test('downloadStart skips the fetch when a verified file already exists (M66)', () async {
    const body = 'already on disk';
    final tempDir = await Directory.systemTemp.createTemp('bunny_core_ffi_download_test');
    try {
      await File('${tempDir.path}/test.bin').writeAsString(body);

      // Nothing listens on this port -- if the fetch were actually
      // attempted, polling would never report a 'verified' outcome.
      final handle = await native.downloadStart('http://127.0.0.1:1/unreachable', const {}, tempDir.path, 'test.bin', null);

      Map<String, Object?> result;
      do {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        result = await native.downloadPoll(handle);
      } while (result['done'] != true);
      await native.downloadRelease(handle);

      expect(result['outcome'], 'verified');
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test('tagAutocomplete returns an empty list when nothing is cached', () async {
    expect(await native.tagAutocomplete('e621', 'any', 10), isEmpty);
  });

  test('markPostSeen rejects a post id with no cached post', () async {
    // seen_posts.post_id REFERENCES posts(id) -- same foreign-key rejection
    // as queueFavoriteAdd below.
    await expectLater(native.markPostSeen(1), throwsA(isA<BunnyCoreNativeException>()));
  });

  test('queueFavoriteAdd rejects a post id with no cached post', () async {
    // bunny_db_action_queue_add enforces a foreign key against the post
    // cache, so this fails immediately at queue time rather than later
    // during processing.
    await expectLater(native.queueFavoriteAdd(1, -1), throwsA(isA<BunnyCoreNativeException>()));
  });

  test('verifyAccount rejects bogus e621 credentials', () async {
    // bunny_core_ffi_open never exposes a fake-transport override (unlike
    // libs/core's own tests) -- standalone mode always talks to the real
    // site. bunny_core_account_verify's actual success/failure logic is
    // already thoroughly covered against fake transports in
    // libs/core/tests/test_sync.c; this only proves the Dart<->native
    // plumbing reaches bunny_core_account_verify and surfaces its failure,
    // via one real (but fast, deterministic) request e621 will always
    // reject.
    await expectLater(native.verifyAccount('e621', 'definitely-not-a-real-user', 'definitely-not-a-real-key'), throwsA(isA<BunnyCoreNativeException>()));
  });

  test('operations before open throw', () async {
    final unopened = BunnyCoreNative();

    await expectLater(unopened.getAccount('e621'), throwsA(isA<BunnyCoreNativeException>()));
  });
}
