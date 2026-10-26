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

import '../fakes/fake_bunny_repository.dart';
import '../fakes/fake_download_queue_notifier.dart';
import '../fakes/fake_path_provider.dart';

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

  setUp(() async {
    PathProviderPlatform.instance = _RealPathProviderPlatform();
    destinationDir = await Directory.systemTemp.createTemp('download_queue_test');
    SharedPreferences.setMockInitialValues({'download_destination_folder': destinationDir.path});
    repository = FakeBunnyRepository();
    notifier = FakeDownloadQueueNotifier();
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

    expect(notifier.progressCalls, [(1, 1)]);
    expect(notifier.summaryCalls, [(1, 0, 0)]);
    expect(await File('${destinationDir.path}/someartist/1.png').exists(), isTrue);
  });

  test('enqueueAll processes every item strictly sequentially', () async {
    final service = buildService(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));
    final posts = [_post(id: 1), _post(id: 2), _post(id: 3)];

    service.enqueueAll(posts, repository);
    await waitUntilIdle(service);

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

    expect(notifier.summaryCalls, [(2, 0, 0)]);
  });

  test('a missing destination folder fails that item and continues to the next one', () async {
    SharedPreferences.setMockInitialValues({});
    final service = buildService(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));

    service.enqueue(_post(id: 1), repository);
    await waitUntilIdle(service);

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
    await Future<void>.delayed(const Duration(milliseconds: 1));

    // Simulate a fresh process: a brand new service instance, pointed at
    // the same (real) persistence directory via the same PathProviderPlatform
    // instance, with nothing enqueued yet.
    final restored = buildService(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));
    await restored.restore(repository);

    expect(restored.totalCount, 1);
    firstItemGate.complete();
    await waitUntilIdle(service);
  });
}

class _ThrowingDownloadQueueNotifier implements DownloadQueueNotifier {
  @override
  Future<void> showProgress({required int done, required int total}) async => throw StateError('boom');

  @override
  Future<void> showSummary({required int succeeded, required int mismatched, required int failed}) async => throw StateError('boom');

  @override
  Future<void> clear() async => throw StateError('boom');
}
