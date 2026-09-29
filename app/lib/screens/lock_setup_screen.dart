import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../settings/app_lock_service.dart';

/// Lets the user enable/disable the app-lock PIN/password (M7.4), reachable
/// from [AccountsScreen]'s app bar. Disabling requires re-entering the
/// current PIN/password first, matching common app-lock UX elsewhere.
class LockSetupScreen extends StatefulWidget {
  final AppLockService lockService;

  const LockSetupScreen({super.key, required this.lockService});

  @override
  State<LockSetupScreen> createState() => _LockSetupScreenState();
}

class _LockSetupScreenState extends State<LockSetupScreen> {
  bool? _enabled;
  final _formKey = GlobalKey<FormState>();
  final _newSecretController = TextEditingController();
  final _confirmSecretController = TextEditingController();
  final _currentSecretController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await widget.lockService.isEnabled();
    if (!mounted) {
      return;
    }
    setState(() => _enabled = enabled);
  }

  @override
  void dispose() {
    _newSecretController.dispose();
    _confirmSecretController.dispose();
    _currentSecretController.dispose();
    super.dispose();
  }

  Future<void> _enableLock() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_newSecretController.text != _confirmSecretController.text) {
      setState(() => _error = AppLocalizations.of(context)!.lockSetupEntriesDoNotMatch);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    await widget.lockService.enable(_newSecretController.text);

    if (!mounted) {
      return;
    }
    setState(() {
      _enabled = true;
      _submitting = false;
      _newSecretController.clear();
      _confirmSecretController.clear();
    });
  }

  Future<void> _disableLock() async {
    final valid = await widget.lockService.verify(_currentSecretController.text);
    if (!valid) {
      setState(() => _error = AppLocalizations.of(context)!.lockScreenIncorrectPin);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    await widget.lockService.disable();

    if (!mounted) {
      return;
    }
    setState(() {
      _enabled = false;
      _submitting = false;
      _currentSecretController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_enabled == null) {
      return Scaffold(appBar: AppBar(title: Text(l10n.lockSetupScreenTitle)), body: const Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.lockSetupScreenTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _enabled! ? _buildDisableForm(context, l10n) : _buildEnableForm(context, l10n),
      ),
    );
  }

  Widget _buildEnableForm(BuildContext context, AppLocalizations l10n) {
    return Form(
      key: _formKey,
      child: ListView(
        children: [
          Text(l10n.lockSetupDescription),
          TextFormField(controller: _newSecretController, enabled: !_submitting, obscureText: true, decoration: InputDecoration(labelText: l10n.lockSetupNewPinLabel), validator: (value) => (value == null || value.isEmpty) ? l10n.commonRequired : null),
          TextFormField(controller: _confirmSecretController, enabled: !_submitting, obscureText: true, decoration: InputDecoration(labelText: l10n.lockSetupConfirmLabel), validator: (value) => (value == null || value.isEmpty) ? l10n.commonRequired : null),
          const SizedBox(height: 16),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 16),
          FilledButton(onPressed: _submitting ? null : _enableLock, child: Text(l10n.lockSetupEnableButton)),
        ],
      ),
    );
  }

  Widget _buildDisableForm(BuildContext context, AppLocalizations l10n) {
    return ListView(
      children: [
        Text(l10n.lockSetupCurrentlyOn),
        TextField(controller: _currentSecretController, enabled: !_submitting, obscureText: true, decoration: InputDecoration(labelText: l10n.lockSetupCurrentPinLabel)),
        const SizedBox(height: 16),
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 16),
        FilledButton(onPressed: _submitting ? null : _disableLock, child: Text(l10n.lockSetupDisableButton)),
      ],
    );
  }
}
