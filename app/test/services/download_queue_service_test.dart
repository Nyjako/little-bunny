import 'dart:async';
import 'dart:convert';
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

/// Same shape as `fake_path_provider.dart`'s own `FakePathProviderPlatform`,
/// but with a *real* (not a bare placeholder string) directory for
/// `getApplicationSupportPath`, computed once so repeated calls (and a
/// second `DownloadQueueService` instance simulating a fresh app launch)
/// see the same path -- `DownloadQueueService`'s persistence (M43) does
/// real file I/O against it, unlike every other current user of the shared
/// fake. `getDownloadsPath` returns null (instead of the shared fake's
/// `/fake/downloads`) so `DownloadSettingsStore.loadDestinationFolder`
/// genuinely falls through to null when a test doesn't save a folder,
/// rather than silently resolving to a fake path.
class _RealPathProviderPlatform extends FakePathProviderPlatform {
  final String supportPath = Directory.systemTemp.createTempSync('bunny_queue_support_').path;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;

  @override
  Future<String?> getDownloadsPath() async => null;
}

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
    PathProviderPlatform.instance = _RealPathProviderPlatform();
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

  DownloadQueueService buildService({http.Client? client}) =>
      DownloadQueueService(downloadManager: DownloadManager(client: client), downloadSettingsStore: const DownloadSettingsStore(), notifier: notifier);

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
    expect(notifier.progressCalls, [(1, 1)]);
    expect(notifier.summaryCalls, [(1, 0, 0)]);
    expect(await File('${destinationDir.path}/someartist/1.png').exists(), isTrue);
  });

  test('enqueueAll processes every item strictly sequentially', () async {
    final service = buildService(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));
    final posts = [_post(id: 1), _post(id: 2), _post(id: 3)];

    service.enqueueAll(posts, repository);
    await waitUntilIdle(service);

    expect(notifier.startingCalls, [3]);
    expect(notifier.progressCalls, [(1, 3), (2, 3), (3, 3)]);
    expect(notifier.summaryCalls, [(3, 0, 0)]);
  });

  test('auto-favorite drains the action queue once per item, not once per batch', () async {
    SharedPreferences.setMockInitialValues({'download_destination_folder': destinationDir.path, 'auto_favorite_on_download': true});
    final service = buildService(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));
    final posts = [_post(id: 1), _post(id: 2)];

    service.enqueueAll(posts, repository);
    await waitUntilIdle(service);

    expect(repository.favoriteAddCalls, [1, 2]);
    expect(repository.processQueueCallCount, 2);
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
    final service = DownloadQueueService(
      downloadManager: DownloadManager(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200))),
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
    // Without this, the background _processQueue() for post 2 is still
    // in flight when this test returns -- it later calls _persist(), which
    // re-reads PathProviderPlatform.instance at call-time. By then the next
    // test's setUp() has already swapped in its own fake instance, so this
    // dangling write lands in (and corrupts) the *next* test's persistence
    // file instead of this test's own.
    await waitUntilIdle(service);
  });

  test('restore re-enqueues whatever was still pending from a previous run', () async {
    final firstItemGate = Completer<void>();
    final service = buildService(
      client: MockClient((_) async {
        await firstItemGate.future;
        return http.Response.bytes([1, 2, 3], 200);
      }),
    );
    final post = _post(id: 1);
    repository.postsById[1] = post;

    service.enqueue(post, repository);
    // enqueue's own _persist() write to pending_downloads.json is real,
    // fire-and-forget file I/O -- a single fixed 1ms wait before reading it
    // back below was flaky under CI load (observed directly: passed in the
    // PR's own check run, then failed on push to `dev` moments later with
    // restored.totalCount reading 0 instead of 1, meaning the write hadn't
    // landed yet). Poll for the real file's content instead of guessing a
    // delay is long enough.
    final persistedFile = File('${(PathProviderPlatform.instance as _RealPathProviderPlatform).supportPath}/pending_downloads.json');
    while (!await persistedFile.exists() || !(await persistedFile.readAsString()).contains('${post.id}')) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }

    // Simulate a fresh process: a brand new service instance, pointed at
    // the same (real) persistence directory via the same PathProviderPlatform
    // instance, with nothing enqueued yet.
    final restored = buildService(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));
    await restored.restore(repository);

    expect(restored.totalCount, 1);
    firstItemGate.complete();
    await waitUntilIdle(service);
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

      // Items 1 (fails) and 2 (succeeds) resolve immediately; item 3 is
      // gated, so it sits as "downloading" while we clear.
      while (service.currentItem?.post.id != 3) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(service.items, hasLength(3));

      service.clearFinished();

      expect(service.items, hasLength(1));
      expect(service.currentItem?.post.id, 3);

      thirdItemGate.complete();
      await waitUntilIdle(service);
    });

    test('restore brings back a failed item\'s status/reason without auto-retrying it', () async {
      final service = buildService(client: MockClient((_) async => http.Response('', 500)));
      final post = _post(id: 1);
      repository.postsById[1] = post;

      service.enqueue(post, repository);
      await waitUntilIdle(service);
      expect(service.failedItems, hasLength(1));

      final persistedFile = File('${(PathProviderPlatform.instance as _RealPathProviderPlatform).supportPath}/pending_downloads.json');
      while (!(await persistedFile.readAsString()).contains('failed')) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }

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

    test('restore falls back to the pre-queue-visibility flat-id-array format', () async {
      final file = File('${(PathProviderPlatform.instance as _RealPathProviderPlatform).supportPath}/pending_downloads.json');
      await file.writeAsString(jsonEncode([1]));
      repository.postsById[1] = _post(id: 1);

      final service = buildService(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));
      await service.restore(repository);

      expect(service.totalCount, 1);
      await waitUntilIdle(service);
      expect(await File('${destinationDir.path}/someartist/1.png').exists(), isTrue);
    });
  });
}

class _ThrowingDownloadQueueNotifier implements DownloadQueueNotifier {
  @override
  Future<void> showStarting({required int total}) async => throw StateError('boom');

  @override
  Future<void> showProgress({required int done, required int total}) async => throw StateError('boom');

  @override
  Future<void> showSummary({required int succeeded, required int mismatched, required int failed}) async => throw StateError('boom');

  @override
  Future<void> clear() async => throw StateError('boom');
}
