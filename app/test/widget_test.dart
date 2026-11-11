import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/bunny_repository_scope.dart';
import 'package:little_bunny/l10n/app_localizations.dart';
import 'package:little_bunny/main.dart';
import 'package:little_bunny/screens/searches_screen.dart';
import 'package:little_bunny/services/download_manager.dart';
import 'package:little_bunny/services/download_queue_service.dart';
import 'package:little_bunny/settings/app_lock_service.dart';
import 'package:little_bunny/settings/display_settings_store.dart';
import 'package:little_bunny/settings/repository_settings_store.dart';
import 'package:little_bunny/settings/download_settings_store.dart';
import 'package:little_bunny/settings/theme_settings_store.dart';
import 'package:little_bunny/settings/update_settings_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_bunny_repository.dart';
import 'fakes/fake_path_provider.dart';
import 'fakes/fake_secret_store.dart';

DownloadQueueService _downloadQueueService() => DownloadQueueService(downloadManager: const DownloadManager(), downloadSettingsStore: const DownloadSettingsStore());

void main() {
  // RepositorySettingsStore.load()'s networked branch now also resolves a
  // local db path for HttpBunnyRepository's own small download-queue db
  // (M62 follow-up) via getApplicationSupportDirectory, even though these
  // tests never actually touch that db -- needs the same fake every other
  // test that loads a networked config already relies on.
  setUp(() {
    PathProviderPlatform.instance = FakePathProviderPlatform();
  });

  testWidgets('app boots straight to the searches screen when already configured', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'repository_mode': 'networked', 'repository_server_url': 'https://localhost:9443'});
    final settingsStore = RepositorySettingsStore(FakeSecretStore({'repository_bearer_token': 'test-token', 'repository_cert_fingerprint': '00' * 32}));
    final lockService = AppLockService(FakeSecretStore());

    await tester.pumpWidget(LittleBunnyApp(settingsStore: settingsStore, lockService: lockService, themeSettingsStore: const ThemeSettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), displaySettingsStore: const DisplaySettingsStore(), downloadQueueService: _downloadQueueService(), updateSettingsStore: const UpdateSettingsStore()));
    // Not pumpAndSettle(): SearchesScreen's own listSearches call goes through
    // a real HttpBunnyRepository against an unreachable localhost:9443 here,
    // which never cleanly "settles" under TestWidgetsFlutterBinding. Two
    // pumps are enough to get past settingsStore.load() (fakes only, no real
    // I/O) and render SearchesScreen's Scaffold/AppBar, which doesn't wait
    // on that future -- its own behavior with real search data is covered
    // by searches_screen_test.dart against a fake repository instead.
    await tester.pump();
    await tester.pump();

    // Two matches now: the AppBar title and the "Searches" tab label (M8.5.5
    // added a Pools tab alongside it).
    expect(find.text('Searches'), findsNWidgets(2));
    expect(find.text('Set up LittleBunny'), findsNothing);
  });

  testWidgets('app shows the setup screen on first launch (no persisted config)', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final settingsStore = RepositorySettingsStore(FakeSecretStore());
    final lockService = AppLockService(FakeSecretStore());

    await tester.pumpWidget(LittleBunnyApp(settingsStore: settingsStore, lockService: lockService, themeSettingsStore: const ThemeSettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), displaySettingsStore: const DisplaySettingsStore(), downloadQueueService: _downloadQueueService(), updateSettingsStore: const UpdateSettingsStore()));
    await tester.pumpAndSettle();

    expect(find.text('Set up LittleBunny'), findsOneWidget);
    expect(find.text('Standalone'), findsOneWidget);
    expect(find.text('Networked'), findsOneWidget);
  });

  testWidgets('app shows the lock screen when app-lock is enabled', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'repository_mode': 'networked', 'repository_server_url': 'https://localhost:9443', 'app_lock_enabled': true});
    final lockSecrets = FakeSecretStore({'app_lock_secret': 'my-pin'});
    final settingsStore = RepositorySettingsStore(FakeSecretStore({'repository_bearer_token': 'test-token', 'repository_cert_fingerprint': '00' * 32}));
    final lockService = AppLockService(lockSecrets);

    await tester.pumpWidget(LittleBunnyApp(settingsStore: settingsStore, lockService: lockService, themeSettingsStore: const ThemeSettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), displaySettingsStore: const DisplaySettingsStore(), downloadQueueService: _downloadQueueService(), updateSettingsStore: const UpdateSettingsStore()));
    await tester.pump();
    await tester.pump();

    expect(find.text('LittleBunny is locked'), findsOneWidget);
    expect(find.text('Searches'), findsNothing);
  });

  testWidgets(
    'opening the download queue screen from the real app and tapping its pause button does not crash (regression, M67)',
    (WidgetTester tester) async {
      // Reproduces main.dart's real structure directly -- BunnyRepositoryScope
      // wrapping the whole MaterialApp, not just `home` -- rather than going
      // through LittleBunnyApp itself, which always builds a real FFI/HTTP
      // BunnyRepository with no fake-injection seam. This used to wrap only
      // `home`'s own content, which made it an ancestor of the *first
      // route's* widget subtree only, not of the Navigator itself: a screen
      // reached via Navigator.push (like DownloadQueueScreen, opened below
      // exactly as SearchesScreen's own "Downloads" button does) sat in a
      // separate, sibling route subtree and had no ancestor to find, so
      // calling BunnyRepositoryScope.of(context) there threw a null-check
      // error. Every other test exercising DownloadQueueScreen wraps it
      // directly in its own standalone BunnyRepositoryScope (see
      // download_queue_screen_test.dart's `wrap()`), which is exactly
      // bug-shaped the same way the old main.dart was and never caught this.
      final repository = FakeBunnyRepository();
      final downloadQueueService = DownloadQueueService(downloadManager: const DownloadManager(), downloadSettingsStore: const DownloadSettingsStore());

      await tester.pumpWidget(
        BunnyRepositoryScope(
          repository: repository,
          child: MaterialApp(
            localizationsDelegates: const [AppLocalizations.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: SearchesScreen(
              lockService: AppLockService(FakeSecretStore()),
              themeSettingsStore: const ThemeSettingsStore(),
              displaySettingsStore: const DisplaySettingsStore(),
              downloadSettingsStore: const DownloadSettingsStore(),
              downloadQueueService: downloadQueueService,
              settingsStore: RepositorySettingsStore(FakeSecretStore()),
              updateSettingsStore: const UpdateSettingsStore(),
              onThemeModeChanged: (_) {},
              onThemeColorChanged: (_) {},
              onAmoledChanged: (_) {},
              onLanguageCodeChanged: (_) {},
              onRepositoryConfigured: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Downloads'));
      await tester.pumpAndSettle();
      expect(find.text('Downloads'), findsWidgets); // the opened screen's own AppBar title

      // Pausing alone doesn't touch BunnyRepositoryScope.of -- only the
      // "resume" tap below does (see the FAB's onPressed in
      // download_queue_screen.dart), which is the one that actually used to
      // crash.
      await tester.tap(find.byTooltip('Pause downloads'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(downloadQueueService.isPaused, isTrue);

      await tester.tap(find.byTooltip('Resume downloads'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(downloadQueueService.isPaused, isFalse);
    },
  );
}
