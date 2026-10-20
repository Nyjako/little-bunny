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
          onThemeColorChanged: (_) {},
          onAmoledChanged: (_) {},
          onLanguageCodeChanged: (_) {},
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
          onThemeColorChanged: (_) {},
          onAmoledChanged: (_) {},
          onLanguageCodeChanged: (_) {},
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

  testWidgets('picking a theme color and toggling AMOLED persists both and notifies the callbacks (M27)', (WidgetTester tester) async {
    const themeStore = ThemeSettingsStore();
    ThemeColorOption? notifiedColor;
    bool? notifiedAmoled;

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
          onThemeColorChanged: (color) => notifiedColor = color,
          onAmoledChanged: (amoled) => notifiedAmoled = amoled,
          onLanguageCodeChanged: (_) {},
          onRepositoryConfigured: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Blue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AMOLED (true black) dark mode'));
    await tester.pumpAndSettle();

    expect(notifiedColor, ThemeColorOption.blue);
    expect(notifiedAmoled, isTrue);
    expect(await themeStore.loadColor(), ThemeColorOption.blue);
    expect(await themeStore.loadAmoled(), isTrue);
  });

  testWidgets('picking a language persists it and notifies the callback, defaulting to "System default" (M30)', (WidgetTester tester) async {
    const themeStore = ThemeSettingsStore();
    String? notified = 'not called yet';

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
          onThemeColorChanged: (_) {},
          onAmoledChanged: (_) {},
          onLanguageCodeChanged: (languageCode) => notified = languageCode,
          onRepositoryConfigured: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Color swatches + AMOLED switch (M27) push the language picker itself
    // past the initial render cache extent -- scroll it into view first,
    // same reasoning as the About entry's own dragUntilVisible further up.
    await tester.dragUntilVisible(find.byType(DropdownButtonFormField<String?>), find.byType(ListView), const Offset(0, -100));
    expect(find.text('System default'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();

    expect(notified, 'en');
    expect(await themeStore.loadLanguageCode(), 'en');
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
          onThemeColorChanged: (_) {},
          onAmoledChanged: (_) {},
          onLanguageCodeChanged: (_) {},
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

  testWidgets('tapping the about entry opens AboutScreen (M27)', (WidgetTester tester) async {
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
          onThemeColorChanged: (_) {},
          onAmoledChanged: (_) {},
          onLanguageCodeChanged: (_) {},
          onRepositoryConfigured: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(find.text('About LittleBunny'), find.byType(ListView), const Offset(0, -300));
    await tester.tap(find.text('About LittleBunny'));
    await tester.pumpAndSettle();

    expect(find.text('LittleBunny'), findsOneWidget);
    expect(find.text('Open source licenses'), findsOneWidget);

    await tester.tap(find.text('Open source licenses'));
    await tester.pumpAndSettle();

    expect(find.byType(LicensePage), findsOneWidget);
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
          onThemeColorChanged: (_) {},
          onAmoledChanged: (_) {},
          onLanguageCodeChanged: (_) {},
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
          onThemeColorChanged: (_) {},
          onAmoledChanged: (_) {},
          onLanguageCodeChanged: (_) {},
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
    SharedPreferences.setMockInitialValues({'preview_quality': 'medium', 'grid_columns': 4, 'image_preload_count': 5});

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
          onThemeColorChanged: (_) {},
          onAmoledChanged: (_) {},
          onLanguageCodeChanged: (_) {},
          onRepositoryConfigured: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The color swatches/AMOLED switch (M27) and the language picker (M30)
    // push the Preview Quality section itself past the initial render cache
    // extent now, not just "Grid columns" within it -- scroll before even
    // reading the SegmentedButton, same reasoning as the About entry's own
    // dragUntilVisible further up.
    await tester.dragUntilVisible(find.byType(SegmentedButton<PreviewQuality>), find.byType(ListView), const Offset(0, -100));
    final button = tester.widget<SegmentedButton<PreviewQuality>>(find.byType(SegmentedButton<PreviewQuality>));
    expect(button.selected, {PreviewQuality.medium});
    await tester.dragUntilVisible(find.widgetWithText(TextField, 'Grid columns'), find.byType(ListView), const Offset(0, -100));
    expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Grid columns')).controller!.text, '4');
    expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Images to preload (each direction)')).controller!.text, '5');
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
          onThemeColorChanged: (_) {},
          onAmoledChanged: (_) {},
          onLanguageCodeChanged: (_) {},
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
    // it further down than when this test was first written; M30's language
    // picker pushed it down again).
    await tester.drag(find.byType(ListView), const Offset(0, -500));
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
          onThemeColorChanged: (_) {},
          onAmoledChanged: (_) {},
          onLanguageCodeChanged: (_) {},
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

  testWidgets('picking a preview quality and editing grid columns/image preload count persists all three', (WidgetTester tester) async {
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
          onThemeColorChanged: (_) {},
          onAmoledChanged: (_) {},
          onLanguageCodeChanged: (_) {},
          onRepositoryConfigured: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The color swatches/AMOLED switch (M27) and the language picker (M30)
    // push "Medium" itself past the initial render cache extent now --
    // scroll before tapping it, same reasoning as the About entry's own
    // dragUntilVisible further up.
    await tester.dragUntilVisible(find.text('Medium'), find.byType(ListView), const Offset(0, -100));
    await tester.tap(find.text('Medium'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(find.widgetWithText(TextField, 'Grid columns'), find.byType(ListView), const Offset(0, -100));
    await tester.enterText(find.widgetWithText(TextField, 'Grid columns'), '5');
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Images to preload (each direction)'), '7');
    await tester.pump();

    expect(await displayStore.loadPreviewQuality(), PreviewQuality.medium);
    expect(await displayStore.loadGridColumns(), 5);
    expect(await displayStore.loadImagePreloadCount(), 7);
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
          onThemeColorChanged: (_) {},
          onAmoledChanged: (_) {},
          onLanguageCodeChanged: (_) {},
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

  testWidgets('"Sync from e621" pulls the blacklist and shows a result snackbar (M27)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.syncE621BlacklistResult = const BunnyBlacklistSyncStats(added: 2, alreadyPresent: 1, skippedMultiTag: 1);
    repository.blacklistBySite[BunnySite.e621] = {'brand_new', 'another_new'};

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
          onThemeColorChanged: (_) {},
          onAmoledChanged: (_) {},
          onLanguageCodeChanged: (_) {},
          onRepositoryConfigured: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(find.text('Sync from e621'), find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sync from e621'));
    await tester.pumpAndSettle();

    expect(repository.syncE621BlacklistCallCount, 1);
    expect(find.text('Added 2, 1 already present, skipped 1 multi-tag rule(s)'), findsOneWidget);
    expect(find.text('brand_new'), findsOneWidget);
    expect(find.text('another_new'), findsOneWidget);
  });

  testWidgets('"Sync from e621" is hidden on the Inkbunny blacklist tab', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();

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
          onThemeColorChanged: (_) {},
          onAmoledChanged: (_) {},
          onLanguageCodeChanged: (_) {},
          onRepositoryConfigured: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(find.text('Add tag'), find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inkbunny').last);
    await tester.pumpAndSettle();

    expect(find.text('Sync from e621'), findsNothing);
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
          onThemeColorChanged: (_) {},
          onAmoledChanged: (_) {},
          onLanguageCodeChanged: (_) {},
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
          onThemeColorChanged: (_) {},
          onAmoledChanged: (_) {},
          onLanguageCodeChanged: (_) {},
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
