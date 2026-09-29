import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../settings/app_lock_service.dart';

/// Shown at app root whenever [AppLockService.isEnabled] is true, gating
/// [AccountsScreen] behind it. On Android, tries biometric first
/// (`biometricOnly: true` -- the fallback is this app's own PIN/password, not
/// the OS's device credential, per the roadmap's "per-device, client-side
/// setting" design). Any other platform (and Android when biometric
/// fails/isn't available/isn't enrolled) falls back to PIN/password entry.
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

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      _tryBiometric();
    }
  }

  @override
  void dispose() {
    _secretController.dispose();
    super.dispose();
  }

  Future<void> _tryBiometric() async {
    final auth = LocalAuthentication();
    try {
      final canCheck = await auth.canCheckBiometrics && await auth.isDeviceSupported();
      if (!canCheck) {
        return;
      }
      final authenticated = await auth.authenticate(localizedReason: 'Unlock LittleBunny', biometricOnly: true);
      if (authenticated) {
        widget.onUnlocked();
      }
    } on PlatformException {
      // Unavailable/failed/cancelled -- fall back to PIN/password silently.
    }
  }

  Future<void> _submitPin() async {
    setState(() {
      _checking = true;
      _error = null;
    });

    final valid = await widget.lockService.verify(_secretController.text);

    if (!mounted) {
      return;
    }
    if (valid) {
      widget.onUnlocked();
      return;
    }
    setState(() {
      _checking = false;
      _error = 'Incorrect PIN/password';
      _secretController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('LittleBunny is locked'),
              const SizedBox(height: 16),
              TextField(controller: _secretController, enabled: !_checking, obscureText: true, decoration: const InputDecoration(labelText: 'PIN/password'), onSubmitted: (_) => _submitPin()),
              const SizedBox(height: 16),
              if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 16),
              FilledButton(onPressed: _checking ? null : _submitPin, child: const Text('Unlock')),
              if (Platform.isAndroid) TextButton(onPressed: _checking ? null : _tryBiometric, child: const Text('Try fingerprint again')),
            ],
          ),
        ),
      ),
    );
  }
}
