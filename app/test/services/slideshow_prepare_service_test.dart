import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/services/download_manager.dart';
import 'package:little_bunny/services/download_queue_service.dart';
import 'package:little_bunny/services/slideshow_prepare_service.dart';
import 'package:little_bunny/settings/download_settings_store.dart';
import 'package:little_bunny/util/app_wakelock.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart' show wakelockPlusPlatformInstance;

import '../fakes/fake_bunny_repository.dart';
import '../fakes/fake_download_queue_notifier.dart';
import '../fakes/fake_path_provider.dart';
import '../fakes/fake_wakelock_plus_platform.dart';

/// Unlike [FakePathProviderPlatform] (which always has a Downloads path),
/// this has none -- for the one test exercising [DownloadSettingsStore.
/// loadDestinationFolder]'s full fallback-to-null chain.
class _NoDownloadsPathProviderPlatform extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  @override
  Future<String?> getDownloadsPath() async => null;
}

BunnyPost _post({required int id}) => BunnyPost(
  id: id,
  site: BunnySite.e621,
  externalId: id,
  artist: 'someartist',
  score: 0,
  favCount: 0,
  commentCount: 0,
  fileUrl: 'https://static1.e621.net/data/$id.png',
  fileExt: 'png',
  width: 100,
  height: 100,
  cachedAt: '2026-01-01T00:00:00Z',
  isSeen: false,
  isFavorited: false,
);

