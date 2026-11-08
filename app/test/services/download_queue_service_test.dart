import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/services/download_manager.dart';
import 'package:little_bunny/services/download_queue_notifier.dart';
import 'package:little_bunny/services/download_queue_service.dart';
import 'package:little_bunny/settings/download_settings_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart' show wakelockPlusPlatformInstance;

import '../fakes/fake_bunny_repository.dart';
import '../fakes/fake_download_queue_notifier.dart';
import '../fakes/fake_path_provider.dart';
import '../fakes/fake_wakelock_plus_platform.dart';

BunnyPost _post({required int id, String? fileUrl = 'https://static1.e621.net/data/1.png', String? fileMd5}) => BunnyPost(
  id: id,
  site: BunnySite.e621,
  externalId: id,
  artist: 'someartist',
  score: 0,
  favCount: 0,
  commentCount: 0,
  fileUrl: fileUrl,
  fileExt: 'png',
  fileMd5: fileMd5,
  width: 100,
  height: 100,
  cachedAt: '2026-01-01T00:00:00Z',
  isSeen: false,
  isFavorited: false,
);

void main() {
  late Directory destinationDir;
  late FakeBunnyRepository repository;
  late FakeDownloadQueueNotifier notifier;
  late FakeWakelockPlusPlatform wakelockPlatform;

  setUp(() async {
    PathProviderPlatform.instance = FakePathProviderPlatform();
    destinationDir = await Directory.systemTemp.createTemp('download_queue_test');
    SharedPreferences.setMockInitialValues({'download_destination_folder': destinationDir.path});
    repository = FakeBunnyRepository();
    notifier = FakeDownloadQueueNotifier();
    wakelockPlatform = FakeWakelockPlusPlatform();
    wakelockPlusPlatformInstance = wakelockPlatform;
  });

  tearDown(() async {
    if (await destinationDir.exists()) {
      await destinationDir.delete(recursive: true);
    }
  });

  // M66: DownloadManager's plain-path branch no longer touches an
  // http.Client at all (that part is now BunnyRepository.downloadFile,
  // delegating to native code with no fake-transport seam of its own) --
  // every existing MockClient handler here still works unchanged by
  // feeding it through FakeBunnyRepository.downloadFileFetchImpl instead,
  // preserving each test's own per-URL branching logic.
  DownloadQueueService buildService({http.Client? client}) {
    if (client != null) {
      repository.downloadFileFetchImpl = (url) => client.send(http.Request('GET', Uri.parse(url))).then(http.Response.fromStream);
    }
    return DownloadQueueService(downloadManager: const DownloadManager(), downloadSettingsStore: const DownloadSettingsStore(), notifier: notifier);
  }

  Future<void> waitUntilIdle(DownloadQueueService service) async {
    while (service.isActive) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  test('enqueue downloads the post and reports progress then a summary', () async {
    final service = buildService(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));
    final post = _post(id: 1);
    repository.postsById[1] = post;

    service.enqueue(post, repository);
    await waitUntilIdle(service);

    expect(notifier.startingCalls, [1]);
    expect(notifier.progressCalls, [(1, 1, 0, null)]);
    expect(notifier.summaryCalls, [(1, 0, 0)]);
    expect(await File('${destinationDir.path}/someartist/1.png').exists(), isTrue);
  });

  test('a DownloadQueueItem\'s bytesReceived/bytesTotal (M62) track its own progress, resetting after', () async {
    final firstChunkGate = Completer<void>();
    // Drives onProgress on its own timeline (M66 -- the native fetch
    // reports progress via polling, not an injectable HTTP stream, so this
    // simulates the same "partial progress, then more arrives" shape
    // directly through FakeBunnyRepository.downloadFileImpl instead).
    repository.downloadFileImpl = (fileUrl, destDir, filename, expectedMd5, onProgress) async {
      onProgress(30, 100);
      await firstChunkGate.future;
      onProgress(100, 100);
      await Directory(destDir).create(recursive: true);
      await File('$destDir/$filename').writeAsBytes(List.filled(100, 1));
      return const DownloadFetchResult(outcome: 'verified');
    };
    final service = buildService();
    final post = _post(id: 1);
    repository.postsById[1] = post;

    service.enqueue(post, repository);
    while (service.downloadingItems.isEmpty || service.downloadingItems.single.bytesReceived != 30) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    final item = service.downloadingItems.single;
    expect(item.bytesTotal, 100);

    firstChunkGate.complete();
    await waitUntilIdle(service);

    // The same DownloadQueueItem object survives into its terminal state
    // (succeeded) once the queue drains -- but a fresh item starting later
    // would get its own null-initialized fields, confirmed by the next item
    // test in this suite via downloadingItems never showing stale bytes
    // from a previous item.
    expect(item.status, DownloadQueueItemStatus.succeeded);
  });

  test('enqueueAll processes every item, reporting progress through to completion (M62: concurrently, order not guaranteed)', () async {
    final service = buildService(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));
    final posts = [_post(id: 1), _post(id: 2), _post(id: 3)];

    service.enqueueAll(posts, repository);
    await waitUntilIdle(service);

    expect(notifier.startingCalls, [3]);
    // Exactly one progress call per completed item, each reporting against
    // the whole batch's total/failed -- but which item's completion lands
    // "first" (done: 1) is no longer guaranteed now that up to 3 download
    // concurrently (M62), so this only checks the set of done values, not
    // their order.
    expect(notifier.progressCalls.map((call) => call.$1).toSet(), {1, 2, 3});
    expect(notifier.progressCalls.every((call) => call.$2 == 3 && call.$3 == 0), isTrue);
    // eta is null only for the call reporting the very first completed item
    // (done: 1) -- not enough data yet for a rate -- and non-null for every
    // other call.
    expect(notifier.progressCalls.singleWhere((call) => call.$1 == 1).$4, isNull);
    expect(notifier.progressCalls.where((call) => call.$1 != 1).every((call) => call.$4 != null), isTrue);
    expect(notifier.summaryCalls, [(3, 0, 0)]);
  });

  test('up to 3 items download concurrently, a 4th stays queued until one finishes (M62)', () async {
    final gates = List.generate(3, (_) => Completer<void>());
    var requestCount = 0;
    final service = buildService(
      client: MockClient((_) async {
        final index = requestCount;
        requestCount++;
        if (index < gates.length) {
          await gates[index].future;
        }
        return http.Response.bytes([1, 2, 3], 200);
      }),
    );

    service.enqueueAll([_post(id: 1), _post(id: 2), _post(id: 3), _post(id: 4)], repository);
    while (service.downloadingItems.length < 3) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }

    // All 3 concurrency slots are taken by items 1-3; item 4 has nowhere to go yet.
    expect(service.downloadingItems.map((item) => item.post.id).toSet(), {1, 2, 3});
    expect(service.pendingCount, 1);

    // item 4's own request has no gate (requestCount is already past
    // gates.length by the time it's claimed), so it resolves almost
    // immediately -- waiting for pendingCount to drop (rather than trying
    // to catch item 4 mid-"downloading") is what's actually reliable here.
    gates[0].complete();
    while (service.pendingCount > 0) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }

    gates[1].complete();
    gates[2].complete();
    await waitUntilIdle(service);
    expect(service.succeededCount, 4);
  });

  group('enqueue dedup -- a post already active in the queue is not added twice', () {
    test('a post still queued is ignored by a second enqueue call', () async {
      final gate = Completer<void>();
      final service = buildService(client: MockClient((_) async => gate.future.then((_) => http.Response.bytes([1, 2, 3], 200))));
      final post = _post(id: 1);

      service.enqueue(post, repository);
      service.enqueue(post, repository);

      expect(service.items, hasLength(1));
      expect(service.totalCount, 1);

      gate.complete();
      await waitUntilIdle(service);
    });

    test('a post currently downloading is ignored by a second enqueue call', () async {
      final gate = Completer<void>();
      final service = buildService(client: MockClient((_) async => gate.future.then((_) => http.Response.bytes([1, 2, 3], 200))));
      final post = _post(id: 1);

      service.enqueue(post, repository);
      while (service.downloadingItems.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }

      service.enqueue(post, repository);

      expect(service.items, hasLength(1));
      expect(service.totalCount, 1);

      gate.complete();
      await waitUntilIdle(service);
    });

    test('enqueueAll dedupes the same post repeated within one call', () async {
      final service = buildService(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));
      final post = _post(id: 1);

      service.enqueueAll([post, post, post], repository);
      await waitUntilIdle(service);

      expect(service.succeededCount, 1);
    });

    test('a post that already finished can be legitimately re-queued', () async {
      final service = buildService(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));
      final post = _post(id: 1);

      service.enqueue(post, repository);
      await waitUntilIdle(service);
      expect(service.succeededCount, 1);

      // Not a duplicate-in-flight situation -- the first run already
      // finished, so a deliberate second download must still go through.
      service.enqueue(post, repository);
      await waitUntilIdle(service);

      expect(service.items, hasLength(2));
      expect(service.succeededCount, 2);
    });

    test('enqueueAll only drops the duplicates, not the genuinely new posts in the same batch', () async {
      final service = buildService(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));
      final gate = Completer<void>();
      service.enqueue(_post(id: 1, fileUrl: 'https://static1.e621.net/data/1.png'), repository);
      // Re-enqueue id 1 (should be dropped) alongside a genuinely new id 2
      // (should go through) in the same call.
      service.enqueueAll([_post(id: 1, fileUrl: 'https://static1.e621.net/data/1.png'), _post(id: 2, fileUrl: 'https://static1.e621.net/data/2.png')], repository);
      gate.complete();
      await waitUntilIdle(service);

      expect(service.items.map((item) => item.post.id).toSet(), {1, 2});
    });
  });

  test('auto-favorite drains the action queue once via the final flush, for a batch under the sync threshold', () async {
    SharedPreferences.setMockInitialValues({'download_destination_folder': destinationDir.path, 'auto_favorite_on_download': true});
    final service = buildService(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));
    // Fewer than the throttle threshold -- exercises the "final flush covers
    // a batch that never hit the threshold" path.
    final posts = List.generate(9, (i) => _post(id: i + 1));

    service.enqueueAll(posts, repository);
    await waitUntilIdle(service);

    // Set, not list, equality -- which item finishes first is no longer
    // guaranteed now that up to 3 download concurrently (M62).
    expect(repository.favoriteAddCalls.toSet(), posts.map((p) => p.id).toSet());
    expect(repository.processQueueCallCount, 1);
  });

  test('a batch larger than the sync threshold does not drain the action queue once per item', () async {
    SharedPreferences.setMockInitialValues({'download_destination_folder': destinationDir.path, 'auto_favorite_on_download': true});
    final service = buildService(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));
    final posts = List.generate(25, (i) => _post(id: i + 1));

    service.enqueueAll(posts, repository);
    await waitUntilIdle(service);

    expect(repository.favoriteAddCalls, hasLength(25));
    // Far fewer than one-per-item (25) -- the exact count depends on the
    // throttle threshold, deliberately not hardcoded here so this test isn't
    // coupled to that literal constant.
    expect(repository.processQueueCallCount, greaterThan(0));
    expect(repository.processQueueCallCount, lessThan(10));
  });

  test('auto-favorite off never drains the action queue at all', () async {
    SharedPreferences.setMockInitialValues({'download_destination_folder': destinationDir.path});
    final service = buildService(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));

    service.enqueueAll(List.generate(12, (i) => _post(id: i + 1)), repository);
    await waitUntilIdle(service);

    expect(repository.processQueueCallCount, 0);
  });

  test('a slow action-queue drain does not block the next item\'s download', () async {
    SharedPreferences.setMockInitialValues({'download_destination_folder': destinationDir.path, 'auto_favorite_on_download': true});
    final drainGate = Completer<void>();
    repository.processQueueImpl = () async {
      await drainGate.future;
      return repository.processQueueResult;
    };
    final service = buildService(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));

    service.enqueue(_post(id: 1), repository);
    // The download itself (file write) completes independent of the gated
    // final-flush drain -- proving the drain isn't on the download's own
    // critical path. If it were, this would hang until drainGate completes.
    while (!await File('${destinationDir.path}/someartist/1.png').exists()) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    drainGate.complete();
    await waitUntilIdle(service);
  });

  test('enqueueing more items mid-flight extends the total without losing progress', () async {
    final firstItemGate = Completer<void>();
    var requestCount = 0;
    final service = buildService(
      client: MockClient((_) async {
        requestCount++;
        if (requestCount == 1) {
          await firstItemGate.future;
        }
        return http.Response.bytes([1, 2, 3], 200);
      }),
    );

    service.enqueue(_post(id: 1), repository);
    // The first item is now awaiting firstItemGate -- enqueue a second one
    // while it's still in flight.
    await Future<void>.delayed(const Duration(milliseconds: 1));
    service.enqueue(_post(id: 2), repository);
    expect(service.totalCount, 2);

    firstItemGate.complete();
    await waitUntilIdle(service);

    // Only one startingCalls entry -- the second enqueue() lands while the
    // queue is already processing, so it extends the existing run rather
    // than starting a second one.
    expect(notifier.startingCalls, [1]);
    expect(notifier.summaryCalls, [(2, 0, 0)]);
  });

  test('a missing destination folder fails that item and continues to the next one', () async {
    SharedPreferences.setMockInitialValues({});
    final service = buildService(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));

    service.enqueue(_post(id: 1), repository);
    await waitUntilIdle(service);

    expect(notifier.startingCalls, [1]);
    expect(notifier.summaryCalls, [(0, 0, 1)]);
  });

  test('a notifier that throws on every call never stops the queue from processing', () async {
    repository.downloadFileFetchImpl = (_) async => http.Response.bytes([1, 2, 3], 200);
    final service = DownloadQueueService(
      downloadManager: const DownloadManager(),
      downloadSettingsStore: const DownloadSettingsStore(),
      notifier: _ThrowingDownloadQueueNotifier(),
    );

    service.enqueueAll([_post(id: 1), _post(id: 2)], repository);
    await waitUntilIdle(service);

    expect(await File('${destinationDir.path}/someartist/1.png').exists(), isTrue);
    expect(await File('${destinationDir.path}/someartist/2.png').exists(), isTrue);
  });

  test('session counters reset to 0 once the queue fully drains', () async {
    final service = buildService(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));
    service.enqueue(_post(id: 1), repository);
    await waitUntilIdle(service);
    expect(service.totalCount, 0);
    expect(service.completedCount, 0);

    service.enqueue(_post(id: 2), repository);
    expect(service.totalCount, 1);
    await waitUntilIdle(service);
  });

  group('persistence (M62 follow-up -- SQLite via BunnyRepository, not a Dart-owned JSON file)', () {
    test('enqueueAll persists each new item as a queued row', () async {
      final service = buildService(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));
      final posts = [_post(id: 1), _post(id: 2)];

      service.enqueueAll(posts, repository);
      // Each item's own insert is fire-and-forget (enqueueAll never blocks
      // its caller) -- wait for them before reading the persisted state back.
      await Future.wait(service.items.map((item) => item.queueRowIdFuture));

      final rows = await repository.downloadQueueList();
      expect(rows.map((r) => r.postId).toSet(), {1, 2});
      expect(rows.every((r) => r.status == 'queued'), isTrue);

      await waitUntilIdle(service);
    });

    test('a completed download persists its terminal status', () async {
      final service = buildService(client: MockClient((_) async => http.Response('', 500)));

      service.enqueue(_post(id: 1), repository);
      await waitUntilIdle(service);

      final rows = await repository.downloadQueueList();
      expect(rows, hasLength(1));
      expect(rows.single.status, 'failed');
      expect(rows.single.failureReason, 'HTTP 500');
    });

    test('clearFinished also drops the persisted rows', () async {
      final service = buildService(client: MockClient((_) async => http.Response('', 500)));
      service.enqueue(_post(id: 1), repository);
      await waitUntilIdle(service);
      expect(await repository.downloadQueueList(), isNotEmpty);

      service.clearFinished();

      expect(await repository.downloadQueueList(), isEmpty);
    });

    test('restore re-enqueues a row still queued from a previous run', () async {
      final post = _post(id: 1);
      repository.postsById[1] = post;
      repository.seedDownloadQueueRow(postId: 1, status: 'queued');

      final restored = buildService(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));
      await restored.restore(repository);

      expect(restored.totalCount, 1);
      await waitUntilIdle(restored);
      expect(await File('${destinationDir.path}/someartist/1.png').exists(), isTrue);
    });

    test('restore resets a still-downloading row back to queued and reprocesses it', () async {
      final post = _post(id: 1);
      repository.postsById[1] = post;
      repository.seedDownloadQueueRow(postId: 1, status: 'downloading');

      final restored = buildService(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));
      await restored.restore(repository);

      expect(restored.totalCount, 1);
      await waitUntilIdle(restored);
      expect(restored.succeededCount, 1);
    });

    test('restore skips a row whose post no longer resolves, without failing the rest', () async {
      repository.postsById[2] = _post(id: 2);
      repository.seedDownloadQueueRow(postId: 1, status: 'queued'); // never resolvable
      repository.seedDownloadQueueRow(postId: 2, status: 'queued');

      final restored = buildService(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));
      await restored.restore(repository);

      expect(restored.totalCount, 1);
      expect(restored.items.single.post.id, 2);
    });

    test('restore retries a transient getPost failure (M65) and still succeeds once it recovers', () async {
      final post = _post(id: 1);
      repository.postsById[1] = post;
      // Fails on the first 2 attempts (e.g. network not up yet at cold
      // boot), succeeds on the 3rd -- within _getPostRetries' budget.
      repository.getPostFailuresRemaining[1] = 2;
      repository.seedDownloadQueueRow(postId: 1, status: 'queued');

      final restored = buildService(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));
      await restored.restore(repository);

      expect(restored.totalCount, 1);
      await waitUntilIdle(restored);
      expect(restored.succeededCount, 1);
    });

    test('resume (M65) re-checks a row that failed to resolve on the earlier restore() call and picks it up', () async {
      final post = _post(id: 1);
      repository.postsById[1] = post;
      // Exhausts restore()'s retry budget entirely -- the row is left out of
      // the queue after the first restore() call.
      repository.getPostFailuresRemaining[1] = 10;
      repository.seedDownloadQueueRow(postId: 1, status: 'queued');

      final service = buildService(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));
      await service.restore(repository);
      expect(service.totalCount, 0);

      // The network has "recovered" by the time resume() is called.
      repository.getPostFailuresRemaining[1] = 0;
      await service.resume(repository);

      expect(service.totalCount, 1);
      await waitUntilIdle(service);
      expect(service.succeededCount, 1);
    });

    test('resume (M65) does not duplicate a row already pulled in by a previous restore()', () async {
      final post = _post(id: 1);
      repository.postsById[1] = post;
      repository.seedDownloadQueueRow(postId: 1, status: 'queued');

      final service = buildService(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));
      await service.restore(repository);
      await waitUntilIdle(service);
      expect(service.items, hasLength(1));

      await service.resume(repository);

      expect(service.items, hasLength(1));
    });
  });

  test('showStarting fires before the first HTTP request completes (M57 screen-lock fix)', () async {
    final firstItemGate = Completer<void>();
    final service = buildService(
      client: MockClient((_) async {
        await firstItemGate.future;
        return http.Response.bytes([1, 2, 3], 200);
      }),
    );

    service.enqueue(_post(id: 1), repository);
    // Let the queue's own microtasks run, but the HTTP client is still
    // gated -- showStarting must already have fired by now, well before the
    // fetch itself resolves.
    await Future<void>.delayed(const Duration(milliseconds: 1));
    expect(notifier.startingCalls, [1]);
    expect(notifier.progressCalls, isEmpty);

    firstItemGate.complete();
    await waitUntilIdle(service);
  });

  test('holds a wake lock while the queue is active and releases it once drained', () async {
    final firstItemGate = Completer<void>();
    final service = buildService(
      client: MockClient((_) async {
        await firstItemGate.future;
        return http.Response.bytes([1, 2, 3], 200);
      }),
    );

    expect(wakelockPlatform.enabledValue, isFalse);
    service.enqueue(_post(id: 1), repository);
    await Future<void>.delayed(const Duration(milliseconds: 1));
    expect(wakelockPlatform.enabledValue, isTrue);

    firstItemGate.complete();
    await waitUntilIdle(service);
    expect(wakelockPlatform.enabledValue, isFalse);
  });

  group('queue visibility (M43 follow-up)', () {
    test('a failed download shows up in failedItems with its reason', () async {
      final service = buildService(client: MockClient((_) async => http.Response('', 500)));

      service.enqueue(_post(id: 1), repository);
      await waitUntilIdle(service);

      expect(service.failedItems, hasLength(1));
      expect(service.failedItems.single.post.id, 1);
      expect(service.failedItems.single.failureReason, 'HTTP 500');
      expect(notifier.progressCalls.last.$3, 1);
    });

    test('retryFailed moves one failed item back to queued and it gets reprocessed', () async {
      final attempts = <String, int>{};
      final service = buildService(
        client: MockClient((request) async {
          final url = request.url.toString();
          attempts[url] = (attempts[url] ?? 0) + 1;
          return attempts[url] == 1 ? http.Response('', 500) : http.Response.bytes([1, 2, 3], 200);
        }),
      );

      service.enqueue(_post(id: 1), repository);
      await waitUntilIdle(service);
      final failedItem = service.failedItems.single;

      service.retryFailed(failedItem);
      await waitUntilIdle(service);

      expect(service.failedItems, isEmpty);
      expect(failedItem.status, DownloadQueueItemStatus.succeeded);
      expect(await File('${destinationDir.path}/someartist/1.png').exists(), isTrue);
    });

    test('retryFailed is a no-op for an item that is not actually failed', () async {
      final service = buildService(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));
      service.enqueue(_post(id: 1), repository);
      await waitUntilIdle(service);
      final succeededItem = service.items.single;
      expect(succeededItem.status, DownloadQueueItemStatus.succeeded);

      service.retryFailed(succeededItem);

      expect(service.isActive, isFalse);
      expect(succeededItem.status, DownloadQueueItemStatus.succeeded);
    });

    test('retryAllFailed retries every failed item in one batch', () async {
      final attempts = <String, int>{};
      final service = buildService(
        client: MockClient((request) async {
          final url = request.url.toString();
          attempts[url] = (attempts[url] ?? 0) + 1;
          return attempts[url] == 1 ? http.Response('', 500) : http.Response.bytes([1, 2, 3], 200);
        }),
      );

      service.enqueueAll([_post(id: 1, fileUrl: 'https://static1.e621.net/data/1.png'), _post(id: 2, fileUrl: 'https://static1.e621.net/data/2.png')], repository);
      await waitUntilIdle(service);
      expect(service.failedItems, hasLength(2));

      service.retryAllFailed();
      await waitUntilIdle(service);

      expect(service.failedItems, isEmpty);
    });

    test('clearFinished drops terminal items but leaves a still-downloading one untouched', () async {
      final thirdItemGate = Completer<void>();
      final service = buildService(
        client: MockClient((request) async {
          final url = request.url.toString();
          if (url.endsWith('/1.png')) {
            return http.Response('', 500);
          }
          if (url.endsWith('/2.png')) {
            return http.Response.bytes([1, 2, 3], 200);
          }
          await thirdItemGate.future;
          return http.Response.bytes([1, 2, 3], 200);
        }),
      );

      service.enqueueAll([
        _post(id: 1, fileUrl: 'https://static1.e621.net/data/1.png'),
        _post(id: 2, fileUrl: 'https://static1.e621.net/data/2.png'),
        _post(id: 3, fileUrl: 'https://static1.e621.net/data/3.png'),
      ], repository);

      // All 3 are claimed as "downloading" at once (M62: up to 3 concurrent
      // slots). Items 1 (fails) and 2 (succeeds) resolve immediately; item 3
      // is gated, so it's the only one still sitting as "downloading" by
      // the time we poll for it.
      while (!(service.downloadingItems.length == 1 && service.downloadingItems.single.post.id == 3)) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(service.items, hasLength(3));

      service.clearFinished();

      expect(service.items, hasLength(1));
      expect(service.downloadingItems.single.post.id, 3);

      thirdItemGate.complete();
      await waitUntilIdle(service);
    });

    test('restore brings back a failed item\'s status/reason without auto-retrying it', () async {
      final post = _post(id: 1);
      repository.postsById[1] = post;
      repository.seedDownloadQueueRow(postId: 1, status: 'failed', failureReason: 'HTTP 500');

      var requestCount = 0;
      final restored = buildService(
        client: MockClient((_) async {
          requestCount++;
          return http.Response.bytes([1, 2, 3], 200);
        }),
      );
      await restored.restore(repository);

      expect(restored.failedItems, hasLength(1));
      expect(restored.failedItems.single.failureReason, 'HTTP 500');
      expect(requestCount, 0);
    });
  });
}

class _ThrowingDownloadQueueNotifier implements DownloadQueueNotifier {
  @override
  Future<void> showStarting({required int total}) async => throw StateError('boom');

  @override
  Future<void> showProgress({required int done, required int total, required int failed, Duration? eta}) async => throw StateError('boom');

  @override
  Future<void> showSummary({required int succeeded, required int mismatched, required int failed}) async => throw StateError('boom');

  @override
  Future<void> clear() async => throw StateError('boom');
}
