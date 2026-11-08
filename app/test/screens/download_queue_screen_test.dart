import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/screens/download_queue_screen.dart';
import 'package:little_bunny/services/download_manager.dart';
import 'package:little_bunny/services/download_queue_service.dart';
import 'package:little_bunny/settings/download_settings_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart' show wakelockPlusPlatformInstance;

import '../fakes/fake_bunny_repository.dart';
import '../fakes/fake_path_provider.dart';
import '../fakes/fake_wakelock_plus_platform.dart';
import '../fakes/test_app.dart';

BunnyPost _post({required int id, String? title, String? previewUrl, String? fileMd5}) => BunnyPost(
  id: id,
  site: BunnySite.e621,
  externalId: id,
  title: title,
  previewUrl: previewUrl,
  score: 0,
  favCount: 0,
  commentCount: 0,
  fileUrl: 'https://static1.e621.net/data/$id.png',
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

  setUp(() async {
    PathProviderPlatform.instance = FakePathProviderPlatform();
    destinationDir = await Directory.systemTemp.createTemp('download_queue_screen_test');
    SharedPreferences.setMockInitialValues({'download_destination_folder': destinationDir.path});
    repository = FakeBunnyRepository();
    // DownloadQueueService now holds a wake lock while processing (M57
    // follow-up) -- the real plugin has no platform-channel implementation
    // under bare `flutter test`, so this needs the same fake registered as
    // post_detail_screen_test.dart's own download-button tests.
    wakelockPlusPlatformInstance = FakeWakelockPlusPlatform();
  });

  tearDown(() async {
    if (await destinationDir.exists()) {
      await destinationDir.delete(recursive: true);
    }
  });

  Widget wrap(DownloadQueueService service) => wrapWithLocalization(DownloadQueueScreen(downloadQueueService: service));

  testWidgets('shows the empty state when nothing is queued', (WidgetTester tester) async {
    final service = DownloadQueueService(downloadManager: const DownloadManager(), downloadSettingsStore: const DownloadSettingsStore());

    await tester.pumpWidget(wrap(service));
    await tester.pumpAndSettle();

    expect(find.text('Nothing here right now.'), findsOneWidget);
  });

  testWidgets('shows a row per concurrently-downloading item, alongside queued/failed counts (M62)', (WidgetTester tester) async {
    final gates = {2: Completer<void>(), 3: Completer<void>(), 4: Completer<void>()};
    // Tracks which gated requests have actually reached their `await
    // entry.value.future` below, as opposed to merely being claimed by a
    // worker (DownloadQueueItemStatus.downloading) -- a worker can sit claimed
    // for a while before its HTTP call actually fires (it does a real,
    // unordered file-existence check first). The first runAsync block below
    // must wait for this, not just the downloading count: a Future that's
    // still working its way to its first real await when runAsync returns
    // never gets properly woken up again by a later runAsync call, which
    // otherwise deadlocks this test permanently on exactly that item.
    final gatingStarted = <int>{};
    repository.downloadFileFetchImpl = (url) async {
      if (url.endsWith('/1.png')) {
        return http.Response('', 500);
      }
      for (final entry in gates.entries) {
        if (url.endsWith('/${entry.key}.png')) {
          gatingStarted.add(entry.key);
          await entry.value.future;
        }
      }
      return http.Response.bytes([1, 2, 3], 200);
    };
    final service = DownloadQueueService(downloadManager: const DownloadManager(), downloadSettingsStore: const DownloadSettingsStore());

    // runAsync escapes testWidgets's fake-async clock, which never advances
    // on its own -- needed so these real Future.delayed-based polls (and
    // the real HTTP/file work underneath) can actually resolve. Same
    // pattern already established in post_detail_screen_test.dart's own
    // download-button tests.
    await tester.runAsync(() async {
      service.enqueueAll([
        _post(id: 1, title: 'First'),
        _post(id: 2, title: 'Second'),
        _post(id: 3, title: 'Third'),
        _post(id: 4, title: 'Fourth'),
        _post(id: 5, title: 'Fifth'),
      ], repository);
      // Item 1 fails immediately, freeing its concurrency slot for item 4
      // -- once items 2/3/4 all occupy the 3 slots (all gated), item 5 has
      // nowhere to go and stays queued.
      while (service.downloadingItems.length != 3 || service.pendingCount != 1 || gatingStarted.length != 3) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    });

    await tester.pumpWidget(wrap(service));
    await tester.pump();

    expect(find.text('Downloading'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('Third'), findsOneWidget);
    expect(find.text('Fourth'), findsOneWidget);
    // Queued is a count, not a per-item list -- "Fifth" never renders by
    // name, item 5 is just folded into the "1 queued" count.
    expect(find.text('1 queued'), findsOneWidget);
    expect(find.text('Fifth'), findsNothing);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('First'), findsOneWidget);
    expect(find.text('HTTP 500'), findsOneWidget);

    await tester.runAsync(() async {
      for (final gate in gates.values) {
        gate.complete();
      }
      while (service.isActive) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    });
  });

  testWidgets('tapping a failed row\'s retry icon retries just that item', (WidgetTester tester) async {
    final attempts = <String, int>{};
    repository.downloadFileFetchImpl = (url) async {
      attempts[url] = (attempts[url] ?? 0) + 1;
      return attempts[url] == 1 ? http.Response('', 500) : http.Response.bytes([1, 2, 3], 200);
    };
    final service = DownloadQueueService(downloadManager: const DownloadManager(), downloadSettingsStore: const DownloadSettingsStore());

    await tester.runAsync(() async {
      service.enqueue(_post(id: 1, title: 'First'), repository);
      while (service.isActive) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    });

    await tester.pumpWidget(wrap(service));
    await tester.pumpAndSettle();
    expect(find.text('Failed'), findsOneWidget);

    final retryRow = find.ancestor(of: find.text('First'), matching: find.byType(ListTile));
    final retryRowButton = tester.widget<IconButton>(find.ancestor(of: find.descendant(of: retryRow, matching: find.byIcon(Icons.replay)), matching: find.byType(IconButton)));
    await tester.runAsync(() async {
      retryRowButton.onPressed!();
      while (service.isActive) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    });
    await tester.pump();

    expect(find.text('Failed'), findsNothing);
  });

  testWidgets('"Retry all" retries every failed item', (WidgetTester tester) async {
    final attempts = <String, int>{};
    repository.downloadFileFetchImpl = (url) async {
      attempts[url] = (attempts[url] ?? 0) + 1;
      return attempts[url] == 1 ? http.Response('', 500) : http.Response.bytes([1, 2, 3], 200);
    };
    final service = DownloadQueueService(downloadManager: const DownloadManager(), downloadSettingsStore: const DownloadSettingsStore());

    await tester.runAsync(() async {
      service.enqueueAll([_post(id: 1, title: 'First'), _post(id: 2, title: 'Second')], repository);
      while (service.isActive) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    });

    await tester.pumpWidget(wrap(service));
    await tester.pumpAndSettle();
    expect(find.text('Failed'), findsOneWidget);

    final retryAllButton = tester.widget<IconButton>(
      find.ancestor(of: find.descendant(of: find.byType(AppBar), matching: find.byIcon(Icons.replay)), matching: find.byType(IconButton)),
    );
    await tester.runAsync(() async {
      retryAllButton.onPressed!();
      while (service.isActive) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    });
    await tester.pump();

    expect(find.text('Failed'), findsNothing);
  });

  testWidgets('"Clear finished" removes terminal items from view', (WidgetTester tester) async {
    repository.downloadFileFetchImpl = (_) async => http.Response.bytes([1, 2, 3], 200);
    final service = DownloadQueueService(downloadManager: const DownloadManager(), downloadSettingsStore: const DownloadSettingsStore());

    await tester.runAsync(() async {
      service.enqueue(_post(id: 1, title: 'First'), repository);
      while (service.isActive) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    });
    expect(service.items, hasLength(1));

    await tester.pumpWidget(wrap(service));
    await tester.pumpAndSettle();

    final clearButton = tester.widget<IconButton>(find.ancestor(of: find.byIcon(Icons.clear_all), matching: find.byType(IconButton)));
    clearButton.onPressed!();
    await tester.pump();

    expect(service.items, isEmpty);
    expect(find.text('Nothing here right now.'), findsOneWidget);
  });

  testWidgets('the currently-downloading row shows a thumbnail and a determinate batch-progress bar', (WidgetTester tester) async {
    final secondItemGate = Completer<void>();
    repository.downloadFileFetchImpl = (url) async {
      if (url.endsWith('/2.png')) {
        await secondItemGate.future;
      }
      return http.Response.bytes([1, 2, 3], 200);
    };
    final service = DownloadQueueService(downloadManager: const DownloadManager(), downloadSettingsStore: const DownloadSettingsStore());

    await tester.runAsync(() async {
      service.enqueueAll([_post(id: 1, title: 'First'), _post(id: 2, title: 'Second', previewUrl: 'https://example.com/2_preview.jpg')], repository);
      while (service.downloadingItems.length != 1 || service.downloadingItems.single.post.id != 2) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    });

    await tester.pumpWidget(wrap(service));
    await tester.pump();

    final progressBar = tester.widget<LinearProgressIndicator>(find.byKey(const Key('downloadQueueBatchProgressBar')));
    // Item 1 of 2 already done, item 2 (this row) actively downloading.
    expect(progressBar.value, 0.5);
    expect(find.byType(CachedNetworkImage), findsOneWidget);

    await tester.runAsync(() async {
      secondItemGate.complete();
      while (service.isActive) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    });
  });

  testWidgets('shows the current file\'s own byte progress separately from the batch bar (M62)', (WidgetTester tester) async {
    final chunkGate = Completer<void>();
    // Drives onProgress directly (M66 -- see download_queue_service_test.dart's
    // own equivalent fix for why this needs the full downloadFileImpl
    // override rather than a streamed MockClient response).
    repository.downloadFileImpl = (fileUrl, destDir, filename, expectedMd5, onProgress) async {
      onProgress(40, 100);
      await chunkGate.future;
      onProgress(100, 100);
      await Directory(destDir).create(recursive: true);
      await File('$destDir/$filename').writeAsBytes(List.filled(100, 1));
      return const DownloadFetchResult(outcome: 'verified');
    };
    final service = DownloadQueueService(downloadManager: const DownloadManager(), downloadSettingsStore: const DownloadSettingsStore());

    await tester.runAsync(() async {
      service.enqueue(_post(id: 1, title: 'First'), repository);
      while (service.downloadingItems.isEmpty || service.downloadingItems.single.bytesReceived != 40) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    });

    await tester.pumpWidget(wrap(service));
    await tester.pump();

    final fileProgressBar = tester.widget<LinearProgressIndicator>(find.byKey(const ValueKey('downloadQueueFileProgressBar_1')));
    expect(fileProgressBar.value, 0.4);
    expect(find.text('40 B / 100 B'), findsOneWidget);

    await tester.runAsync(() async {
      chunkGate.complete();
      while (service.isActive) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    });
  });

  testWidgets('queued/done render as counts, not one row each -- only downloading items get real rows (M62)', (WidgetTester tester) async {
    // A small item count here, not literally hundreds/thousands -- the
    // screen's rendering has no count-dependent branch (the count-row path
    // is taken identically whether pending is 1 or 5000). Item 1 resolves
    // immediately ("1 done"); items 2-4 occupy all 3 concurrency slots (all
    // gated, 3 downloading rows); item 5 has nowhere to go ("1 queued").
    final gates = {2: Completer<void>(), 3: Completer<void>(), 4: Completer<void>()};
    repository.downloadFileFetchImpl = (url) async {
      for (final entry in gates.entries) {
        if (url.endsWith('/${entry.key}.png')) {
          await entry.value.future;
        }
      }
      return http.Response.bytes([1, 2, 3], 200);
    };
    final service = DownloadQueueService(downloadManager: const DownloadManager(), downloadSettingsStore: const DownloadSettingsStore());

    await tester.runAsync(() async {
      service.enqueueAll(List.generate(5, (i) => _post(id: i + 1)), repository);
      while (service.downloadingItems.length != 3 || service.pendingCount != 1) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    });

    await tester.pumpWidget(wrap(service));
    await tester.pump();

    expect(find.text('1 queued'), findsOneWidget);
    expect(find.text('1 done'), findsOneWidget);
    // 5 ListTiles total: 3 currently-downloading rows + "1 queued" row +
    // "1 done" row -- no per-item rows were built for the queued/done posts.
    expect(find.byType(ListTile), findsNWidgets(5));

    await tester.runAsync(() async {
      for (final gate in gates.values) {
        gate.complete();
      }
      while (service.isActive) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    });
  });

  testWidgets('"Done" counts succeeded items only, unaffected by a checksum-mismatch item', (WidgetTester tester) async {
    repository.downloadFileFetchImpl = (_) async => http.Response.bytes([1, 2, 3], 200);
    final service = DownloadQueueService(downloadManager: const DownloadManager(), downloadSettingsStore: const DownloadSettingsStore());

    await tester.runAsync(() async {
      // Post 1 has no published checksum -- downloads verified. Post 2
      // claims a checksum the fake bytes won't match -- checksumMismatch,
      // which must stay out of the "Done" count and show under Failed.
      service.enqueueAll([_post(id: 1, title: 'First'), _post(id: 2, title: 'Second', fileMd5: 'deadbeef')], repository);
      while (service.isActive) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    });

    await tester.pumpWidget(wrap(service));
    await tester.pumpAndSettle();

    expect(find.text('1 done'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
  });
}
