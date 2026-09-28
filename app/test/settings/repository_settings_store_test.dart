import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/repository/bunny_repository_factory.dart';
import 'package:little_bunny/settings/repository_settings_store.dart';
import 'package:little_bunny/settings/secret_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSecretStore implements SecretStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

class _FakePathProviderPlatform extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async => '/fake/app/support';
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PathProviderPlatform.instance = _FakePathProviderPlatform();
  });

  test('load returns null when no mode has been configured yet', () async {
    final store = RepositorySettingsStore(_FakeSecretStore());

    expect(await store.load(), isNull);
  });

  test('saveStandalone then load returns a StandaloneConfig using the app support directory', () async {
    final store = RepositorySettingsStore(_FakeSecretStore());
    await store.saveStandalone();

    final config = await store.load();

    expect(config, isA<StandaloneConfig>());
    expect((config as StandaloneConfig).dbPath, '/fake/app/support/bunny.db');
  });

  test('saveNetworked then load returns a matching NetworkedConfig', () async {
    final store = RepositorySettingsStore(_FakeSecretStore());
    await store.saveNetworked(serverBaseUrl: Uri.parse('https://bunny.example:9443'), bearerToken: 'sometoken', certificateSha256Fingerprint: 'abc123');

    final config = await store.load();

    expect(config, isA<NetworkedConfig>());
    final networked = config as NetworkedConfig;
    expect(networked.serverBaseUrl, Uri.parse('https://bunny.example:9443'));
    expect(networked.bearerToken, 'sometoken');
    expect(networked.certificateSha256Fingerprint, 'abc123');
  });

  test('load returns null for networked mode with a missing secret (cleared/corrupted storage)', () async {
    final secrets = _FakeSecretStore();
    final store = RepositorySettingsStore(secrets);
    await store.saveNetworked(serverBaseUrl: Uri.parse('https://bunny.example:9443'), bearerToken: 'sometoken', certificateSha256Fingerprint: 'abc123');
    await secrets.delete('repository_bearer_token');

    expect(await store.load(), isNull);
  });
}
