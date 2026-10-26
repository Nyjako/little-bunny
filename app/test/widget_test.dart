import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/main.dart';
import 'package:little_bunny/services/download_manager.dart';
import 'package:little_bunny/services/download_queue_service.dart';
import 'package:little_bunny/settings/app_lock_service.dart';
import 'package:little_bunny/settings/display_settings_store.dart';
import 'package:little_bunny/settings/repository_settings_store.dart';
import 'package:little_bunny/settings/download_settings_store.dart';
import 'package:little_bunny/settings/theme_settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_secret_store.dart';

DownloadQueueService _downloadQueueService() => DownloadQueueService(downloadManager: const DownloadManager(), downloadSettingsStore: const DownloadSettingsStore());

void main() {
  testWidgets('app boots straight to the searches screen when already configured', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'repository_mode': 'networked', 'repository_server_url': 'https://localhost:9443'});
    final settingsStore = RepositorySettingsStore(FakeSecretStore({'repository_bearer_token': 'test-token', 'repository_cert_fingerprint': '00' * 32}));
    final lockService = AppLockService(FakeSecretStore());

    await tester.pumpWidget(LittleBunnyApp(settingsStore: settingsStore, lockService: lockService, themeSettingsStore: const ThemeSettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), displaySettingsStore: const DisplaySettingsStore(), downloadQueueService: _downloadQueueService()));
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

    await tester.pumpWidget(LittleBunnyApp(settingsStore: settingsStore, lockService: lockService, themeSettingsStore: const ThemeSettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), displaySettingsStore: const DisplaySettingsStore(), downloadQueueService: _downloadQueueService()));
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

    await tester.pumpWidget(LittleBunnyApp(settingsStore: settingsStore, lockService: lockService, themeSettingsStore: const ThemeSettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), displaySettingsStore: const DisplaySettingsStore(), downloadQueueService: _downloadQueueService()));
    await tester.pump();
    await tester.pump();

    expect(find.text('LittleBunny is locked'), findsOneWidget);
    expect(find.text('Searches'), findsNothing);
  });
}
