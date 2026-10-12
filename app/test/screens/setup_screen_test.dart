import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/repository/bunny_repository_factory.dart';
import 'package:little_bunny/screens/setup_screen.dart';
import 'package:little_bunny/settings/repository_settings_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_path_provider.dart';
import '../fakes/fake_secret_store.dart';
import '../fakes/test_app.dart';

// Only covers the parts of the reconfigure flow (M15) that don't require a
// real repository to actually come up: SetupScreen._submitStandalone/
// _submitNetworked call the real createBunnyRepository (real FFI/sqlite or a
// real HTTP connection check), which no screen-level test in this suite
// exercises end-to-end -- ffi_bunny_repository_test.dart covers the FFI side
// in isolation with an in-memory database instead. The cancel path below
// never reaches repository creation, so it's safe to test at this level.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PathProviderPlatform.instance = FakePathProviderPlatform();
  });

  testWidgets('reconfigure mode preselects the currently active mode (M15)', (WidgetTester tester) async {
    final store = RepositorySettingsStore(FakeSecretStore());
    await store.saveNetworked(serverBaseUrl: Uri.parse('https://example.test:8443'), bearerToken: 'tok', certificateSha256Fingerprint: 'fp');

    await tester.pumpWidget(wrapWithLocalization(SetupScreen(settingsStore: store, onConfigured: (_) {}, isReconfigure: true)));
    await tester.pumpAndSettle();

    expect(find.text('Switch connection'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Server URL'), findsOneWidget);
    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Server URL')).controller!.text, 'https://example.test:8443');
    // The secret fields are never prefilled.
    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Bearer token')).controller!.text, isEmpty);
  });

  testWidgets('reconfigure mode shows a warning before switching, and backs out on cancel (M15)', (WidgetTester tester) async {
    final store = RepositorySettingsStore(FakeSecretStore());
    await store.saveNetworked(serverBaseUrl: Uri.parse('https://example.test:8443'), bearerToken: 'tok', certificateSha256Fingerprint: 'fp');
    var configuredCount = 0;

    await tester.pumpWidget(wrapWithLocalization(SetupScreen(settingsStore: store, onConfigured: (_) => configuredCount++, isReconfigure: true)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Standalone'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Switch data source?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(configuredCount, 0);
    // Still on the setup screen, nothing persisted.
    expect(find.text('Switch connection'), findsOneWidget);
    expect(await store.load(), isA<NetworkedConfig>());
  });

  testWidgets('first-launch mode (isReconfigure: false) never shows the switch warning', (WidgetTester tester) async {
    final store = RepositorySettingsStore(FakeSecretStore());

    await tester.pumpWidget(wrapWithLocalization(SetupScreen(settingsStore: store, onConfigured: (_) {})));
    await tester.pumpAndSettle();

    expect(find.text('Set up LittleBunny'), findsOneWidget);

    // Switch to networked mode and submit an obviously-unreachable server --
    // checkServerConnection fails fast, so this exercises form validation
    // without needing a real repository to come up. The point here is only
    // that no "Switch data source?" dialog ever appears outside
    // isReconfigure, confirmed by its absence after the failed attempt.
    await tester.tap(find.text('Networked'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Server URL'), 'https://127.0.0.1:1');
    await tester.enterText(find.widgetWithText(TextFormField, 'Bearer token'), 'tok');
    await tester.enterText(find.widgetWithText(TextFormField, 'Certificate SHA-256 fingerprint'), 'fp');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('Switch data source?'), findsNothing);
  });
}
