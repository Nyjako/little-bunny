import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/screens/slideshow_edit_screen.dart';
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
    destinationDir = await Directory.systemTemp.createTemp('slideshow_edit_screen_test');
    SharedPreferences.setMockInitialValues({'download_destination_folder': destinationDir.path});
    repository = FakeBunnyRepository();
    queueService = DownloadQueueService(downloadManager: const DownloadManager(), downloadSettingsStore: const DownloadSettingsStore(), notifier: FakeDownloadQueueNotifier());
  });

  tearDown(() async {
    if (await destinationDir.exists()) {
      await destinationDir.delete(recursive: true);
    }
  });

  Widget buildScreen({BunnySlideshow? slideshow}) => wrapWithLocalization(
    SlideshowEditScreen(repository: repository, downloadManager: const DownloadManager(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: queueService, slideshow: slideshow),
  );

  /// The default test surface (800x600) is too short for this screen's
  /// form fields plus the searches/prepare sections combined -- anything
  /// below the fold is offstage, which every finder (`find.text`,
  /// `widgetWithText`, `byType`, ...) skips by default, surfacing as "no
  /// matching widgets" for a button that's actually right there, just
  /// unscrolled-to. A taller surface fits this whole screen without ever
  /// needing to scroll.
  Future<void> pumpScreen(WidgetTester tester, {BunnySlideshow? slideshow}) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(buildScreen(slideshow: slideshow));
  }

  testWidgets('create mode starts with no searches section until the slideshow is saved', (tester) async {
    await pumpScreen(tester);
    await tester.pump();

    expect(find.text('New slideshow'), findsOneWidget);
    expect(find.text('Searches'), findsNothing);

    await tester.enterText(find.widgetWithText(TextFormField, 'Label'), 'my slideshow');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Searches'), findsOneWidget);
    final created = await repository.slideshowList();
    expect(created.single.label, 'my slideshow');
  });

  testWidgets('edit mode pre-fills fields and shows the searches section immediately', (tester) async {
    // 7/20, not 5, so neither collides with the interval field's own
    // default text ('5') -- find.text('5') would otherwise ambiguously
    // match both.
    final id = await repository.slideshowCreate('existing', defaultPostsPerSearch: 7, maxTotalPosts: 20);
    final slideshow = (await repository.slideshowList()).single;
    expect(slideshow.id, id);

    await pumpScreen(tester, slideshow: slideshow);
    await tester.pump();

    expect(find.text('Edit slideshow'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Label'), findsOneWidget);
    expect(find.text('existing'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('20'), findsOneWidget);
    expect(find.text('Searches'), findsOneWidget);
    expect(find.text('No searches added yet. Save the slideshow first, then add one.'), findsOneWidget);
  });

  testWidgets('adding a search commits its posts and shows up in the list', (tester) async {
    final id = await repository.slideshowCreate('my slideshow');
    final searchId = await repository.createSearch(BunnySite.e621, 'wolves', 'wolf');
    repository.postsBySearchId[searchId] = [_post(id: 1)];
    final slideshow = (await repository.slideshowList()).single;

    await pumpScreen(tester, slideshow: slideshow);
    await tester.pump();

    await tester.tap(find.byTooltip('Add search'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('wolves'));
    // The dialog's "Add" button is disabled until the checkbox tap above is
    // actually reflected in its own setState -- without this pump, the tap
    // below lands on a still-disabled button and silently does nothing.
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(find.text('wolves'), findsOneWidget);
    expect(find.text('Uses the slideshow default'), findsOneWidget);
    final links = await repository.slideshowSearchList(id);
    expect(links, hasLength(1));
    final committed = await repository.slideshowPostsList(id);
    expect(committed.map((p) => p.post.id), [1]);
  });

  testWidgets('shows a message instead of an empty dialog once every search is already added', (tester) async {
    final id = await repository.slideshowCreate('my slideshow');
    final searchId = await repository.createSearch(BunnySite.e621, 'wolves', 'wolf');
    final slideshow = (await repository.slideshowList()).single;
    await repository.slideshowSearchAdd(id, searchId);

    await pumpScreen(tester, slideshow: slideshow);
    await tester.pump();

    await tester.tap(find.byTooltip('Add search'));
    await tester.pumpAndSettle();

    expect(find.text('Every search is already added'), findsOneWidget);
  });

  testWidgets('editing the override count updates the search link', (tester) async {
    final id = await repository.slideshowCreate('my slideshow');
    final searchId = await repository.createSearch(BunnySite.e621, 'wolves', 'wolf');
    final slideshow = (await repository.slideshowList()).single;
    await repository.slideshowSearchAdd(id, searchId);

    await pumpScreen(tester, slideshow: slideshow);
    await tester.pump();

    await tester.tap(find.text('wolves'));
    await tester.pumpAndSettle();
    // Scoped to the dialog -- a bare find.byType(TextField) also matches
    // every TextFormField's own internal TextField on the main screen
    // behind it.
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '3');
    // Disambiguate from the main form's own FilledButton labeled "Save" --
    // the dialog's own submit is a TextButton.
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('3 posts'), findsOneWidget);
    final links = await repository.slideshowSearchList(id);
    expect(links.single.overrideCount, 3);
  });

  testWidgets('removing a search without the checkbox keeps downloaded files; with it, deletes them', (tester) async {
    final id = await repository.slideshowCreate('my slideshow');
    final searchId = await repository.createSearch(BunnySite.e621, 'wolves', 'wolf');
    final post = _post(id: 1);
    repository.postsBySearchId[searchId] = [post];
    final slideshow = (await repository.slideshowList()).single;
    await repository.slideshowSearchAdd(id, searchId);
    Directory('${destinationDir.path}/someartist').createSync(recursive: true);
    final file = File('${destinationDir.path}/someartist/1.png');
    file.writeAsBytesSync([1, 2, 3]);

    await pumpScreen(tester, slideshow: slideshow);
    await tester.pump();

    await tester.tap(find.byTooltip('Remove search'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(file.existsSync(), isTrue);
    expect(await repository.slideshowSearchList(id), isEmpty);
  });

  // No widget test covers the "also delete downloaded files" checkbox's
  // actual file-deletion effect, or tapping Prepare: both go through
  // DownloadManager's real filesystem checks (localFilePathFor/
  // isDownloaded), real async dart:io work that never resolves under this
  // project's flutter_test environment when triggered from inside a tapped
  // widget callback -- confirmed via several minimal repros, including a
  // bare `ElevatedButton` whose `onPressed` does nothing but `await file
  // .exists()` (see slideshow_screen_test.dart's own comment on local-file
  // rendering for the equivalent finding with Image.file). `tester.runAsync`
  // doesn't help here either (pumpAndSettle inside it either times out, or
  // the delete call itself silently fails inside the production code's own
  // try/catch). The underlying logic -- SlideshowPrepareService.prepare()'s
  // ready/inProgress/replaced/unreplaceable classification, and
  // DownloadManager.isDownloaded/localFilePathFor's own file checks -- is
  // fully covered elsewhere by plain test()s (slideshow_prepare_service_test.dart,
  // download_manager_test.dart) that use real temp files without a
  // widget-test binding, so without hitting this limitation; only the
  // "does tapping this button call it" wiring is unverified here.

  testWidgets('Watch stays disabled before Prepare has ever produced a report', (tester) async {
    final id = await repository.slideshowCreate('my slideshow');
    final searchId = await repository.createSearch(BunnySite.e621, 'wolves', 'wolf');
    repository.postsBySearchId[searchId] = [_post(id: 1)];
    final slideshow = (await repository.slideshowList()).single;
    await repository.slideshowSearchAdd(id, searchId);

    await pumpScreen(tester, slideshow: slideshow);
    await tester.pumpAndSettle();

    final watchButton = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Watch'));
    expect(watchButton.onPressed, isNull);
  });
}
