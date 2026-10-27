import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

BunnyPost _post({required int id, String? title}) => BunnyPost(
  id: id,
  site: BunnySite.e621,
  externalId: id,
  title: title,
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

  testWidgets('shows downloading/queued/failed sections with the right items', (WidgetTester tester) async {
    final secondItemGate = Completer<void>();
    final service = DownloadQueueService(
      downloadManager: DownloadManager(
        client: MockClient((request) async {
          final url = request.url.toString();
          if (url.endsWith('/1.png')) {
            return http.Response('', 500);
          }
          if (url.endsWith('/2.png')) {
            await secondItemGate.future;
          }
          return http.Response.bytes([1, 2, 3], 200);
        }),
      ),
      downloadSettingsStore: const DownloadSettingsStore(),
    );

    // runAsync escapes testWidgets's fake-async clock, which never advances
    // on its own -- needed so these real Future.delayed-based polls (and
    // the real HTTP/file work underneath) can actually resolve. Same
    // pattern already established in post_detail_screen_test.dart's own
    // download-button tests.
    await tester.runAsync(() async {
      service.enqueueAll([_post(id: 1, title: 'First'), _post(id: 2, title: 'Second'), _post(id: 3, title: 'Third')], repository);
      // Wait for item 1 to fail and item 2 to become the one actively
      // downloading, leaving item 3 behind it still queued.
      while (service.currentItem?.post.id != 2) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    });

    await tester.pumpWidget(wrap(service));
    // Not pumpAndSettle -- the "Downloading" row's CircularProgressIndicator
    // is indeterminate and animates forever, which pumpAndSettle would
    // never consider "settled."
    await tester.pump();

    expect(find.text('Downloading'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('Queued'), findsOneWidget);
    expect(find.text('Third'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('First'), findsOneWidget);
    expect(find.text('HTTP 500'), findsOneWidget);

    await tester.runAsync(() async {
      secondItemGate.complete();
      while (service.isActive) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    });
  });

  testWidgets('tapping a failed row\'s retry icon retries just that item', (WidgetTester tester) async {
    final attempts = <String, int>{};
    final service = DownloadQueueService(
      downloadManager: DownloadManager(
        client: MockClient((request) async {
          final url = request.url.toString();
          attempts[url] = (attempts[url] ?? 0) + 1;
          return attempts[url] == 1 ? http.Response('', 500) : http.Response.bytes([1, 2, 3], 200);
        }),
      ),
      downloadSettingsStore: const DownloadSettingsStore(),
    );

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
    final service = DownloadQueueService(
      downloadManager: DownloadManager(
        client: MockClient((request) async {
          final url = request.url.toString();
          attempts[url] = (attempts[url] ?? 0) + 1;
          return attempts[url] == 1 ? http.Response('', 500) : http.Response.bytes([1, 2, 3], 200);
        }),
      ),
      downloadSettingsStore: const DownloadSettingsStore(),
    );

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
    final service = DownloadQueueService(
      downloadManager: DownloadManager(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200))),
      downloadSettingsStore: const DownloadSettingsStore(),
    );

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
}
