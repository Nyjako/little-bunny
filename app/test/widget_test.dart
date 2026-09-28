import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/main.dart';
import 'package:little_bunny/settings/repository_settings_store.dart';
import 'package:little_bunny/settings/secret_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSecretStore implements SecretStore {
  final Map<String, String> values;

  _FakeSecretStore([Map<String, String>? initial]) : values = initial ?? {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  testWidgets('app boots straight to the accounts screen when already configured', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'repository_mode': 'networked', 'repository_server_url': 'https://localhost:9443'});
    final settingsStore = RepositorySettingsStore(_FakeSecretStore({'repository_bearer_token': 'test-token', 'repository_cert_fingerprint': '00' * 32}));

    await tester.pumpWidget(LittleBunnyApp(settingsStore: settingsStore));
    // Not pumpAndSettle(): AccountsScreen's own getAccount calls go through a
    // real HttpBunnyRepository against an unreachable localhost:9443 here,
    // which never cleanly "settles" under TestWidgetsFlutterBinding. Two
    // pumps are enough to get past settingsStore.load() (fakes only, no real
    // I/O) and render AccountsScreen's Scaffold/AppBar, which doesn't wait
    // on that future -- its own behavior with real account data is covered
    // by accounts_screen_test.dart against a fake repository instead.
    await tester.pump();
    await tester.pump();

    expect(find.text('Accounts'), findsOneWidget);
    expect(find.text('Set up LittleBunny'), findsNothing);
  });

  testWidgets('app shows the setup screen on first launch (no persisted config)', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final settingsStore = RepositorySettingsStore(_FakeSecretStore());

    await tester.pumpWidget(LittleBunnyApp(settingsStore: settingsStore));
    await tester.pumpAndSettle();

    expect(find.text('Set up LittleBunny'), findsOneWidget);
    expect(find.text('Standalone'), findsOneWidget);
    expect(find.text('Networked'), findsOneWidget);
  });
}
