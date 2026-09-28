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
  testWidgets('app boots straight to the placeholder home page when already configured', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'repository_mode': 'networked', 'repository_server_url': 'https://localhost:9443'});
    final settingsStore = RepositorySettingsStore(_FakeSecretStore({'repository_bearer_token': 'test-token', 'repository_cert_fingerprint': '00' * 32}));

    await tester.pumpWidget(LittleBunnyApp(settingsStore: settingsStore));
    await tester.pumpAndSettle();

    expect(find.text('LittleBunny'), findsOneWidget);
    expect(find.text('App shell (M6) -- no screens yet.'), findsOneWidget);
    expect(find.text('Active repository: HttpBunnyRepository'), findsOneWidget);
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