void main() {
  late Directory destinationDir;
  late FakeBunnyRepository repository;
  late DownloadQueueService queueService;
  late SlideshowPrepareService service;

  setUp(() async {
    AppWakelock.resetForTesting();
    PathProviderPlatform.instance = FakePathProviderPlatform();
    destinationDir = await Directory.systemTemp.createTemp('slideshow_prepare_test');
    SharedPreferences.setMockInitialValues({'download_destination_folder': destinationDir.path});
    repository = FakeBunnyRepository();
    queueService = DownloadQueueService(downloadManager: const DownloadManager(), downloadSettingsStore: const DownloadSettingsStore(), notifier: FakeDownloadQueueNotifier());
    wakelockPlusPlatformInstance = FakeWakelockPlusPlatform();
    service = SlideshowPrepareService(
      repository: repository,
      downloadQueueService: queueService,
      downloadManager: const DownloadManager(),
      downloadSettingsStore: const DownloadSettingsStore(),
    );
  });

  tearDown(() async {
    if (await destinationDir.exists()) {
      await destinationDir.delete(recursive: true);
    }
  });

  Future<void> waitUntilIdle() async {
    while (queueService.isActive) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  test('a post already verified on disk is classified ready', () async {
    final post = _post(id: 1);
    final searchId = await repository.createSearch(BunnySite.e621, 'wolves', 'wolf');
    repository.postsBySearchId[searchId] = [post];
    final slideshowId = await repository.slideshowCreate('my slideshow');
    await repository.slideshowSearchAdd(slideshowId, searchId);

    await Directory('${destinationDir.path}/someartist').create(recursive: true);
    await File('${destinationDir.path}/someartist/1.png').writeAsBytes([1, 2, 3]);

    final report = await service.prepare(slideshowId);

    expect(report.posts, hasLength(1));
    expect(report.posts.single.readiness, SlideshowPostReadiness.ready);
    expect(report.readyCount, 1);
    expect(report.readyPosts.single.id, 1);
  });

  test('a post with no download history is enqueued and classified in progress', () async {
    final post = _post(id: 2);
    final searchId = await repository.createSearch(BunnySite.e621, 'wolves', 'wolf');
    repository.postsBySearchId[searchId] = [post];
    final slideshowId = await repository.slideshowCreate('my slideshow');
    await repository.slideshowSearchAdd(slideshowId, searchId);

    final report = await service.prepare(slideshowId);

    expect(report.posts.single.readiness, SlideshowPostReadiness.inProgress);
    expect(report.inProgressCount, 1);
    // enqueueAll awaits the row insert before returning -- a row for this
    // post must now exist.
    final rows = await repository.downloadQueueList();
    expect(rows.where((row) => row.postId == 2), hasLength(1));

    await waitUntilIdle();
  });

  test('a post actively downloading this session is classified in progress, without being re-enqueued', () async {
    final post = _post(id: 3);
    final searchId = await repository.createSearch(BunnySite.e621, 'wolves', 'wolf');
    repository.postsBySearchId[searchId] = [post];
    final slideshowId = await repository.slideshowCreate('my slideshow');
    await repository.slideshowSearchAdd(slideshowId, searchId);

    final gate = Completer<void>();
    repository.downloadFileImpl = (fileUrl, destDir, filename, expectedMd5, onProgress) async {
      await gate.future;
      return const DownloadFetchResult(outcome: 'verified');
    };
    await queueService.enqueue(post, repository);
    while (queueService.downloadingItems.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }

    final report = await service.prepare(slideshowId);

    expect(report.posts.single.readiness, SlideshowPostReadiness.inProgress);
    // Still exactly one row/item for this post -- prepare() must not have
    // enqueued a second one on top of the one already in flight.
    final rows = await repository.downloadQueueList();
    expect(rows.where((row) => row.postId == 3), hasLength(1));

    gate.complete();
    await waitUntilIdle();
  });

  test('a persistently failed post is replaced with a fresh pick from the same search, which gets enqueued too', () async {
    final deadPost = _post(id: 4);
    final freshPost = _post(id: 5);
    final searchId = await repository.createSearch(BunnySite.e621, 'wolves', 'wolf');
    repository.postsBySearchId[searchId] = [deadPost, freshPost];
    final slideshowId = await repository.slideshowCreate('my slideshow');
    await repository.slideshowSearchAdd(slideshowId, searchId, overrideCount: 1);
    repository.seedDownloadQueueRow(postId: deadPost.id, status: 'failed', failureReason: 'HTTP 404');

    final report = await service.prepare(slideshowId);

    expect(report.posts, hasLength(1));
    expect(report.posts.single.readiness, SlideshowPostReadiness.replaced);
    expect(report.posts.single.post.id, 5);
    expect(report.replacedCount, 1);

    // The slideshow's own committed posts now reflect the swap.
    final committed = await repository.slideshowPostsList(slideshowId);
    expect(committed.map((p) => p.post.id), [5]);

    // And the fresh pick was handed to the real download queue.
    final rows = await repository.downloadQueueList();
    expect(rows.where((row) => row.postId == 5), hasLength(1));

    await waitUntilIdle();
  });

  test('a persistently failed post with nothing left to replace it is reported unreplaceable and stays committed', () async {
    final deadPost = _post(id: 6);
    final searchId = await repository.createSearch(BunnySite.e621, 'wolves', 'wolf');
    repository.postsBySearchId[searchId] = [deadPost];
    final slideshowId = await repository.slideshowCreate('my slideshow');
    await repository.slideshowSearchAdd(slideshowId, searchId);
    repository.seedDownloadQueueRow(postId: deadPost.id, status: 'checksum_mismatch', failureReason: 'checksum mismatch');

    final report = await service.prepare(slideshowId);

    expect(report.posts, hasLength(1));
    expect(report.posts.single.readiness, SlideshowPostReadiness.unreplaceable);
    expect(report.posts.single.reason, 'checksum mismatch');
    expect(report.unreplaceableCount, 1);

    final committed = await repository.slideshowPostsList(slideshowId);
    expect(committed.map((p) => p.post.id), [6]);
  });

  test('a quiet refresh (enqueueMissing: false) classifies a never-attempted post as missing without enqueueing it (M78)', () async {
    final post = _post(id: 8);
    final searchId = await repository.createSearch(BunnySite.e621, 'wolves', 'wolf');
    repository.postsBySearchId[searchId] = [post];
    final slideshowId = await repository.slideshowCreate('my slideshow');
    await repository.slideshowSearchAdd(slideshowId, searchId);

    final report = await service.prepare(slideshowId, enqueueMissing: false);

    expect(report.posts.single.readiness, SlideshowPostReadiness.missing);
    expect(report.missingCount, 1);
    final rows = await repository.downloadQueueList();
    expect(rows.where((row) => row.postId == 8), isEmpty);
  });

  test('a quiet refresh never re-enqueues a post whose file was deleted after an earlier successful download (M78)', () async {
    final post = _post(id: 9);
    final searchId = await repository.createSearch(BunnySite.e621, 'wolves', 'wolf');
    repository.postsBySearchId[searchId] = [post];
    final slideshowId = await repository.slideshowCreate('my slideshow');
    await repository.slideshowSearchAdd(slideshowId, searchId);
    // Simulates a post that was genuinely downloaded once (a 'succeeded' row
    // exists) and whose file was then deleted out-of-band -- exactly the
    // repro that used to make the very next quiet refresh silently
    // redownload it.
    repository.seedDownloadQueueRow(postId: post.id, status: 'succeeded');

    final report = await service.prepare(slideshowId, enqueueMissing: false);

    expect(report.posts.single.readiness, SlideshowPostReadiness.missing);
    final rows = await repository.downloadQueueList();
    expect(rows.where((row) => row.postId == 9 && row.status != 'succeeded'), isEmpty);
  });

  test('a quiet refresh leaves a stuck (persistently failed) post missing rather than attempting a replace (M78)', () async {
    final deadPost = _post(id: 10);
    final otherPost = _post(id: 11);
    final searchId = await repository.createSearch(BunnySite.e621, 'wolves', 'wolf');
    repository.postsBySearchId[searchId] = [deadPost, otherPost];
    final slideshowId = await repository.slideshowCreate('my slideshow');
    await repository.slideshowSearchAdd(slideshowId, searchId, overrideCount: 1);
    repository.seedDownloadQueueRow(postId: deadPost.id, status: 'failed', failureReason: 'HTTP 404');

    final report = await service.prepare(slideshowId, enqueueMissing: false);

    expect(report.posts.single.readiness, SlideshowPostReadiness.missing);
    // Never replaced -- the dead post is still the one committed.
    final committed = await repository.slideshowPostsList(slideshowId);
    expect(committed.map((p) => p.post.id), [10]);
  });

  test('prepare throws when no destination folder is configured and the OS has no Downloads directory either', () async {
    // Mirrors loadDestinationFolder's own fallback chain: nothing saved,
    // *and* no OS Downloads directory to fall back to (FakePathProviderPlatform
    // always has one, so this test swaps in a platform fake without it,
    // just for this one case).
    SharedPreferences.setMockInitialValues({});
    PathProviderPlatform.instance = _NoDownloadsPathProviderPlatform();
    final searchId = await repository.createSearch(BunnySite.e621, 'wolves', 'wolf');
    final slideshowId = await repository.slideshowCreate('my slideshow');
    await repository.slideshowSearchAdd(slideshowId, searchId);

    await expectLater(service.prepare(slideshowId), throwsA(isA<SlideshowPrepareException>()));
  });

  test('DownloadQueueService.progressFor counts terminal items among the given post ids', () async {
    final post = _post(id: 7);
    repository.postsById[7] = post;
    repository.downloadFileFetchImpl = (_) async => http.Response.bytes([1, 2, 3], 200);

    expect(queueService.progressFor({7}), (0, 1));

    await queueService.enqueue(post, repository);
    await waitUntilIdle();

    expect(queueService.progressFor({7}), (1, 1));
    expect(queueService.progressFor({}), (0, 0));
  });
}
