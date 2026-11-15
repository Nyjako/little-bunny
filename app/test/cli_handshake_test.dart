import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/cli_handshake.dart';
import 'package:little_bunny/settings/app_lock_service.dart';
import 'package:little_bunny/settings/repository_settings_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_secret_store.dart';

class _FakePathProviderPlatform extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async => '/fake/app/support';
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PathProviderPlatform.instance = _FakePathProviderPlatform();
  });

  test('no repository configured yet reports mode "none"', () async {
    final response = await buildCliHandshakeResponse(
      lockService: AppLockService(FakeSecretStore()),
      settingsStore: RepositorySettingsStore(FakeSecretStore()),
      suppliedSecret: '',
    );

    expect(response, {'ok': true, 'mode': 'none'});
  });

  test('standalone config reports its dbPath/userAgent', () async {
    final settingsStore = RepositorySettingsStore(FakeSecretStore());
    await settingsStore.saveStandalone();

    final response = await buildCliHandshakeResponse(lockService: AppLockService(FakeSecretStore()), settingsStore: settingsStore, suppliedSecret: '');

    expect(response, {'ok': true, 'mode': 'standalone', 'dbPath': '/fake/app/support/bunny.db', 'userAgent': 'LittleBunny/1.0.0'});
  });

  test('networked config reports its serverBaseUrl/bearerToken/certFingerprint', () async {
    final settingsStore = RepositorySettingsStore(FakeSecretStore());
    await settingsStore.saveNetworked(serverBaseUrl: Uri.parse('https://bunny.example:9443'), bearerToken: 'sometoken', certificateSha256Fingerprint: 'abc123');

    final response = await buildCliHandshakeResponse(lockService: AppLockService(FakeSecretStore()), settingsStore: settingsStore, suppliedSecret: '');

    expect(response, {'ok': true, 'mode': 'networked', 'serverBaseUrl': 'https://bunny.example:9443', 'bearerToken': 'sometoken', 'certFingerprint': 'abc123'});
  });

  test('app-lock off never looks at the supplied secret at all', () async {
    final settingsStore = RepositorySettingsStore(FakeSecretStore());
    await settingsStore.saveStandalone();
    // An AppLockService whose isEnabled() is false (default -- no
    // 'app_lock_enabled' key written) must never call verify() with this
    // deliberately-wrong value and still succeed.
    final response = await buildCliHandshakeResponse(lockService: AppLockService(FakeSecretStore()), settingsStore: settingsStore, suppliedSecret: 'definitely-not-the-secret');

    expect(response['ok'], isTrue);
    expect(response['mode'], 'standalone');
  });

  test('app-lock on with the correct secret reports the real config', () async {
    SharedPreferences.setMockInitialValues({'app_lock_enabled': true});
    final settingsStore = RepositorySettingsStore(FakeSecretStore());
    await settingsStore.saveStandalone();
    final lockService = AppLockService(FakeSecretStore({'app_lock_secret': 'my-pin'}));

    final response = await buildCliHandshakeResponse(lockService: lockService, settingsStore: settingsStore, suppliedSecret: 'my-pin');

    expect(response, {'ok': true, 'mode': 'standalone', 'dbPath': '/fake/app/support/bunny.db', 'userAgent': 'LittleBunny/1.0.0'});
  });

  test('app-lock on with the wrong secret reports locked, never the real config', () async {
    SharedPreferences.setMockInitialValues({'app_lock_enabled': true});
    final settingsStore = RepositorySettingsStore(FakeSecretStore());
    await settingsStore.saveStandalone();
    final lockService = AppLockService(FakeSecretStore({'app_lock_secret': 'my-pin'}));

    final response = await buildCliHandshakeResponse(lockService: lockService, settingsStore: settingsStore, suppliedSecret: 'wrong-pin');

    expect(response, {'ok': false, 'error': 'locked'});
  });

  test('app-lock on with an empty supplied secret (bunny_cli given none) reports locked', () async {
    SharedPreferences.setMockInitialValues({'app_lock_enabled': true});
    final settingsStore = RepositorySettingsStore(FakeSecretStore());
    await settingsStore.saveStandalone();
    final lockService = AppLockService(FakeSecretStore({'app_lock_secret': 'my-pin'}));

    final response = await buildCliHandshakeResponse(lockService: lockService, settingsStore: settingsStore, suppliedSecret: '');

    expect(response, {'ok': false, 'error': 'locked'});
  });
}
