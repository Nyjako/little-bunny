import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/screens/slideshow_edit_screen.dart';
import 'package:little_bunny/screens/slideshows_screen.dart';
import 'package:little_bunny/services/download_manager.dart';
import 'package:little_bunny/services/download_queue_service.dart';
import 'package:little_bunny/settings/download_settings_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_bunny_repository.dart';
import '../fakes/fake_download_queue_notifier.dart';
import '../fakes/fake_path_provider.dart';
import '../fakes/test_app.dart';

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

  setUp(() async {
    PathProviderPlatform.instance = FakePathProviderPlatform();
    destinationDir = await Directory.systemTemp.createTemp('slideshows_screen_test');
    SharedPreferences.setMockInitialValues({'download_destination_folder': destinationDir.path});
    repository = FakeBunnyRepository();
    queueService = DownloadQueueService(downloadManager: const DownloadManager(), downloadSettingsStore: const DownloadSettingsStore(), notifier: FakeDownloadQueueNotifier());
  });

  tearDown(() async {
    if (await destinationDir.exists()) {
      await destinationDir.delete(recursive: true);
    }
  });

  Widget buildScreen() => wrapWithLocalization(
    SlideshowsScreen(repository: repository, downloadManager: const DownloadManager(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: queueService),
  );

  testWidgets('shows the empty state when there are no slideshows', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pump();

    expect(find.text('No slideshows yet. Tap + to create one.'), findsOneWidget);
  });

  testWidgets('lists slideshows with a no-limit or max-posts subtitle', (tester) async {
    await repository.slideshowCreate('unlimited one');
    await repository.slideshowCreate('capped one', maxTotalPosts: 10);
    await tester.pumpWidget(buildScreen());
    await tester.pump();

    expect(find.text('unlimited one'), findsOneWidget);
    expect(find.text('No post limit'), findsOneWidget);
    expect(find.text('capped one'), findsOneWidget);
    expect(find.text('Up to 10 posts'), findsOneWidget);
  });

  testWidgets('tapping a row opens the edit screen for it', (tester) async {
    await repository.slideshowCreate('my slideshow');
    await tester.pumpWidget(buildScreen());
    await tester.pump();

    await tester.tap(find.text('my slideshow'));
    await tester.pumpAndSettle();

    expect(find.byType(SlideshowEditScreen), findsOneWidget);
    expect(find.text('Edit slideshow'), findsOneWidget);
  });

  testWidgets('the FAB opens the create screen, and returning refreshes the list', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pump();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('New slideshow'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Label'), 'brand new');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('brand new'), findsOneWidget);
  });

  testWidgets('deleting without the checkbox keeps any downloaded file', (tester) async {
    final slideshowId = await repository.slideshowCreate('my slideshow');
    final searchId = await repository.createSearch(BunnySite.e621, 'wolves', 'wolf');
    final post = _post(id: 1);
    repository.postsBySearchId[searchId] = [post];
    await repository.slideshowSearchAdd(slideshowId, searchId);
    // Sync, not async -- a real dart:io Future awaited directly in a
    // test's own body (as opposed to one triggered from inside a tapped
    // widget callback, see this file's own note further down) still hangs
    // under this project's flutter_test environment when awaited async;
    // the sync variant sidesteps that entirely.
    Directory('${destinationDir.path}/someartist').createSync(recursive: true);
    final file = File('${destinationDir.path}/someartist/1.png');
    file.writeAsBytesSync([1, 2, 3]);

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    // Leave the "also delete downloaded files" checkbox unchecked.
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(file.existsSync(), isTrue);
    expect(await repository.slideshowList(), isEmpty);
  });

  // No widget test covers the "also delete downloaded files" checkbox's
  // actual file-deletion effect -- it goes through DownloadManager's real
  // filesystem check (localFilePathFor), real async dart:io work that
  // never resolves correctly under this project's flutter_test environment
  // when triggered from inside a tapped widget callback (confirmed via
  // several minimal repros, including a bare `ElevatedButton` whose
  // `onPressed` does nothing but `await file.exists()`; `tester.runAsync`
  // doesn't help either -- the delete call just silently fails inside
  // `_deleteLocalFiles`'s own try/catch instead of throwing). The
  // underlying file-check/delete logic itself is already covered
  // elsewhere by plain test()s (download_manager_test.dart,
  // slideshow_prepare_service_test.dart) that use real temp files without
  // a widget-test binding, so without hitting this limitation; only the
  // "does checking the box actually delete the file" wiring is unverified
  // here.
}
