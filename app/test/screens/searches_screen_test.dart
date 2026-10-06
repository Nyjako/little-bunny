import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/bunny_repository_scope.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/screens/searches_screen.dart';
import 'package:little_bunny/settings/app_lock_service.dart';
import 'package:little_bunny/settings/display_settings_store.dart';
import 'package:little_bunny/settings/download_settings_store.dart';
import 'package:little_bunny/settings/sync_settings_store.dart';
import 'package:little_bunny/settings/theme_settings_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_bunny_repository.dart';
import '../fakes/fake_path_provider.dart';
import '../fakes/fake_secret_store.dart';
import '../fakes/test_app.dart';

Widget _wrap(FakeBunnyRepository repository) => wrapWithLocalization(
  BunnyRepositoryScope(
    repository: repository,
    child: SearchesScreen(
      lockService: AppLockService(FakeSecretStore()),
      themeSettingsStore: const ThemeSettingsStore(),
      syncSettingsStore: const SyncSettingsStore(),
      displaySettingsStore: const DisplaySettingsStore(),
      downloadSettingsStore: const DownloadSettingsStore(),
      onThemeModeChanged: (_) {},
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
    expect(find.text('e621 • every 6h'), findsOneWidget);
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

  testWidgets('tapping the auto-favorite icon toggles it on the search (M9.6.8)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    await repository.createSearch(BunnySite.e621, 'Foxes', 'fox');

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsNothing);

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pumpAndSettle();

    expect(repository.searches.single.autoFavorite, isTrue);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsNothing);

    await tester.tap(find.byIcon(Icons.favorite));
    await tester.pumpAndSettle();

    expect(repository.searches.single.autoFavorite, isFalse);
  });

  testWidgets('tapping remove then confirming deletes the search', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    await repository.createSearch(BunnySite.e621, 'Foxes', 'fox');

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete));
    await tester.pumpAndSettle();
    expect(find.text('Remove search?'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(repository.searches, isEmpty);
    expect(find.text('No saved searches yet. Tap + to add one.'), findsOneWidget);
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

  testWidgets('tapping the settings icon opens SettingsScreen', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(FakeBunnyRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
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
}
