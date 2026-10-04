import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/screens/settings_screen.dart';
import 'package:little_bunny/settings/app_lock_service.dart';
import 'package:little_bunny/settings/sync_settings_store.dart';
import 'package:little_bunny/settings/theme_settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_secret_store.dart';
import '../fakes/test_app.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows the persisted theme mode selected', (WidgetTester tester) async {
    const themeStore = ThemeSettingsStore();
    await themeStore.save(ThemeMode.light);

    await tester.pumpWidget(wrapWithLocalization(SettingsScreen(themeSettingsStore: themeStore, lockService: AppLockService(FakeSecretStore()), syncSettingsStore: const SyncSettingsStore(), onThemeModeChanged: (_) {})));
    await tester.pumpAndSettle();

    final button = tester.widget<SegmentedButton<ThemeMode>>(find.byType(SegmentedButton<ThemeMode>));
    expect(button.selected, {ThemeMode.light});
  });

  testWidgets('picking a theme mode persists it and notifies the callback', (WidgetTester tester) async {
    const themeStore = ThemeSettingsStore();
    ThemeMode? notified;

    await tester.pumpWidget(wrapWithLocalization(SettingsScreen(themeSettingsStore: themeStore, lockService: AppLockService(FakeSecretStore()), syncSettingsStore: const SyncSettingsStore(), onThemeModeChanged: (mode) => notified = mode)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();

    expect(notified, ThemeMode.light);
    expect(await themeStore.load(), ThemeMode.light);
  });

  testWidgets('tapping the app lock entry opens LockSetupScreen', (WidgetTester tester) async {
    await tester.pumpWidget(wrapWithLocalization(SettingsScreen(themeSettingsStore: const ThemeSettingsStore(), lockService: AppLockService(FakeSecretStore()), syncSettingsStore: const SyncSettingsStore(), onThemeModeChanged: (_) {})));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Manage app lock'));
    await tester.pumpAndSettle();

    expect(find.text('App lock'), findsOneWidget);
  });

  testWidgets('shows the persisted default sync interval', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'default_sync_interval_hours': 48});

    await tester.pumpWidget(
      wrapWithLocalization(
        SettingsScreen(themeSettingsStore: const ThemeSettingsStore(), lockService: AppLockService(FakeSecretStore()), syncSettingsStore: const SyncSettingsStore(), onThemeModeChanged: (_) {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Default sync interval (hours)')).controller!.text, '48');
  });

  testWidgets('editing the default sync interval persists it', (WidgetTester tester) async {
    const syncStore = SyncSettingsStore();

    await tester.pumpWidget(
      wrapWithLocalization(SettingsScreen(themeSettingsStore: const ThemeSettingsStore(), lockService: AppLockService(FakeSecretStore()), syncSettingsStore: syncStore, onThemeModeChanged: (_) {})),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Default sync interval (hours)'), '12');
    await tester.pump();

    expect(await syncStore.loadDefaultIntervalHours(), 12);
  });
}
