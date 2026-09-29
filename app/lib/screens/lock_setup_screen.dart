import 'package:flutter/material.dart';

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
      setState(() => _error = 'Entries do not match');
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
      setState(() => _error = 'Incorrect PIN/password');
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
    if (_enabled == null) {
      return Scaffold(appBar: AppBar(title: const Text('App lock')), body: const Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('App lock')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _enabled! ? _buildDisableForm(context) : _buildEnableForm(context),
      ),
    );
  }

  Widget _buildEnableForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        children: [
          const Text('Set a PIN or password to lock this app on startup.'),
          TextFormField(controller: _newSecretController, enabled: !_submitting, obscureText: true, decoration: const InputDecoration(labelText: 'New PIN/password'), validator: (value) => (value == null || value.isEmpty) ? 'Required' : null),
          TextFormField(controller: _confirmSecretController, enabled: !_submitting, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm'), validator: (value) => (value == null || value.isEmpty) ? 'Required' : null),
          const SizedBox(height: 16),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 16),
          FilledButton(onPressed: _submitting ? null : _enableLock, child: const Text('Enable app lock')),
        ],
      ),
    );
  }

  Widget _buildDisableForm(BuildContext context) {
    return ListView(
      children: [
        const Text('App lock is currently on.'),
        TextField(controller: _currentSecretController, enabled: !_submitting, obscureText: true, decoration: const InputDecoration(labelText: 'Enter current PIN/password to disable')),
        const SizedBox(height: 16),
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 16),
        FilledButton(onPressed: _submitting ? null : _disableLock, child: const Text('Disable app lock')),
      ],
    );
  }
}
