import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/screens/settings_screen.dart';
import 'package:little_bunny/settings/app_lock_service.dart';
import 'package:little_bunny/settings/display_settings_store.dart';
import 'package:little_bunny/settings/download_settings_store.dart';
import 'package:little_bunny/settings/repository_settings_store.dart';
import 'package:little_bunny/settings/theme_settings_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_bunny_repository.dart';
import '../fakes/fake_path_provider.dart';
import '../fakes/fake_secret_store.dart';
import '../fakes/test_app.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PathProviderPlatform.instance = FakePathProviderPlatform();
  });

  RepositorySettingsStore settingsStore() => RepositorySettingsStore(FakeSecretStore());

  testWidgets('shows the persisted theme mode selected', (WidgetTester tester) async {
    const themeStore = ThemeSettingsStore();
    await themeStore.save(ThemeMode.light);

    await tester.pumpWidget(
      wrapWithLocalization(
        SettingsScreen(
          repository: FakeBunnyRepository(),
          themeSettingsStore: themeStore,
          lockService: AppLockService(FakeSecretStore()),
          downloadSettingsStore: const DownloadSettingsStore(),
          displaySettingsStore: const DisplaySettingsStore(),
          settingsStore: settingsStore(),
          onThemeModeChanged: (_) {},
          onRepositoryConfigured: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final button = tester.widget<SegmentedButton<ThemeMode>>(find.byType(SegmentedButton<ThemeMode>));
    expect(button.selected, {ThemeMode.light});
  });

  testWidgets('picking a theme mode persists it and notifies the callback', (WidgetTester tester) async {
    const themeStore = ThemeSettingsStore();
    ThemeMode? notified;

    await tester.pumpWidget(
      wrapWithLocalization(
        SettingsScreen(
          repository: FakeBunnyRepository(),
          themeSettingsStore: themeStore,
          lockService: AppLockService(FakeSecretStore()),
          downloadSettingsStore: const DownloadSettingsStore(),
          displaySettingsStore: const DisplaySettingsStore(),
          settingsStore: settingsStore(),
          onThemeModeChanged: (mode) => notified = mode,
          onRepositoryConfigured: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();

    expect(notified, ThemeMode.light);
    expect(await themeStore.load(), ThemeMode.light);
  });

  testWidgets('tapping the app lock entry opens LockSetupScreen', (WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithLocalization(
        SettingsScreen(
          repository: FakeBunnyRepository(),
          themeSettingsStore: const ThemeSettingsStore(),
          lockService: AppLockService(FakeSecretStore()),
          downloadSettingsStore: const DownloadSettingsStore(),
          displaySettingsStore: const DisplaySettingsStore(),
          settingsStore: settingsStore(),
          onThemeModeChanged: (_) {},
          onRepositoryConfigured: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The Downloads section (M9.4) pushed "Manage app lock" past the
    // ListView's default build cache extent in the test viewport -- scroll
    // it into view first so the sliver actually materializes that element.
    await tester.dragUntilVisible(find.text('Manage app lock'), find.byType(ListView), const Offset(0, -100));
    await tester.tap(find.text('Manage app lock'));
    await tester.pumpAndSettle();

    expect(find.text('App lock'), findsOneWidget);
  });

  testWidgets('shows the persisted default sync interval', (WidgetTester tester) async {
    final repository = FakeBunnyRepository()..defaultSyncIntervalHours = 48;

    await tester.pumpWidget(
      wrapWithLocalization(
        SettingsScreen(
          repository: repository,
          themeSettingsStore: const ThemeSettingsStore(),
          lockService: AppLockService(FakeSecretStore()),
          downloadSettingsStore: const DownloadSettingsStore(),
          displaySettingsStore: const DisplaySettingsStore(),
          settingsStore: settingsStore(),
          onThemeModeChanged: (_) {},
          onRepositoryConfigured: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Default sync interval (hours)')).controller!.text, '48');
  });

  testWidgets('editing the default sync interval persists it (M20 -- server-side, not local-only)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();

    await tester.pumpWidget(
      wrapWithLocalization(
        SettingsScreen(
          repository: repository,
          themeSettingsStore: const ThemeSettingsStore(),
          lockService: AppLockService(FakeSecretStore()),
          displaySettingsStore: const DisplaySettingsStore(),
          downloadSettingsStore: const DownloadSettingsStore(),
          settingsStore: settingsStore(),
          onThemeModeChanged: (_) {},
          onRepositoryConfigured: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Default sync interval (hours)'), '12');
    await tester.pump();

    expect(await repository.getDefaultSyncIntervalHours(), 12);
  });

  testWidgets('shows the persisted preview quality and grid columns', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'preview_quality': 'medium', 'grid_columns': 4});

    await tester.pumpWidget(
      wrapWithLocalization(
        SettingsScreen(
          repository: FakeBunnyRepository(),
          themeSettingsStore: const ThemeSettingsStore(),
          lockService: AppLockService(FakeSecretStore()),
          downloadSettingsStore: const DownloadSettingsStore(),
          displaySettingsStore: const DisplaySettingsStore(),
          settingsStore: settingsStore(),
          onThemeModeChanged: (_) {},
          onRepositoryConfigured: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final button = tester.widget<SegmentedButton<PreviewQuality>>(find.byType(SegmentedButton<PreviewQuality>));
    expect(button.selected, {PreviewQuality.medium});
    expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Grid columns')).controller!.text, '4');
  });

  testWidgets('toggling auto-favorite on download persists it (M10.1)', (WidgetTester tester) async {
    const downloadStore = DownloadSettingsStore();

    await tester.pumpWidget(
      wrapWithLocalization(
        SettingsScreen(
          repository: FakeBunnyRepository(),
          themeSettingsStore: const ThemeSettingsStore(),
          lockService: AppLockService(FakeSecretStore()),
          downloadSettingsStore: downloadStore,
          displaySettingsStore: const DisplaySettingsStore(),
          settingsStore: settingsStore(),
          onThemeModeChanged: (_) {},
          onRepositoryConfigured: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(await downloadStore.loadAutoFavoriteOnDownload(), isFalse);

    // A generous fixed scroll (rather than dragUntilVisible's "just enough
    // to barely exist" stopping point) so the switch lands solidly inside
    // the test viewport rather than clipped at its edge, where a tap can
    // silently miss (M15 added a Connection section above this one, pushing
    // it further down than when this test was first written).
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, 'Auto-favorite on download'));
    await tester.pumpAndSettle();

    expect(await downloadStore.loadAutoFavoriteOnDownload(), isTrue);
  });

  testWidgets('toggling auto-upvote on download persists it (M14.2)', (WidgetTester tester) async {
    const downloadStore = DownloadSettingsStore();

    await tester.pumpWidget(
      wrapWithLocalization(
        SettingsScreen(
          repository: FakeBunnyRepository(),
          themeSettingsStore: const ThemeSettingsStore(),
          lockService: AppLockService(FakeSecretStore()),
          downloadSettingsStore: downloadStore,
          displaySettingsStore: const DisplaySettingsStore(),
          settingsStore: settingsStore(),
          onThemeModeChanged: (_) {},
          onRepositoryConfigured: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(await downloadStore.loadAutoUpvoteOnDownload(), isFalse);

    await tester.dragUntilVisible(find.text('Auto-upvote on download'), find.byType(ListView), const Offset(0, -100));
    await tester.tap(find.widgetWithText(SwitchListTile, 'Auto-upvote on download'));
    await tester.pumpAndSettle();

    expect(await downloadStore.loadAutoUpvoteOnDownload(), isTrue);
  });

  testWidgets('picking a preview quality and editing grid columns persists both', (WidgetTester tester) async {
    const displayStore = DisplaySettingsStore();

    await tester.pumpWidget(
      wrapWithLocalization(
        SettingsScreen(
          repository: FakeBunnyRepository(),
          themeSettingsStore: const ThemeSettingsStore(),
          lockService: AppLockService(FakeSecretStore()),
          downloadSettingsStore: const DownloadSettingsStore(),
          displaySettingsStore: displayStore,
          settingsStore: settingsStore(),
          onThemeModeChanged: (_) {},
          onRepositoryConfigured: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Medium'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Grid columns'), '5');
    await tester.pump();

    expect(await displayStore.loadPreviewQuality(), PreviewQuality.medium);
    expect(await displayStore.loadGridColumns(), 5);
  });

  testWidgets('blacklist editor adds/removes tags per site (M13.3)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.blacklistBySite[BunnySite.inkbunny] = {'gore'};

    await tester.pumpWidget(
      wrapWithLocalization(
        SettingsScreen(
          repository: repository,
          themeSettingsStore: const ThemeSettingsStore(),
          lockService: AppLockService(FakeSecretStore()),
          downloadSettingsStore: const DownloadSettingsStore(),
          displaySettingsStore: const DisplaySettingsStore(),
          settingsStore: settingsStore(),
          onThemeModeChanged: (_) {},
          onRepositoryConfigured: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(find.text('Add tag'), find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();

    expect(find.text('No blacklisted tags yet.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Add tag'), 'young');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('young'), findsOneWidget);
    expect(await repository.getBlacklist(BunnySite.e621), ['young']);
    // Inkbunny's own list must stay untouched by an e621 addition.
    expect(await repository.getBlacklist(BunnySite.inkbunny), ['gore']);

    await tester.tap(find.text('Inkbunny').last);
    await tester.pumpAndSettle();

    expect(find.text('gore'), findsOneWidget);
    expect(find.text('young'), findsNothing);

    await tester.tap(find.descendant(of: find.widgetWithText(Chip, 'gore'), matching: find.byIcon(Icons.cancel)));
    await tester.pumpAndSettle();

    expect(find.text('gore'), findsNothing);
    expect(await repository.getBlacklist(BunnySite.inkbunny), isEmpty);
  });

  testWidgets('Connection section shows the persisted mode (M15)', (WidgetTester tester) async {
    final store = settingsStore();
    await store.saveStandalone();

    await tester.pumpWidget(
      wrapWithLocalization(
        SettingsScreen(
          repository: FakeBunnyRepository(),
          themeSettingsStore: const ThemeSettingsStore(),
          lockService: AppLockService(FakeSecretStore()),
          downloadSettingsStore: const DownloadSettingsStore(),
          displaySettingsStore: const DisplaySettingsStore(),
          settingsStore: store,
          onThemeModeChanged: (_) {},
          onRepositoryConfigured: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Standalone'), findsOneWidget);
  });

  testWidgets('tapping "Switch connection mode" opens the reconfigure screen (M15)', (WidgetTester tester) async {
    final store = settingsStore();
    await store.saveStandalone();

    await tester.pumpWidget(
      wrapWithLocalization(
        SettingsScreen(
          repository: FakeBunnyRepository(),
          themeSettingsStore: const ThemeSettingsStore(),
          lockService: AppLockService(FakeSecretStore()),
          downloadSettingsStore: const DownloadSettingsStore(),
          displaySettingsStore: const DisplaySettingsStore(),
          settingsStore: store,
          onThemeModeChanged: (_) {},
          onRepositoryConfigured: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Switch connection mode'));
    await tester.pumpAndSettle();

    expect(find.text('Switch connection'), findsOneWidget);
  });
}
