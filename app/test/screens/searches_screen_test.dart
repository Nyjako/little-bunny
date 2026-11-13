import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:little_bunny/bunny_repository_scope.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/screens/searches_screen.dart';
import 'package:little_bunny/services/download_manager.dart';
import 'package:little_bunny/services/download_queue_service.dart';
import 'package:little_bunny/services/preview_cache_service.dart';
import 'package:little_bunny/services/update_check_service.dart';
import 'package:little_bunny/settings/app_lock_service.dart';
import 'package:little_bunny/settings/display_settings_store.dart';
import 'package:little_bunny/settings/download_settings_store.dart';
import 'package:little_bunny/settings/repository_settings_store.dart';
import 'package:little_bunny/settings/theme_settings_store.dart';
import 'package:little_bunny/settings/update_settings_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_bunny_repository.dart';
import '../fakes/fake_path_provider.dart';
import '../fakes/fake_secret_store.dart';
import '../fakes/test_app.dart';

Widget _wrap(FakeBunnyRepository repository, {DownloadQueueService? downloadQueueService, UpdateSettingsStore? updateSettingsStore, UpdateCheckService? updateCheckService}) => wrapWithLocalization(
  BunnyRepositoryScope(
    repository: repository,
    child: SearchesScreen(
      lockService: AppLockService(FakeSecretStore()),
      themeSettingsStore: const ThemeSettingsStore(),
      displaySettingsStore: const DisplaySettingsStore(),
      downloadSettingsStore: const DownloadSettingsStore(),
      downloadQueueService: downloadQueueService ?? DownloadQueueService(downloadManager: const DownloadManager(), downloadSettingsStore: const DownloadSettingsStore()),
      previewCacheService: PreviewCacheService(),
      settingsStore: RepositorySettingsStore(FakeSecretStore()),
      updateSettingsStore: updateSettingsStore ?? const UpdateSettingsStore(),
      updateCheckService: updateCheckService ?? const UpdateCheckService(),
      onThemeModeChanged: (_) {},
      onThemeColorChanged: (_) {},
      onAmoledChanged: (_) {},
          onLanguageCodeChanged: (_) {},
      onRepositoryConfigured: (_) {},
    ),
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PathProviderPlatform.instance = FakePathProviderPlatform();
  });

  testWidgets('shows the empty state when there are no saved searches', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(FakeBunnyRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No saved searches yet. Tap + to add one.'), findsOneWidget);
  });

  testWidgets('app bar shrinks on wide windows (M9.6.6)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();

    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();
    final narrowHeight = tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight ?? kToolbarHeight;

    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();
    final wideHeight = tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight ?? kToolbarHeight;

    expect(wideHeight, lessThan(narrowHeight));
  });

  testWidgets('lists saved searches with their site and interval', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    await repository.createSearch(BunnySite.e621, 'Foxes', 'fox', intervalHours: 6);

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    expect(find.text('Foxes'), findsOneWidget);
    expect(find.text('e621 • every 6h • 0 posts'), findsOneWidget);
  });

  testWidgets('shows an unseen-count badge only when there are unseen posts', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final searchId = await repository.createSearch(BunnySite.e621, 'Foxes', 'fox');
    repository.postsBySearchId[searchId] = [
      BunnyPost(id: 1, site: BunnySite.e621, externalId: 1, score: 0, favCount: 0, commentCount: 0, width: 100, height: 100, cachedAt: '2026-01-01T00:00:00Z', isSeen: false, isFavorited: false),
      BunnyPost(id: 2, site: BunnySite.e621, externalId: 2, score: 0, favCount: 0, commentCount: 0, width: 100, height: 100, cachedAt: '2026-01-01T00:00:00Z', isSeen: true, isFavorited: false),
    ];

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('long-pressing a search row opens EditSearchScreen and refreshes on success (M9.7.2)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    await repository.createSearch(BunnySite.e621, 'Foxes', 'fox');

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Foxes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit search'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Label'), 'Renamed foxes');
    // The e621 metatags panel (shown by default, e621 being the search's
    // site) can push the Save button below the test surface's default
    // Sliver layout-cache extent.
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Renamed foxes'), findsOneWidget);
    expect(repository.searches.single.label, 'Renamed foxes');
  });

  testWidgets('deleting from EditSearchScreen removes the search from the list (M14.1)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    await repository.createSearch(BunnySite.e621, 'Foxes', 'fox');

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Foxes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit search'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete));
    await tester.pumpAndSettle();
    expect(find.text('Remove search?'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(repository.searches, isEmpty);
    expect(find.text('No saved searches yet. Tap + to add one.'), findsOneWidget);
  });

  testWidgets('tapping the pin icon pins a search to the top (M14.1)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    await repository.createSearch(BunnySite.e621, 'Alpha', 'alpha');
    await repository.createSearch(BunnySite.e621, 'Beta', 'beta');

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    // Beta's own pin button -- same row-finding shape as other per-row
    // action tests below.
    final betaPinButton = find.descendant(of: find.widgetWithText(ListTile, 'Beta'), matching: find.byIcon(Icons.push_pin_outlined));
    await tester.tap(betaPinButton);
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('Beta')).dy, lessThan(tester.getTopLeft(find.text('Alpha')).dy));
    expect(find.descendant(of: find.widgetWithText(ListTile, 'Beta'), matching: find.byIcon(Icons.push_pin)), findsOneWidget);
  });

  testWidgets('tapping the per-row sync button syncs only that search (M14.1)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final id1 = await repository.createSearch(BunnySite.e621, 'Foxes', 'fox');
    await repository.createSearch(BunnySite.e621, 'Wolves', 'wolf');

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    final foxesSyncButton = find.descendant(of: find.widgetWithText(ListTile, 'Foxes'), matching: find.byIcon(Icons.refresh));
    await tester.tap(foxesSyncButton);
    await tester.pumpAndSettle();

    expect(repository.syncSearchCalls, [id1]);
  });

  testWidgets('tapping a search row opens PostGridScreen for that search', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    await repository.createSearch(BunnySite.e621, 'Foxes', 'fox');

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Foxes'));
    await tester.pumpAndSettle();

    expect(find.text('No posts cached yet. Tap refresh to sync.'), findsOneWidget);
  });

  testWidgets('tapping the accounts icon opens AccountsScreen', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(FakeBunnyRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();

    expect(find.text('Accounts'), findsOneWidget);
  });

  testWidgets('tapping the tag stats icon opens TagStatsScreen (M10.2)', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(FakeBunnyRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.bar_chart_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Tag stats'), findsOneWidget);
  });

  testWidgets('tapping the custom search icon opens CustomSearchScreen (M54 partial)', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(FakeBunnyRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.travel_explore));
    await tester.pumpAndSettle();

    expect(find.text('Custom search'), findsOneWidget);
  });

  testWidgets('tapping the settings icon opens SettingsScreen', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(FakeBunnyRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('returning from SettingsScreen refreshes the search list (M13.1)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();
    expect(find.text('No saved searches yet. Tap + to add one.'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    // Simulates what Settings' Import feature (M11) does: creating searches
    // directly through the repository while SearchesScreen is paused behind
    // it, with no pop result to signal it.
    await repository.createSearch(BunnySite.e621, 'Foxes', 'fox');

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Foxes'), findsOneWidget);
  });

  testWidgets('selecting multiple searches and downloading queues every post from each (M65)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final firstId = await repository.createSearch(BunnySite.e621, 'Foxes', 'fox');
    final secondId = await repository.createSearch(BunnySite.e621, 'Wolves', 'wolf');
    repository.postsBySearchId[firstId] = [
      BunnyPost(id: 1, site: BunnySite.e621, externalId: 1, score: 0, favCount: 0, commentCount: 0, width: 100, height: 100, cachedAt: '2026-01-01T00:00:00Z', isSeen: false, isFavorited: false),
    ];
    repository.postsBySearchId[secondId] = [
      BunnyPost(id: 2, site: BunnySite.e621, externalId: 2, score: 0, favCount: 0, commentCount: 0, width: 100, height: 100, cachedAt: '2026-01-01T00:00:00Z', isSeen: false, isFavorited: false),
      BunnyPost(id: 3, site: BunnySite.e621, externalId: 3, score: 0, favCount: 0, commentCount: 0, width: 100, height: 100, cachedAt: '2026-01-01T00:00:00Z', isSeen: false, isFavorited: false),
    ];
    final downloadQueueService = DownloadQueueService(downloadManager: const DownloadManager(), downloadSettingsStore: const DownloadSettingsStore());

    await tester.pumpWidget(_wrap(repository, downloadQueueService: downloadQueueService));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select searches to download'));
    await tester.pumpAndSettle();

    expect(find.text('0 selected'), findsOneWidget);
    await tester.tap(find.text('Foxes'));
    await tester.tap(find.text('Wolves'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.byTooltip('Download selected'));
    await tester.pumpAndSettle();

    expect(find.text('3 queued for download'), findsOneWidget);
    expect(downloadQueueService.totalCount, 3);
    expect(downloadQueueService.items.map((item) => item.post.id).toSet(), {1, 2, 3});
    // Exits selection mode and clears the selection once queued.
    expect(find.text('Searches'), findsWidgets);
  });

  testWidgets('long-pressing a row and choosing Add to slideshow links it to the chosen slideshow', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    await repository.createSearch(BunnySite.e621, 'Foxes', 'fox');
    final slideshowId = await repository.slideshowCreate('My show');

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Foxes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to slideshow'));
    await tester.pumpAndSettle();

    expect(find.text('Add to slideshow'), findsWidgets);
    await tester.tap(find.text('My show'));
    await tester.pumpAndSettle();

    expect(find.text('Added to "My show"'), findsOneWidget);
    final links = await repository.slideshowSearchList(slideshowId);
    expect(links.single.searchId, repository.searches.single.id);
  });

  testWidgets('Add to slideshow shows a snackbar instead of a picker when there are no slideshows yet', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    await repository.createSearch(BunnySite.e621, 'Foxes', 'fox');

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Foxes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to slideshow'));
    await tester.pumpAndSettle();

    expect(find.text('No slideshows yet -- create one first.'), findsOneWidget);
  });

  testWidgets('selection mode can bulk-add every selected search to a chosen slideshow', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    await repository.createSearch(BunnySite.e621, 'Foxes', 'fox');
    await repository.createSearch(BunnySite.e621, 'Wolves', 'wolf');
    final slideshowId = await repository.slideshowCreate('My show');

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select searches to download'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Foxes'));
    await tester.tap(find.text('Wolves'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add selected to slideshow'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My show'));
    await tester.pumpAndSettle();

    expect(find.text('2 added to "My show"'), findsOneWidget);
    final links = await repository.slideshowSearchList(slideshowId);
    expect(links.map((link) => link.searchId).toSet(), repository.searches.map((search) => search.id).toSet());
    // Exits selection mode and clears the selection once added.
    expect(find.text('Searches'), findsWidgets);
  });

  testWidgets('downloading selected searches shows a per-search loading-posts progress dialog (M67)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final firstId = await repository.createSearch(BunnySite.e621, 'Foxes', 'fox');
    final secondId = await repository.createSearch(BunnySite.e621, 'Wolves', 'wolf');
    repository.postsBySearchId[firstId] = [
      BunnyPost(id: 1, site: BunnySite.e621, externalId: 1, score: 0, favCount: 0, commentCount: 0, width: 100, height: 100, cachedAt: '2026-01-01T00:00:00Z', isSeen: false, isFavorited: false),
    ];
    repository.postsBySearchId[secondId] = [
      BunnyPost(id: 2, site: BunnySite.e621, externalId: 2, score: 0, favCount: 0, commentCount: 0, width: 100, height: 100, cachedAt: '2026-01-01T00:00:00Z', isSeen: false, isFavorited: false),
      BunnyPost(id: 3, site: BunnySite.e621, externalId: 3, score: 0, favCount: 0, commentCount: 0, width: 100, height: 100, cachedAt: '2026-01-01T00:00:00Z', isSeen: false, isFavorited: false),
    ];

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select searches to download'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Foxes'));
    await tester.tap(find.text('Wolves'));
    await tester.pumpAndSettle();

    // Pauses every listSearchPosts call -- catches the dialog mid-flight, on
    // the first (1-post, 1-of-2-selected) search, before either ever gets
    // the chance to finish loading.
    repository.pauseBeforePage = Completer<void>();
    await tester.tap(find.byTooltip('Download selected'));
    await tester.pump();

    expect(find.text('Loading posts data 1/2'), findsOneWidget);
    expect(find.text('Foxes 0/1'), findsOneWidget);

    repository.pauseBeforePage!.complete();
    await tester.pumpAndSettle();

    expect(find.text('3 queued for download'), findsOneWidget);
    // The dialog closed along with everything else settling.
    expect(find.text('Loading posts data 1/2'), findsNothing);
  });


  testWidgets('on narrow widths, most actions fold into one overflow menu, and it still works (M51 declutter)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final searchId = await repository.createSearch(BunnySite.e621, 'Foxes', 'fox');
    repository.postsBySearchId[searchId] = [
      BunnyPost(id: 1, site: BunnySite.e621, externalId: 1, score: 0, favCount: 0, commentCount: 0, width: 100, height: 100, cachedAt: '2026-01-01T00:00:00Z', isSeen: false, isFavorited: false),
    ];

    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    // Sync and download queue stay as direct icons even on narrow widths.
    expect(find.byTooltip('Check for updates'), findsOneWidget);
    expect(find.byTooltip('Downloads'), findsOneWidget);
    // Everything else is folded away, replaced by one "more" icon.
    expect(find.byIcon(Icons.travel_explore), findsNothing);
    expect(find.byIcon(Icons.person_outline), findsNothing);
    expect(find.byIcon(Icons.bar_chart_outlined), findsNothing);
    expect(find.byIcon(Icons.settings_outlined), findsNothing);
    expect(find.byIcon(Icons.sort), findsNothing);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Most unseen'), findsOneWidget);
    expect(find.text('Select searches to download'), findsOneWidget);
    expect(find.text('Custom search'), findsOneWidget);
    expect(find.text('Accounts'), findsOneWidget);
    expect(find.text('Tag stats'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('New group'), findsOneWidget);

    // The folded select-for-download entry still enters selection mode.
    await tester.tap(find.text('Select searches to download'));
    await tester.pumpAndSettle();
    expect(find.text('0 selected'), findsOneWidget);

    await tester.tap(find.text('Foxes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Download selected'));
    await tester.pumpAndSettle();

    expect(find.text('1 queued for download'), findsOneWidget);
  });

  testWidgets('sort order defaults to most-unseen-first and persists a change (M13.1)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final fewUnseenId = await repository.createSearch(BunnySite.e621, 'Alpha', 'alpha');
    final manyUnseenId = await repository.createSearch(BunnySite.e621, 'Zebra', 'zebra');
    repository.postsBySearchId[fewUnseenId] = [
      BunnyPost(id: 1, site: BunnySite.e621, externalId: 1, score: 0, favCount: 0, commentCount: 0, width: 100, height: 100, cachedAt: '2026-01-01T00:00:00Z', isSeen: false, isFavorited: false),
    ];
    repository.postsBySearchId[manyUnseenId] = [
      BunnyPost(id: 2, site: BunnySite.e621, externalId: 2, score: 0, favCount: 0, commentCount: 0, width: 100, height: 100, cachedAt: '2026-01-01T00:00:00Z', isSeen: false, isFavorited: false),
      BunnyPost(id: 3, site: BunnySite.e621, externalId: 3, score: 0, favCount: 0, commentCount: 0, width: 100, height: 100, cachedAt: '2026-01-01T00:00:00Z', isSeen: false, isFavorited: false),
    ];

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    // Default: most unseen first -- "Zebra" (2 unseen) before "Alpha" (1).
    expect(tester.getTopLeft(find.text('Zebra')).dy, lessThan(tester.getTopLeft(find.text('Alpha')).dy));

    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    // CheckedPopupMenuItem's leading checkmark shifts the text's hit-test
    // center slightly outside its own bounds at this viewport size --
    // harmless, same non-fatal warning every CheckedPopupMenuItem tap gets.
    await tester.tap(find.text('Label (A-Z)'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('Alpha')).dy, lessThan(tester.getTopLeft(find.text('Zebra')).dy));

    final store = const DisplaySettingsStore();
    expect(await store.loadSearchSortOrder(), SearchSortOrder.label);
  });

  testWidgets('last-viewed sort orders by lastViewedAt descending, and opening a search bumps it to the top (M15)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final alphaId = await repository.createSearch(BunnySite.e621, 'Alpha', 'alpha');
    final zebraId = await repository.createSearch(BunnySite.e621, 'Zebra', 'zebra');

    void setLastViewed(int searchId, String? timestamp) {
      final index = repository.searches.indexWhere((search) => search.id == searchId);
      final search = repository.searches[index];
      repository.searches[index] = BunnySearch(
        id: search.id,
        site: search.site,
        label: search.label,
        query: search.query,
        intervalHours: search.intervalHours,
        createdAt: search.createdAt,
        lastViewedAt: timestamp,
      );
    }

    setLastViewed(alphaId, '2026-01-01T00:00:00Z');
    setLastViewed(zebraId, null);

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last viewed'), warnIfMissed: false);
    await tester.pumpAndSettle();

    // Alpha has a real lastViewedAt; Zebra has never been viewed (null sorts
    // last).
    expect(tester.getTopLeft(find.text('Alpha')).dy, lessThan(tester.getTopLeft(find.text('Zebra')).dy));

    // Opening a search records it as viewed immediately (fire-and-forget,
    // doesn't wait on navigation) -- same hook backs the Pools tab since
    // pools are just BunnySearch rows filtered by query prefix.
    await tester.tap(find.text('Zebra'));
    expect(repository.searches.firstWhere((search) => search.id == zebraId).lastViewedAt, isNotNull);
    await tester.pumpAndSettle();

    // Back on the list (returning from PostGridScreen refreshes it), Zebra
    // now sorts above Alpha.
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('Zebra')).dy, lessThan(tester.getTopLeft(find.text('Alpha')).dy));
  });

  testWidgets('last-updated sort orders by lastUpdatedAt descending, distinct from lastViewedAt (M69)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final alphaId = await repository.createSearch(BunnySite.e621, 'Alpha', 'alpha');
    final zebraId = await repository.createSearch(BunnySite.e621, 'Zebra', 'zebra');

    void setLastUpdated(int searchId, String? timestamp) {
      final index = repository.searches.indexWhere((search) => search.id == searchId);
      final search = repository.searches[index];
      repository.searches[index] = BunnySearch(
        id: search.id,
        site: search.site,
        label: search.label,
        query: search.query,
        intervalHours: search.intervalHours,
        createdAt: search.createdAt,
        // Deliberately the opposite of lastUpdatedAt below -- proves the
        // sort uses lastUpdatedAt, not lastViewedAt.
        lastViewedAt: searchId == zebraId ? '2026-01-01T00:00:00Z' : null,
        lastUpdatedAt: timestamp,
      );
    }

    setLastUpdated(alphaId, '2026-02-01T00:00:00Z');
    setLastUpdated(zebraId, null);

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last updated'), warnIfMissed: false);
    await tester.pumpAndSettle();

    // Alpha has a real lastUpdatedAt; Zebra has never had one (null sorts
    // last), even though Zebra has the more recent lastViewedAt.
    expect(tester.getTopLeft(find.text('Alpha')).dy, lessThan(tester.getTopLeft(find.text('Zebra')).dy));
  });

  testWidgets('shows a "last updated" indicator on a row that has one, not on one that never has (M69)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final updatedId = await repository.createSearch(BunnySite.e621, 'Foxes', 'fox');
    await repository.createSearch(BunnySite.e621, 'Wolves', 'wolf');

    final index = repository.searches.indexWhere((search) => search.id == updatedId);
    final search = repository.searches[index];
    repository.searches[index] = BunnySearch(
      id: search.id,
      site: search.site,
      label: search.label,
      query: search.query,
      intervalHours: search.intervalHours,
      createdAt: search.createdAt,
      lastUpdatedAt: DateTime.now().toUtc().subtract(const Duration(hours: 3)).toIso8601String(),
    );

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    expect(find.textContaining('Updated'), findsOneWidget);
    expect(
      find.descendant(of: find.widgetWithText(ListTile, 'Foxes'), matching: find.textContaining('Updated')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.widgetWithText(ListTile, 'Wolves'), matching: find.textContaining('Updated')),
      findsNothing,
    );
  });

  testWidgets('tapping "check for updates" syncs every search and re-enables the button when done (M13.2)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final id1 = await repository.createSearch(BunnySite.e621, 'Foxes', 'fox');
    final id2 = await repository.createSearch(BunnySite.e621, 'Wolves', 'wolf');

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.sync));
    await tester.pumpAndSettle();

    expect(repository.syncSearchCalls, containsAll([id1, id2]));
    expect(repository.syncSearchCalls, hasLength(2));
    // Back to the normal sync icon, tappable again -- not left stuck on
    // the spinner.
    final button = tester.widget<IconButton>(find.ancestor(of: find.byIcon(Icons.sync), matching: find.byType(IconButton)));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('"check for updates" keeps going past a single search failing (M13.2)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final id1 = await repository.createSearch(BunnySite.e621, 'Foxes', 'fox');
    final id2 = await repository.createSearch(BunnySite.e621, 'Wolves', 'wolf');
    repository.syncSearchFailures[id1] = 'network error';

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.sync));
    await tester.pumpAndSettle();

    expect(repository.syncSearchCalls, [id1, id2]);
  });

  testWidgets('"check for updates" refreshes unseen badges from periodic status polling, not only at the end (M14.3, M20)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final id1 = await repository.createSearch(BunnySite.e621, 'Foxes', 'fox');
    final id2 = await repository.createSearch(BunnySite.e621, 'Wolves', 'wolf');
    final gate1 = Completer<void>();
    final gate2 = Completer<void>();
    repository.syncSearchGates[id1] = gate1;
    repository.syncSearchGates[id2] = gate2;
    repository.syncSearchNewPosts[id1] = [
      const BunnyPost(id: 101, site: BunnySite.e621, externalId: 101, score: 0, favCount: 0, commentCount: 0, width: 100, height: 100, cachedAt: '2026-01-01T00:00:00Z', isSeen: false, isFavorited: false),
    ];
    repository.syncSearchNewPosts[id2] = [
      const BunnyPost(id: 102, site: BunnySite.e621, externalId: 102, score: 0, favCount: 0, commentCount: 0, width: 100, height: 100, cachedAt: '2026-01-01T00:00:00Z', isSeen: false, isFavorited: false),
    ];

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.sync));
    await tester.pump();

    // Neither search has synced yet -- no badges.
    expect(find.text('1'), findsNothing);

    gate1.complete();
    // "check for updates" calls syncAllSearches() as a single call that
    // doesn't resolve until the whole batch (gate1 AND gate2) finishes --
    // progress is instead surfaced by SearchesScreen's independent 2s
    // getSyncStatus() poll timer (M20), which runs concurrently and already
    // sees postsBySearchId updated for Foxes even though syncAllSearches()
    // itself is still blocked on gate2.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    // Foxes' sync resolved and found a post -- its badge should already be
    // visible even though Wolves' sync (gated on gate2) hasn't resolved yet.
    expect(find.text('1'), findsOneWidget);

    gate2.complete();
    await tester.pumpAndSettle();

    expect(find.text('1'), findsNWidgets(2));
  });

  testWidgets('tapping the FAB opens CreateSearchScreen and refreshes on success', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('New search'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Label'), 'Foxes');
    await tester.enterText(find.widgetWithText(TextFormField, 'Query'), 'fox');
    // The group picker (M21) and the e621 metatags panel (shown by default)
    // can push the Create button below the fold.
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Create'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('Foxes'), findsOneWidget);
    expect(repository.searches, hasLength(1));
  });

  testWidgets('pool searches only show up in the Pools tab, regular searches only in the Searches tab', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    await repository.createSearch(BunnySite.e621, 'Foxes', 'fox');
    await repository.createSearch(BunnySite.e621, 'a_pool', 'pool:5');

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    expect(find.text('Foxes'), findsOneWidget);
    expect(find.text('a_pool'), findsNothing);

    await tester.tap(find.text('Pools'));
    await tester.pumpAndSettle();

    expect(find.text('a_pool'), findsOneWidget);
    expect(find.text('Foxes'), findsNothing);
  });

  testWidgets('a favorites search (the AccountsScreen-managed sentinel, M30) is hidden from the Searches tab', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    await repository.createSearch(BunnySite.e621, 'Foxes', 'fox');
    await repository.createSearch(BunnySite.e621, 'Favorites', 'fav:someuser');

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    expect(find.text('Foxes'), findsOneWidget);
    expect(find.text('Favorites'), findsNothing);
  });

  testWidgets('shows the pools empty state on the Pools tab when there are no pool searches', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    await repository.createSearch(BunnySite.e621, 'Foxes', 'fox');

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pools'));
    await tester.pumpAndSettle();

    expect(find.text('No saved pools yet. Tap + to add one.'), findsOneWidget);
  });

  testWidgets('tapping the FAB on the Pools tab opens the add-pool dialog and uses the fetched pool name as the label', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.poolInfoById[5] = const BunnyPoolInfo(id: 5, name: 'a_fetched_pool', postCount: 3);

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pools'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('Add pool'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Pool ID'), '5');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(find.text('a_fetched_pool'), findsOneWidget);
    expect(repository.searches, hasLength(1));
    expect(repository.searches.single.query, 'pool:5');
  });

  testWidgets('add-pool dialog falls back to a default label when the pool lookup fails', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    // No poolInfoById[5] seeded -- fetchPool throws.

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pools'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Pool ID'), '5');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(find.text('pool:5'), findsOneWidget);
    expect(repository.searches, hasLength(1));
  });

  testWidgets('add-pool dialog creates an Inkbunny pool search with a bare id label when no name is known locally (M28/M76)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.poolInfoById[108216] = const BunnyPoolInfo(id: 108216, name: 'should never be used', postCount: 20);

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pools'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('Add pool'), findsOneWidget);

    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Inkbunny')));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Pool ID'), '108216');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    // Never attempted the e621-only lookup -- it would risk showing an
    // unrelated e621 pool's name if the numeric id happened to collide.
    // getInkbunnyPoolName (M76) IS attempted, but nothing's cached for this
    // pool id yet, so it falls back to the bare id label, same as always.
    expect(repository.fetchPoolCallCount, 0);
    expect(find.text('pool:108216'), findsOneWidget);
    expect(repository.searches, hasLength(1));
    expect(repository.searches.single.site, BunnySite.inkbunny);
    expect(repository.searches.single.query, 'pool:108216');
    expect(repository.searches.single.usesDefaultInterval, isTrue);
  });

  testWidgets('add-pool dialog backfills an Inkbunny pool search\'s label from a name already known locally (M76)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.inkbunnyPoolNameById[108216] = 'Sleepover Party';

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pools'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Inkbunny')));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Pool ID'), '108216');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(find.text('Sleepover Party'), findsOneWidget);
    expect(repository.searches.single.label, 'Sleepover Party');
    expect(repository.searches.single.query, 'pool:108216');
  });

  testWidgets('add-pool dialog refuses a pool that is already saved (M38)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    await repository.createSearch(BunnySite.e621, 'a_pool', 'pool:5', usesDefaultInterval: true);

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pools'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Pool ID'), '5');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(find.text('This pool is already saved.'), findsOneWidget);
    expect(repository.searches, hasLength(1));
    expect(repository.fetchPoolCallCount, 0);
  });

  testWidgets('assigning a search to a group nests it under an expandable group row (M21)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    await repository.createSearch(BunnySite.e621, 'Alpha', 'alpha');
    await repository.createSearch(BunnySite.e621, 'Beta', 'beta');

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Canines');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(repository.groups, hasLength(1));
    // No member searches yet in this tab, so the group itself isn't shown.
    expect(find.text('Canines'), findsNothing);

    await tester.longPress(find.widgetWithText(ListTile, 'Alpha'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Canines').last);
    await tester.pumpAndSettle();

    // The e621 metatags panel (shown by default) can push the Save button
    // below the test surface's default Sliver layout-cache extent.
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Canines'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);

    await tester.tap(find.text('Canines'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('pinning a group sorts it above unpinned searches (M21)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final alphaId = await repository.createSearch(BunnySite.e621, 'Alpha', 'alpha');
    await repository.createSearch(BunnySite.e621, 'Beta', 'beta');
    final groupId = await repository.createGroup('Canines', false);
    await repository.setSearchGroup(alphaId, groupId);

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('Beta')).dy, lessThan(tester.getTopLeft(find.text('Canines')).dy));

    final groupPinButton = find.descendant(of: find.widgetWithText(ExpansionTile, 'Canines'), matching: find.byIcon(Icons.push_pin_outlined));
    await tester.tap(groupPinButton);
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('Canines')).dy, lessThan(tester.getTopLeft(find.text('Beta')).dy));
  });

  testWidgets('deleting a group ungroups its member search instead of removing it (M21)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final alphaId = await repository.createSearch(BunnySite.e621, 'Alpha', 'alpha');
    final groupId = await repository.createGroup('Canines', false);
    await repository.setSearchGroup(alphaId, groupId);

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    expect(find.text('Canines'), findsOneWidget);

    await tester.tap(find.descendant(of: find.widgetWithText(ExpansionTile, 'Canines'), matching: find.byType(PopupMenuButton<String>)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete group'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(find.text('Canines'), findsNothing);
    expect(repository.searches.single.groupId, 0);
    expect(find.text('Alpha'), findsOneWidget);
  });

  group('duplicate searches banner (M41)', () {
    testWidgets('shows a banner when two searches share the same (site, query)', (WidgetTester tester) async {
      final repository = FakeBunnyRepository();
      await repository.createSearch(BunnySite.e621, 'Wolves', 'wolf');
      await repository.createSearch(BunnySite.e621, 'Wolves (dupe)', 'wolf', intervalHours: 48);

      await tester.pumpWidget(_wrap(repository));
      await tester.pumpAndSettle();

      expect(find.text('1 duplicate searches found.'), findsOneWidget);
    });

    testWidgets('shows no banner when no searches are duplicated', (WidgetTester tester) async {
      final repository = FakeBunnyRepository();
      await repository.createSearch(BunnySite.e621, 'Wolves', 'wolf');
      await repository.createSearch(BunnySite.e621, 'Foxes', 'fox');

      await tester.pumpWidget(_wrap(repository));
      await tester.pumpAndSettle();

      expect(find.textContaining('duplicate searches found'), findsNothing);
    });

    testWidgets('dismissing the banner hides it', (WidgetTester tester) async {
      final repository = FakeBunnyRepository();
      await repository.createSearch(BunnySite.e621, 'Wolves', 'wolf');
      await repository.createSearch(BunnySite.e621, 'Wolves (dupe)', 'wolf', intervalHours: 48);

      await tester.pumpWidget(_wrap(repository));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
      await tester.pumpAndSettle();

      expect(find.textContaining('duplicate searches found'), findsNothing);
    });

    testWidgets('reviewing and keeping one search merges the other duplicate into it', (WidgetTester tester) async {
      final repository = FakeBunnyRepository();
      final keeperId = await repository.createSearch(BunnySite.e621, 'Wolves', 'wolf');
      await repository.createSearch(BunnySite.e621, 'Wolves (dupe)', 'wolf', intervalHours: 48);

      await tester.pumpWidget(_wrap(repository));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();

      expect(find.text('Wolves'), findsWidgets);
      expect(find.text('Wolves (dupe)'), findsWidgets);

      await tester.tap(find.widgetWithText(TextButton, 'Keep this one').first);
      await tester.pumpAndSettle();

      // Only two duplicates existed, so resolving the group closes the
      // dialog on its own, back to the main list with just the keeper left.
      expect(find.text('Duplicate searches'), findsNothing);
      expect(repository.searches, hasLength(1));
      expect(repository.searches.single.id, keeperId);
      expect(find.textContaining('duplicate searches found'), findsNothing);
    });
  });

  group('finder (local filter over saved searches/pools)', () {
    testWidgets('the finder field is hidden until the search icon is tapped', (WidgetTester tester) async {
      final repository = FakeBunnyRepository();
      await repository.createSearch(BunnySite.e621, 'Foxes', 'fox');

      await tester.pumpWidget(_wrap(repository));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.byTooltip('Find a saved search or pool'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('typing filters the Searches tab by label or query text', (WidgetTester tester) async {
      final repository = FakeBunnyRepository();
      await repository.createSearch(BunnySite.e621, 'Foxes', 'fox');
      await repository.createSearch(BunnySite.e621, 'Wolves', 'wolf');

      await tester.pumpWidget(_wrap(repository));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Find a saved search or pool'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'wolf');
      await tester.pumpAndSettle();

      expect(find.text('Foxes'), findsNothing);
      expect(find.text('Wolves'), findsOneWidget);
    });

    testWidgets('typing a pool id finds that pool even when it is not in the label or query text', (WidgetTester tester) async {
      final repository = FakeBunnyRepository();
      await repository.createSearch(BunnySite.e621, 'A nice comic', 'pool:108216');
      await repository.createSearch(BunnySite.e621, 'Another pool', 'pool:5');

      await tester.pumpWidget(_wrap(repository));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pools'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Find a saved search or pool'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '108216');
      await tester.pumpAndSettle();

      expect(find.text('A nice comic'), findsOneWidget);
      expect(find.text('Another pool'), findsNothing);
    });

    testWidgets('clearing the filter shows every search again', (WidgetTester tester) async {
      final repository = FakeBunnyRepository();
      await repository.createSearch(BunnySite.e621, 'Foxes', 'fox');
      await repository.createSearch(BunnySite.e621, 'Wolves', 'wolf');

      await tester.pumpWidget(_wrap(repository));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Find a saved search or pool'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'wolf');
      await tester.pumpAndSettle();
      expect(find.text('Foxes'), findsNothing);

      await tester.tap(find.byTooltip('Clear'));
      await tester.pumpAndSettle();

      expect(find.text('Foxes'), findsOneWidget);
      expect(find.text('Wolves'), findsOneWidget);
    });

    testWidgets('no matches shows the finder-specific empty state instead of the generic one', (WidgetTester tester) async {
      final repository = FakeBunnyRepository();
      await repository.createSearch(BunnySite.e621, 'Foxes', 'fox');

      await tester.pumpWidget(_wrap(repository));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Find a saved search or pool'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'nonexistent');
      await tester.pumpAndSettle();

      expect(find.text('Nothing matches "nonexistent".'), findsOneWidget);
    });
  });

  testWidgets('skips the automatic update check when auto-check is disabled', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'update_auto_check_enabled': false});
    final checkService = UpdateCheckService(
      currentBuildNumber: 10,
      client: MockClient((_) async => http.Response('{"tag_name":"build-42","assets":[{"name":"little-bunny-${UpdateCheckService.assetSuffixForPlatform()}","browser_download_url":"https://example.invalid/asset"}]}', 200)),
    );

    await tester.pumpWidget(_wrap(FakeBunnyRepository(), updateCheckService: checkService));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('runs the automatic update check when auto-check is enabled (the default)', (WidgetTester tester) async {
    final checkService = UpdateCheckService(
      currentBuildNumber: 10,
      client: MockClient((_) async => http.Response('{"tag_name":"build-42","assets":[{"name":"little-bunny-${UpdateCheckService.assetSuffixForPlatform()}","browser_download_url":"https://example.invalid/asset"}]}', 200)),
    );

    await tester.pumpWidget(_wrap(FakeBunnyRepository(), updateCheckService: checkService));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
  });
}
