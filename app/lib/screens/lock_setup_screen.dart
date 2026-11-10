import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../settings/app_lock_service.dart';
import '../widgets/pin_entry.dart';

/// Lets the user enable/disable the app-lock PIN/password (M7.4/M60),
/// reachable from [AccountsScreen]'s app bar. Disabling requires re-entering
/// the current PIN/password first, matching common app-lock UX elsewhere.
/// PIN mode (M60) auto-submits as soon as both the new and confirm entries
/// reach the chosen length -- no button, unlike password mode which still
/// needs an explicit submit since free text has no inherent "done" signal.
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

  /// Enable flow: the picker's current selection (password by default, so an
  /// existing password-mode user sees the exact same zero-extra-interaction
  /// flow as before M60). Disable flow: loaded from the service once
  /// [_enabled] is true, so the right UI (keypad vs text field) shows for
  /// whatever's actually configured.
  AppLockMode _mode = AppLockMode.password;
  int _pinLength = 4;
  String _newPin = '';
  String _confirmPin = '';
  String _currentPin = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await widget.lockService.isEnabled();
    final mode = enabled ? await widget.lockService.getMode() : AppLockMode.password;
    final pinLength = enabled ? await widget.lockService.getPinLength() : 4;
    if (!mounted) {
      return;
    }
    setState(() {
      _enabled = enabled;
      _mode = mode;
      _pinLength = pinLength;
    });
  }

  @override
  void dispose() {
    _newSecretController.dispose();
    _confirmSecretController.dispose();
    _currentSecretController.dispose();
    super.dispose();
  }

  void _changeMode(AppLockMode mode) {
    setState(() {
      _mode = mode;
      _newPin = '';
      _confirmPin = '';
      _error = null;
    });
    _newSecretController.clear();
    _confirmSecretController.clear();
  }

  void _changePinLength(int length) {
    // A half-entered PIN at the old length can't be meaningfully reinterpreted
    // at a new one -- drop it rather than silently truncating/misreading it.
    setState(() {
      _pinLength = length;
      _newPin = '';
      _confirmPin = '';
      _error = null;
    });
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

    await widget.lockService.enable(_newSecretController.text, mode: AppLockMode.password);

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

  void _onNewPinChanged(String value) {
    setState(() {
      _newPin = value;
      _error = null;
    });
    _maybeSubmitPin();
  }

  void _onConfirmPinChanged(String value) {
    setState(() {
      _confirmPin = value;
      _error = null;
    });
    _maybeSubmitPin();
  }

  void _maybeSubmitPin() {
    if (_newPin.length != _pinLength || _confirmPin.length != _pinLength) {
      return;
    }
    if (_newPin != _confirmPin) {
      // Only the confirm entry is cleared -- the new-PIN value and the error
      // both stay visible, same "show the error, let the user retry" shape
      // the password flow already has, rather than silently vanishing both.
      setState(() {
        _error = AppLocalizations.of(context)!.lockSetupEntriesDoNotMatch;
        _confirmPin = '';
      });
      return;
    }
    _enablePinLock();
  }

  Future<void> _enablePinLock() async {
    setState(() => _submitting = true);

    await widget.lockService.enable(_newPin, mode: AppLockMode.pin, pinLength: _pinLength);

    if (!mounted) {
      return;
    }
    setState(() {
      _enabled = true;
      _submitting = false;
      _newPin = '';
      _confirmPin = '';
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

  void _onCurrentPinChanged(String value) {
    setState(() {
      _currentPin = value;
      _error = null;
    });
    if (value.length == _pinLength) {
      _disablePinLock(value);
    }
  }

  Future<void> _disablePinLock(String pin) async {
    final valid = await widget.lockService.verify(pin);
    if (!valid) {
      setState(() {
        _error = AppLocalizations.of(context)!.lockScreenIncorrectPin;
        _currentPin = '';
      });
      return;
    }

    setState(() => _submitting = true);

    await widget.lockService.disable();

    if (!mounted) {
      return;
    }
    setState(() {
      _enabled = false;
      _submitting = false;
      _currentPin = '';
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
    return ListView(
      children: [
        Text(l10n.lockSetupDescription),
        const SizedBox(height: 16),
        SegmentedButton<AppLockMode>(
          segments: [
            ButtonSegment(value: AppLockMode.pin, label: Text(l10n.lockSetupModePin)),
            ButtonSegment(value: AppLockMode.password, label: Text(l10n.lockSetupModePassword)),
          ],
          selected: {_mode},
          onSelectionChanged: _submitting ? null : (selection) => _changeMode(selection.first),
        ),
        const SizedBox(height: 16),
        if (_mode == AppLockMode.password) _buildPasswordEnableFields(context, l10n) else _buildPinEnableFields(context, l10n),
        const SizedBox(height: 16),
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ],
    );
  }

  Widget _buildPasswordEnableFields(BuildContext context, AppLocalizations l10n) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          TextFormField(controller: _newSecretController, enabled: !_submitting, obscureText: true, decoration: InputDecoration(labelText: l10n.lockSetupNewPinLabel), validator: (value) => (value == null || value.isEmpty) ? l10n.commonRequired : null),
          TextFormField(controller: _confirmSecretController, enabled: !_submitting, obscureText: true, decoration: InputDecoration(labelText: l10n.lockSetupConfirmLabel), validator: (value) => (value == null || value.isEmpty) ? l10n.commonRequired : null),
          const SizedBox(height: 16),
          FilledButton(onPressed: _submitting ? null : _enableLock, child: Text(l10n.lockSetupEnableButton)),
        ],
      ),
    );
  }

  void _backToNewPin() {
    setState(() {
      _newPin = '';
      _confirmPin = '';
      _error = null;
    });
  }

  Widget _buildPinEnableFields(BuildContext context, AppLocalizations l10n) {
    final onNewPinStep = _newPin.length < _pinLength;
    return Column(
      children: [
        Text(l10n.lockSetupPinLengthLabel),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: const [ButtonSegment(value: 4, label: Text('4')), ButtonSegment(value: 5, label: Text('5')), ButtonSegment(value: 6, label: Text('6'))],
          selected: {_pinLength},
          onSelectionChanged: _submitting ? null : (selection) => _changePinLength(selection.first),
        ),
        const SizedBox(height: 24),
        if (onNewPinStep) ...[
          Text(l10n.lockSetupNewPinHeading),
          PinEntry(length: _pinLength, value: _newPin, enabled: !_submitting, onChanged: _onNewPinChanged),
        ] else ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(onPressed: _submitting ? null : _backToNewPin, icon: const Icon(Icons.arrow_back), tooltip: l10n.lockSetupBackToNewPin),
              Text(l10n.lockSetupConfirmPinHeading),
            ],
          ),
          PinEntry(length: _pinLength, value: _confirmPin, enabled: !_submitting, onChanged: _onConfirmPinChanged),
        ],
      ],
    );
  }

  Widget _buildDisableForm(BuildContext context, AppLocalizations l10n) {
    return ListView(
      children: [
        Text(l10n.lockSetupCurrentlyOn),
        const SizedBox(height: 16),
        if (_mode == AppLockMode.password) _buildPasswordDisableFields(l10n) else _buildPinDisableFields(l10n),
        const SizedBox(height: 16),
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ],
    );
  }

  Widget _buildPasswordDisableFields(AppLocalizations l10n) {
    return Column(
      children: [
        TextField(controller: _currentSecretController, enabled: !_submitting, obscureText: true, decoration: InputDecoration(labelText: l10n.lockSetupCurrentPinLabel)),
        const SizedBox(height: 16),
        FilledButton(onPressed: _submitting ? null : _disableLock, child: Text(l10n.lockSetupDisableButton)),
      ],
    );
  }

  Widget _buildPinDisableFields(AppLocalizations l10n) {
    return Column(
      children: [
        Text(l10n.lockSetupCurrentPinHeading),
        PinEntry(length: _pinLength, value: _currentPin, enabled: !_submitting, onChanged: _onCurrentPinChanged),
      ],
    );
  }
}
