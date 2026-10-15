import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/repository/bunny_repository.dart';
import 'package:little_bunny/repository/ffi_bunny_repository.dart';

// Exercises FfiBunnyRepository against the real compiled bunny_core_ffi
// shared library (built for the host by `flutter test`'s ffiPlugin support),
// backed by an in-memory SQLite database. bunny_core_ffi/test/
// bunny_core_native_test.dart already covers the isolate wrapper itself in
// depth; this suite only checks that FfiBunnyRepository maps its results to
// the BunnyRepository model classes correctly.
void main() {
  late FfiBunnyRepository repository;

  setUp(() async {
    repository = await FfiBunnyRepository.open(dbPath: ':memory:', userAgent: 'little_bunny_test/0.0.1');
  });

  tearDown(() => repository.close());

  test('getAccount returns null when none is configured', () async {
    expect(await repository.getAccount(BunnySite.e621), isNull);
  });

  test('tagAutocomplete returns an empty list when nothing is cached', () async {
    expect(await repository.tagAutocomplete(BunnySite.e621, 'any'), isEmpty);
  });

  test('topFavoritedTags returns an empty list when nothing is favorited (M10.2)', () async {
    expect(await repository.topFavoritedTags(BunnySite.e621), isEmpty);
  });

  test('topUsedTags returns an empty list when nothing is synced (M14.4)', () async {
    expect(await repository.topUsedTags(BunnySite.e621), isEmpty);
  });

  test('markPostSeen rejects a post id with no cached post', () async {
    await expectLater(repository.markPostSeen(1), throwsA(isA<BunnyRepositoryException>()));
  });

  test('markAllSeen is a no-op for a nonexistent search', () async {
    // Unlike markPostSeen (a foreign-key violation on a bad post id),
    // marking all of a search's posts seen is just an empty SELECT when the
    // search has no linked posts (or doesn't exist) -- nothing to reject.
    await expectLater(repository.markAllSeen(1), completes);
  });

  test('getPostTagsByCategory returns an empty list for a nonexistent post', () async {
    // Unlike markPostSeen (a foreign-key violation), this is a pure SELECT
    // with no matching rows for a post that was never cached -- nothing to
    // reject.
    expect(await repository.getPostTagsByCategory(1), isEmpty);
  });

  test('getPostSources returns an empty list for a nonexistent post', () async {
    expect(await repository.getPostSources(1), isEmpty);
  });

  test('addBlacklistTag/getBlacklist/removeBlacklistTag round-trip per site (M13.3)', () async {
    expect(await repository.getBlacklist(BunnySite.e621), isEmpty);

    await repository.addBlacklistTag(BunnySite.e621, 'young');
    expect(await repository.getBlacklist(BunnySite.e621), ['young']);
    expect(await repository.getBlacklist(BunnySite.inkbunny), isEmpty);

    await repository.removeBlacklistTag(BunnySite.e621, 'young');
    expect(await repository.getBlacklist(BunnySite.e621), isEmpty);
  });

  test('getPostRelationships returns all-empty/false for a nonexistent post', () async {
    final relationships = await repository.getPostRelationships(1);
    expect(relationships.hasParent, isFalse);
    expect(relationships.hasActiveChildren, isFalse);
    expect(relationships.children, isEmpty);
  });

  test('getPostPoolIds returns an empty list for a nonexistent post', () async {
    expect(await repository.getPostPoolIds(1), isEmpty);
  });

  test('recordDownload rejects a post id with no cached post', () async {
    await expectLater(repository.recordDownload(1, '/tmp/file.jpg'), throwsA(isA<BunnyRepositoryException>()));
  });

  test('listDownloadsForPost returns an empty list for a post with no recorded downloads', () async {
    expect(await repository.listDownloadsForPost(1), isEmpty);
  });

  test('getPost rejects a post id with no cached post', () async {
    // Unlike the other getPost* reads above, this is a single-row lookup by
    // primary key, so a miss is a real NOT_FOUND rather than an empty list.
    await expectLater(repository.getPost(1), throwsA(isA<BunnyRepositoryException>()));
  });

  test('verifyAccount rejects bogus e621 credentials', () async {
    // See bunny_core_ffi/test/bunny_core_native_test.dart for why this hits
    // real e621 network: standalone mode has no fake-transport override.
    await expectLater(repository.verifyAccount(BunnySite.e621, 'definitely-not-a-real-user', 'definitely-not-a-real-key'), throwsA(isA<BunnyRepositoryException>()));
  });

  test('setAccount then getAccount round-trips into a BunnyAccount', () async {
    await repository.setAccount(BunnySite.e621, 'someuser', 'somesecret');

    final account = await repository.getAccount(BunnySite.e621);

    expect(account, isNotNull);
    expect(account!.site, BunnySite.e621);
    expect(account.username, 'someuser');
  });

  test('createSearch then listSearches round-trips into BunnySearch', () async {
    final id = await repository.createSearch(BunnySite.e621, 'my search', 'rating:safe', intervalHours: 12);

    final searches = await repository.listSearches();

    expect(searches, hasLength(1));
    expect(searches.single.id, id);
    expect(searches.single.site, BunnySite.e621);
    expect(searches.single.label, 'my search');
    expect(searches.single.intervalHours, 12);
    expect(searches.single.autoFavorite, isFalse);
  });

  test('createSearch with autoFavorite, then updateSearch round-trips (M9.7.2)', () async {
    final id = await repository.createSearch(BunnySite.e621, 'my search', 'rating:safe', autoFavorite: true);

    final created = await repository.listSearches();
    expect(created.single.autoFavorite, isTrue);

    await repository.updateSearch(id, 'renamed', 'rating:explicit', intervalHours: 6, autoFavorite: false, autoUpvote: true);

    final updated = await repository.listSearches();
    expect(updated.single.label, 'renamed');
    expect(updated.single.query, 'rating:explicit');
    expect(updated.single.intervalHours, 6);
    expect(updated.single.autoFavorite, isFalse);
    expect(updated.single.autoUpvote, isTrue);
  });

  test('syncDueSearches completes with nothing to sync', () async {
    await expectLater(repository.syncDueSearches(), completes);
  });

  test('syncSearch throws for a nonexistent search id (M13.2)', () async {
    await expectLater(repository.syncSearch(1), throwsA(isA<BunnyRepositoryException>()));
  });

  test('processQueue returns a BunnyQueueStats', () async {
    final stats = await repository.processQueue();

    expect(stats.actionsProcessed, 0);
  });

  test('queueFavoriteAdd against a nonexistent post throws BunnyRepositoryException', () async {
    await expectLater(repository.queueFavoriteAdd(1), throwsA(isA<BunnyRepositoryException>()));
  });
}
