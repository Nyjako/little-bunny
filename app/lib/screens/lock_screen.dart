import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../l10n/app_localizations.dart';
import '../settings/app_lock_service.dart';
import '../widgets/pin_entry.dart';

/// Shown at app root whenever [AppLockService.isEnabled] is true, gating
/// [AccountsScreen] behind it. On Android, tries biometric first
/// (`biometricOnly: true` -- the fallback is this app's own PIN/password, not
/// the OS's device credential, per the roadmap's "per-device, client-side
/// setting" design). Any other platform (and Android when biometric
/// fails/isn't available/isn't enrolled) falls back to PIN/password entry --
/// the biometric attempt and its "Try fingerprint again" retry button are
/// unconditional on [Platform.isAndroid], independent of which typed mode
/// (M60) is actually configured.
///
/// Known gap: the Android path can't be build-verified in this dev
/// environment at all (`flutter build apk` already fails at the OpenSSL
/// step, M6.2, deferred to M12) -- see docs/architecture.md.
class LockScreen extends StatefulWidget {
  final AppLockService lockService;
  final VoidCallback onUnlocked;

  const LockScreen({super.key, required this.lockService, required this.onUnlocked});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _secretController = TextEditingController();
  String? _error;
  bool _checking = false;
  bool _biometricAttempted = false;

  /// Null until [_load] resolves -- which typed fallback (PIN keypad vs
  /// password field) to show (M60).
  AppLockMode? _mode;
  int _pinLength = 4;
  String _pin = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final mode = await widget.lockService.getMode();
    final pinLength = await widget.lockService.getPinLength();
    if (!mounted) {
      return;
    }
    setState(() {
      _mode = mode;
      _pinLength = pinLength;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Not initState(): AppLocalizations.of(context) (used inside
    // _tryBiometric) isn't safe to call before dependencies are resolved.
    // _biometricAttempted guards against didChangeDependencies firing more
    // than once. Independent of _mode/_pinLength's own load -- there's no
    // need to wait on those before trying biometric.
    if (!_biometricAttempted && Platform.isAndroid) {
      _biometricAttempted = true;
      _tryBiometric();
    }
  }

  @override
  void dispose() {
    _secretController.dispose();
    super.dispose();
  }

  Future<void> _tryBiometric() async {
    final localizedReason = AppLocalizations.of(context)!.lockScreenBiometricReason;
    final auth = LocalAuthentication();
    try {
      final canCheck = await auth.canCheckBiometrics && await auth.isDeviceSupported();
      if (!canCheck) {
        return;
      }
      final authenticated = await auth.authenticate(localizedReason: localizedReason, biometricOnly: true);
      if (authenticated) {
        widget.onUnlocked();
      }
    } on PlatformException {
      // Unavailable/failed/cancelled -- fall back to PIN/password silently.
    }
  }

  Future<void> _submitSecret(String secret) async {
    setState(() {
      _checking = true;
      _error = null;
    });

    final valid = await widget.lockService.verify(secret);

    if (!mounted) {
      return;
    }
    if (valid) {
      widget.onUnlocked();
      return;
    }
    setState(() {
      _checking = false;
      _error = AppLocalizations.of(context)!.lockScreenIncorrectPin;
      _secretController.clear();
      _pin = '';
    });
  }

  void _onPinChanged(String value) {
    setState(() {
      _pin = value;
      _error = null;
    });
    if (value.length == _pinLength) {
      _submitSecret(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_mode == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.lockScreenMessage),
              const SizedBox(height: 16),
              if (_mode == AppLockMode.pin) _buildPinEntry(l10n) else _buildPasswordEntry(l10n),
              const SizedBox(height: 16),
              if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 16),
              if (Platform.isAndroid) TextButton(onPressed: _checking ? null : _tryBiometric, child: Text(l10n.lockScreenTryFingerprintAgain)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPinEntry(AppLocalizations l10n) {
    return Column(
      children: [
        Text(l10n.lockScreenEnterPinHeading),
        const SizedBox(height: 8),
        PinEntry(length: _pinLength, value: _pin, enabled: !_checking, onChanged: _onPinChanged),
      ],
    );
  }

  Widget _buildPasswordEntry(AppLocalizations l10n) {
    return Column(
      children: [
        TextField(controller: _secretController, enabled: !_checking, obscureText: true, decoration: InputDecoration(labelText: l10n.lockScreenPinLabel), onSubmitted: (_) => _submitSecret(_secretController.text)),
        const SizedBox(height: 16),
        FilledButton(onPressed: _checking ? null : () => _submitSecret(_secretController.text), child: Text(l10n.lockScreenUnlock)),
      ],
    );
  }
}
