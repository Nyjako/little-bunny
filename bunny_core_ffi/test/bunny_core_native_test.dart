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
  });

  test('deleteSearch removes it', () async {
    final id = await native.createSearch('e621', 'my search', 'rating:safe', 24);
    await native.deleteSearch(id);

    expect(await native.listSearches(), isEmpty);
  });

  test('listSearchPosts is empty for a freshly created search', () async {
    final id = await native.createSearch('e621', 'my search', 'rating:safe', 24);

    expect(await native.listSearchPosts(id, false), isEmpty);
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

  test('recordDownload rejects a post id with no cached post', () async {
    // downloads.post_id REFERENCES posts(id) -- same foreign-key rejection
    // as queueFavoriteAdd/markPostSeen above.
    await expectLater(native.recordDownload(1, '/tmp/file.jpg', null, false), throwsA(isA<BunnyCoreNativeException>()));
  });

  test('listDownloadsForPost is empty for a post with no recorded downloads', () async {
    // bunny_db_download_list_for_post has no foreign-key check on read
    // (unlike recordDownload's insert above) -- a post id with no matching
    // rows is just an empty result, even for one that was never cached.
    expect(await native.listDownloadsForPost(1), isEmpty);
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
