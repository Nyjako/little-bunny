import 'dart:io';

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

  test('getStatsReport returns an empty, unbuilt report when nothing is cached (M40/M55)', () async {
    final report = await repository.getStatsReport();
    expect(report.computedAt, isNull);
    expect(report.topFavoritedTags, isEmpty);
    expect(report.topUsedTags, isEmpty);
    expect(report.topPools, isEmpty);
    expect(report.topViewedSearches, isEmpty);
  });

  test('refreshStatsReport actually builds (and blocks for) a fresh report, unlike getStatsReport (M55)', () async {
    final report = await repository.refreshStatsReport();
    expect(report.computedAt, isNotNull); // a real build just happened, unlike getStatsReport's cache-only read
    expect(report.topFavoritedTags, isEmpty); // still empty -- nothing's actually favorited/synced
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

  test('getPostFiles returns an empty list for a nonexistent post', () async {
    expect(await repository.getPostFiles(1), isEmpty);
  });

  test('addBlacklistTag/getBlacklist/removeBlacklistTag round-trip per site (M13.3)', () async {
    expect(await repository.getBlacklist(BunnySite.e621), isEmpty);

    await repository.addBlacklistTag(BunnySite.e621, 'young');
    expect(await repository.getBlacklist(BunnySite.e621), ['young']);
    expect(await repository.getBlacklist(BunnySite.inkbunny), isEmpty);

    await repository.removeBlacklistTag(BunnySite.e621, 'young');
    expect(await repository.getBlacklist(BunnySite.e621), isEmpty);
  });

  test('addSlideshowBlacklistTag/getSlideshowBlacklist/removeSlideshowBlacklistTag round-trip per slideshow', () async {
    final slideshowId = await repository.slideshowCreate('my slideshow');

    expect(await repository.getSlideshowBlacklist(slideshowId), isEmpty);

    await repository.addSlideshowBlacklistTag(slideshowId, 'comic');
    expect(await repository.getSlideshowBlacklist(slideshowId), ['comic']);

    final otherSlideshowId = await repository.slideshowCreate('other slideshow');
    expect(await repository.getSlideshowBlacklist(otherSlideshowId), isEmpty);

    await repository.removeSlideshowBlacklistTag(slideshowId, 'comic');
    expect(await repository.getSlideshowBlacklist(slideshowId), isEmpty);
  });

  test('validateTagQuery accepts valid syntax and rejects invalid syntax with an error position (M28/M54)', () async {
    expect(await repository.validateTagQuery(BunnySite.e621, 'cat ~dog -bird ( ~a ~b )'), isNull);
    expect(await repository.validateTagQuery(BunnySite.e621, '(  )'), 0);
  });

  test('validateTagQuery uses Inkbunny\'s narrower dialect (M28/M54)', () async {
    expect(await repository.validateTagQuery(BunnySite.inkbunny, 'leopard -snow'), isNull);
    expect(await repository.validateTagQuery(BunnySite.inkbunny, '~cat'), isNotNull);
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
    // Only ever set by a sync that actually finds a new post (M69) -- never
    // populated here, no sync has run.
    expect(searches.single.lastUpdatedAt, isNull);
  });

  test('listSearchPosts is empty for a freshly created search regardless of rating/media mask', () async {
    final id = await repository.createSearch(BunnySite.e621, 'my search', 'rating:safe', intervalHours: 12);

    expect(await repository.listSearchPosts(id), isEmpty);
    expect(await repository.listSearchPosts(id, ratingMask: kRatingMaskSafe, mediaMask: kMediaMaskImage), isEmpty);
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

  test('mergeDuplicateSearch deletes the duplicate and keeps the keeper (M41)', () async {
    final keeperId = await repository.createSearch(BunnySite.e621, 'wolves', 'wolf');
    final duplicateId = await repository.createSearch(BunnySite.e621, 'wolves (dupe)', 'wolf', intervalHours: 48);

    await repository.mergeDuplicateSearch(keeperId, duplicateId);

    final searches = await repository.listSearches();
    expect(searches, hasLength(1));
    expect(searches.single.id, keeperId);
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

  test('downloadQueueAdd/downloadQueueList/downloadQueueSetStatus/downloadQueueClearFinished round-trip (M62 follow-up)', () async {
    // No posts(id) foreign key on this table -- an arbitrary post id (one
    // that was never synced/cached) must be accepted here, unlike
    // queueFavoriteAdd above.
    final id = await repository.downloadQueueAdd(42);
    expect(id, greaterThan(0));

    var records = await repository.downloadQueueList();
    expect(records, hasLength(1));
    expect(records.single.id, id);
    expect(records.single.postId, 42);
    expect(records.single.status, 'queued');
    expect(records.single.failureReason, isNull);

    await repository.downloadQueueSetStatus(id, 'failed', failureReason: 'HTTP 500');
    records = await repository.downloadQueueList();
    expect(records.single.status, 'failed');
    expect(records.single.failureReason, 'HTTP 500');

    await repository.downloadQueueClearFinished();
    expect(await repository.downloadQueueList(), isEmpty);
  });

  test('a download_queue row survives closing and reopening a real, file-backed db (M67)', () async {
    // Every other test in this file uses ':memory:' (see setUp), which
    // proves nothing about actual restart durability -- an in-memory
    // sqlite db is trivially gone the instant the connection closes
    // regardless of whether the underlying write path is sound. A real
    // temp file is what actually exercises "does this row still exist
    // after the app (and its db connection) has fully closed and a brand
    // new one opens the same file," the exact scenario a restart is.
    final dir = await Directory.systemTemp.createTemp('ffi_restart_test');
    addTearDown(() => dir.delete(recursive: true));
    final dbPath = '${dir.path}/bunny.db';

    final first = await FfiBunnyRepository.open(dbPath: dbPath, userAgent: 'little_bunny_test/0.0.1');
    final id = await first.downloadQueueAdd(123);
    await first.close();

    final second = await FfiBunnyRepository.open(dbPath: dbPath, userAgent: 'little_bunny_test/0.0.1');
    final rows = await second.downloadQueueList();
    await second.close();

    expect(rows, hasLength(1));
    expect(rows.single.id, id);
    expect(rows.single.postId, 123);
  });

  test('slideshowCreate/slideshowList/slideshowGet/slideshowUpdate/slideshowDelete round-trip into BunnySlideshow (M51 v2)', () async {
    final id = await repository.slideshowCreate('my slideshow', defaultPostsPerSearch: 5);

    final slideshows = await repository.slideshowList();
    expect(slideshows, hasLength(1));
    expect(slideshows.single.id, id);
    expect(slideshows.single.label, 'my slideshow');
    expect(slideshows.single.defaultPostsPerSearch, 5);
    expect(slideshows.single.maxTotalPosts, isNull);

    await repository.slideshowUpdate(id, 'renamed', maxTotalPosts: 10);
    final slideshow = await repository.slideshowGet(id);
    expect(slideshow.label, 'renamed');
    expect(slideshow.defaultPostsPerSearch, isNull);
    expect(slideshow.maxTotalPosts, 10);

    await repository.slideshowDelete(id);
    expect(await repository.slideshowList(), isEmpty);
  });

  test('slideshowGet throws for a nonexistent slideshow (M51 v2)', () async {
    await expectLater(repository.slideshowGet(999), throwsA(isA<BunnyRepositoryException>()));
  });

  test('slideshowSearchAdd/slideshowSearchList/slideshowPostsList/slideshowSearchRemove round-trip into BunnySlideshowSearch/BunnySlideshowPost (M51 v2)', () async {
    final searchId = await repository.createSearch(BunnySite.e621, 'wolves', 'wolf', intervalHours: 24);
    final slideshowId = await repository.slideshowCreate('my slideshow');

    await repository.slideshowSearchAdd(slideshowId, searchId, overrideCount: 3);
    final links = await repository.slideshowSearchList(slideshowId);
    expect(links, hasLength(1));
    expect(links.single.searchId, searchId);
    expect(links.single.overrideCount, 3);

    // Nothing's actually been synced for this search, so there's nothing to
    // commit -- this just proves the round trip into BunnySlideshowPost
    // doesn't throw.
    expect(await repository.slideshowPostsList(slideshowId), isEmpty);
    expect(await repository.slideshowPostsList(slideshowId, searchId: searchId), isEmpty);

    await repository.slideshowRerollAll(slideshowId);
    await repository.slideshowRerollSearch(slideshowId, searchId);

    await repository.slideshowSearchRemove(slideshowId, searchId);
    expect(await repository.slideshowSearchList(slideshowId), isEmpty);
  });

  test('slideshowReplacePost throws when the search has nothing to replace with (M51 v2)', () async {
    final searchId = await repository.createSearch(BunnySite.e621, 'wolves', 'wolf', intervalHours: 24);
    final slideshowId = await repository.slideshowCreate('my slideshow');
    await repository.slideshowSearchAdd(slideshowId, searchId);

    await expectLater(repository.slideshowReplacePost(slideshowId, searchId, 1), throwsA(isA<BunnyRepositoryException>()));
  });
}
