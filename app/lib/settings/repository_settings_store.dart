import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../repository/bunny_repository_factory.dart';
import 'secret_store.dart';

/// Persists which [BunnyRepositoryConfig] is active across restarts --
/// non-secret bookkeeping (mode, server URL) goes through
/// [SharedPreferences]; the networked mode's bearer token and certificate
/// fingerprint go through [SecretStore] (real backend: OS-native secure
/// storage). Standalone mode's db path is never persisted -- it's
/// recomputed fresh each launch from [getApplicationSupportDirectory], the
/// Dart equivalent of GOBLIN's `appdirs.h` used server-side.
class RepositorySettingsStore {
  static const _keyMode = 'repository_mode';
  static const _keyServerUrl = 'repository_server_url';
  static const _secretKeyBearerToken = 'repository_bearer_token';
  static const _secretKeyCertFingerprint = 'repository_cert_fingerprint';
  static const _standaloneDbFileName = 'bunny.db';
  static const _standaloneUserAgent = 'little_bunny/1.0.0';

  final SecretStore _secrets;

  const RepositorySettingsStore(this._secrets);

  /// Returns `null` if no mode has been configured yet (first launch), or if
  /// a networked config is missing a required secret (cleared/corrupted
  /// storage) -- either way, the caller should fall back to setup.
  Future<BunnyRepositoryConfig?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString(_keyMode);

    if (mode == 'standalone') {
      return StandaloneConfig(dbPath: await _standaloneDbPath(), userAgent: _standaloneUserAgent);
    }

    if (mode == 'networked') {
      final serverUrl = prefs.getString(_keyServerUrl);
      final bearerToken = await _secrets.read(_secretKeyBearerToken);
      final certFingerprint = await _secrets.read(_secretKeyCertFingerprint);
      if (serverUrl == null || bearerToken == null || certFingerprint == null) {
        return null;
      }
      return NetworkedConfig(serverBaseUrl: Uri.parse(serverUrl), bearerToken: bearerToken, certificateSha256Fingerprint: certFingerprint);
    }

    return null;
  }

  Future<void> saveStandalone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMode, 'standalone');
  }

  Future<void> saveNetworked({required Uri serverBaseUrl, required String bearerToken, required String certificateSha256Fingerprint}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMode, 'networked');
    await prefs.setString(_keyServerUrl, serverBaseUrl.toString());
    await _secrets.write(_secretKeyBearerToken, bearerToken);
    await _secrets.write(_secretKeyCertFingerprint, certificateSha256Fingerprint);
  }

  Future<String> _standaloneDbPath() async {
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, _standaloneDbFileName);
  }
}
