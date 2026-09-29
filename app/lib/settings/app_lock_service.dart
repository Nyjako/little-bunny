import 'package:shared_preferences/shared_preferences.dart';

import 'secret_store.dart';

/// App-lock (M7.4): a per-device, client-side gate shown at app startup, with
/// no relationship to server-side account credentials (M4.1/M7.1) -- see
/// docs/architecture.md. The PIN/password is stored directly in
/// [SecretStore] (compared by string equality at [verify] time), not a
/// hand-rolled salt+hash: the real backend already encrypts values at rest
/// via the OS-native mechanism, so layering custom hashing on top would just
/// be extra bespoke crypto code for what is a local UI gate, not data-at-rest
/// protection.
class AppLockService {
  static const _keyEnabled = 'app_lock_enabled';
  static const _secretKeySecret = 'app_lock_secret';

  final SecretStore _secrets;

  const AppLockService(this._secrets);

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyEnabled) ?? false;
  }

  Future<void> enable(String secret) async {
    await _secrets.write(_secretKeySecret, secret);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, true);
  }

  /// Disables the lock and forgets the stored secret. Callers should
  /// [verify] the current secret first -- this method itself doesn't ask for
  /// one, so a UI can decide how to prompt.
  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, false);
    await _secrets.delete(_secretKeySecret);
  }

  /// True if [attempt] matches the stored secret. Always false if no secret
  /// is set (lock disabled).
  Future<bool> verify(String attempt) async {
    final secret = await _secrets.read(_secretKeySecret);
    return secret != null && secret == attempt;
  }
}
