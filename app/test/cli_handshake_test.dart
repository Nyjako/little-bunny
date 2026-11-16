import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/cli_handshake.dart';
import 'package:little_bunny/settings/app_lock_service.dart';
import 'package:little_bunny/settings/download_settings_store.dart';
import 'package:little_bunny/settings/repository_settings_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_path_provider.dart';
import 'fakes/fake_secret_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PathProviderPlatform.instance = FakePathProviderPlatform();
  });

  test('no repository configured yet reports mode "none", with no download folder lookup at all', () async {
    final response = await buildCliHandshakeResponse(
      lockService: AppLockService(FakeSecretStore()),
      settingsStore: RepositorySettingsStore(FakeSecretStore()),
      downloadSettingsStore: const DownloadSettingsStore(),
      suppliedSecret: '',
    );

    expect(response, {'ok': true, 'mode': 'none'});
  });

  test('standalone config reports its dbPath/userAgent plus the download destination folder', () async {
    final settingsStore = RepositorySettingsStore(FakeSecretStore());
    await settingsStore.saveStandalone();

    final response = await buildCliHandshakeResponse(
      lockService: AppLockService(FakeSecretStore()),
      settingsStore: settingsStore,
      downloadSettingsStore: const DownloadSettingsStore(),
      suppliedSecret: '',
    );

    expect(response, {'ok': true, 'mode': 'standalone', 'dbPath': '/fake/support/bunny.db', 'userAgent': 'LittleBunny/1.0.0', 'downloadDestinationFolder': '/fake/downloads'});
  });

  test('networked config reports its serverBaseUrl/bearerToken/certFingerprint plus the download destination folder', () async {
    final settingsStore = RepositorySettingsStore(FakeSecretStore());
    await settingsStore.saveNetworked(serverBaseUrl: Uri.parse('https://bunny.example:9443'), bearerToken: 'sometoken', certificateSha256Fingerprint: 'abc123');

    final response = await buildCliHandshakeResponse(
      lockService: AppLockService(FakeSecretStore()),
      settingsStore: settingsStore,
      downloadSettingsStore: const DownloadSettingsStore(),
      suppliedSecret: '',
    );

    expect(response, {
      'ok': true,
      'mode': 'networked',
      'serverBaseUrl': 'https://bunny.example:9443',
      'bearerToken': 'sometoken',
      'certFingerprint': 'abc123',
      'downloadDestinationFolder': '/fake/downloads',
    });
  });

  test('an explicitly saved download folder is reported instead of the OS-Downloads-directory fallback', () async {
    SharedPreferences.setMockInitialValues({'download_destination_folder': '/explicit/folder'});
    final settingsStore = RepositorySettingsStore(FakeSecretStore());
    await settingsStore.saveStandalone();

    final response = await buildCliHandshakeResponse(
      lockService: AppLockService(FakeSecretStore()),
      settingsStore: settingsStore,
      downloadSettingsStore: const DownloadSettingsStore(),
      suppliedSecret: '',
    );

    expect(response['downloadDestinationFolder'], '/explicit/folder');
  });

  test('app-lock off never looks at the supplied secret at all', () async {
    final settingsStore = RepositorySettingsStore(FakeSecretStore());
    await settingsStore.saveStandalone();
    // An AppLockService whose isEnabled() is false (default -- no
    // 'app_lock_enabled' key written) must never call verify() with this
    // deliberately-wrong value and still succeed.
    final response = await buildCliHandshakeResponse(
      lockService: AppLockService(FakeSecretStore()),
      settingsStore: settingsStore,
      downloadSettingsStore: const DownloadSettingsStore(),
      suppliedSecret: 'definitely-not-the-secret',
    );

    expect(response['ok'], isTrue);
    expect(response['mode'], 'standalone');
  });

  test('app-lock on with the correct secret reports the real config', () async {
    SharedPreferences.setMockInitialValues({'app_lock_enabled': true});
    final settingsStore = RepositorySettingsStore(FakeSecretStore());
    await settingsStore.saveStandalone();
    final lockService = AppLockService(FakeSecretStore({'app_lock_secret': 'my-pin'}));

    final response = await buildCliHandshakeResponse(
      lockService: lockService,
      settingsStore: settingsStore,
      downloadSettingsStore: const DownloadSettingsStore(),
      suppliedSecret: 'my-pin',
    );

    expect(response, {'ok': true, 'mode': 'standalone', 'dbPath': '/fake/support/bunny.db', 'userAgent': 'LittleBunny/1.0.0', 'downloadDestinationFolder': '/fake/downloads'});
  });

  test('app-lock on with the wrong secret reports locked, never the real config', () async {
    SharedPreferences.setMockInitialValues({'app_lock_enabled': true});
    final settingsStore = RepositorySettingsStore(FakeSecretStore());
    await settingsStore.saveStandalone();
    final lockService = AppLockService(FakeSecretStore({'app_lock_secret': 'my-pin'}));

    final response = await buildCliHandshakeResponse(
      lockService: lockService,
      settingsStore: settingsStore,
      downloadSettingsStore: const DownloadSettingsStore(),
      suppliedSecret: 'wrong-pin',
    );

    expect(response, {'ok': false, 'error': 'locked'});
  });

  test('app-lock on with an empty supplied secret (bunny_cli given none) reports locked', () async {
    SharedPreferences.setMockInitialValues({'app_lock_enabled': true});
    final settingsStore = RepositorySettingsStore(FakeSecretStore());
    await settingsStore.saveStandalone();
    final lockService = AppLockService(FakeSecretStore({'app_lock_secret': 'my-pin'}));

    final response = await buildCliHandshakeResponse(
      lockService: lockService,
      settingsStore: settingsStore,
      downloadSettingsStore: const DownloadSettingsStore(),
      suppliedSecret: '',
    );

    expect(response, {'ok': false, 'error': 'locked'});
  });
}
