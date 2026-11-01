import 'package:shared_preferences/shared_preferences.dart';

import 'secret_store.dart';

/// Distinguishes a real digits-only PIN keypad (M60, auto-submits once the
/// configured length is reached) from the original free-text password field
/// (M7.4) -- the user picks one at [AppLockService.enable] time, not a
/// platform- or app-wide default.
enum AppLockMode { pin, password }

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
  static const _keyMode = 'app_lock_mode';
  static const _keyPinLength = 'app_lock_pin_length';

  final SecretStore _secrets;

  const AppLockService(this._secrets);

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyEnabled) ?? false;
  }

  /// `password` if never configured (M60 adds [mode]/[pinLength] on top of
  /// the pre-existing lock; an install that enabled the lock before this
  /// field existed has no stored mode at all).
  Future<AppLockMode> getMode() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_keyMode);
    return stored == null ? AppLockMode.password : AppLockMode.values.byName(stored);
  }

  /// Only meaningful when [getMode] is [AppLockMode.pin]. Defaults to 4.
  Future<int> getPinLength() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyPinLength) ?? 4;
  }

  /// Writes [mode]/[pinLength] *before* flipping the enabled flag, so a
  /// concurrent [isEnabled]/[getMode] read can never observe the lock as on
  /// with a stale/default mode.
  Future<void> enable(String secret, {required AppLockMode mode, int pinLength = 4}) async {
    await _secrets.write(_secretKeySecret, secret);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMode, mode.name);
    await prefs.setInt(_keyPinLength, pinLength);
    await prefs.setBool(_keyEnabled, true);
  }

  /// Disables the lock and forgets the stored secret/mode/PIN length.
  /// Callers should [verify] the current secret first -- this method itself
  /// doesn't ask for one, so a UI can decide how to prompt.
  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, false);
    await prefs.remove(_keyMode);
    await prefs.remove(_keyPinLength);
    await _secrets.delete(_secretKeySecret);
  }

  /// True if [attempt] matches the stored secret. Always false if no secret
  /// is set (lock disabled).
  Future<bool> verify(String attempt) async {
    final secret = await _secrets.read(_secretKeySecret);
    return secret != null && secret == attempt;
  }
}
