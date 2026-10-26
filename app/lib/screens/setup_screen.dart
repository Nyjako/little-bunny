import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../repository/bunny_repository.dart';
import '../repository/bunny_repository_factory.dart';
import '../settings/repository_settings_store.dart';
import '../settings/server_connection_check.dart';
import '../util/connection_qr_payload.dart';
import 'qr_scan_screen.dart';

/// Shown on first launch (no persisted [BunnyRepositoryConfig] yet): lets the
/// user pick standalone (FFI) or networked (HTTP) mode and, once it's
/// confirmed to actually work, persists it via [RepositorySettingsStore] and
/// hands the ready-to-use [BunnyRepository] back to [onConfigured].
class SetupScreen extends StatefulWidget {
  final RepositorySettingsStore settingsStore;
  final ValueChanged<BunnyRepository> onConfigured;

  /// True when reached from Settings (M15) to switch an already-configured
  /// app's connection mode, rather than the first-launch flow. Preselects
  /// the currently active mode, shows a data-isolation warning before
  /// committing, and pops the navigator back to the app's root on success
  /// instead of just calling [onConfigured].
  final bool isReconfigure;

  const SetupScreen({super.key, required this.settingsStore, required this.onConfigured, this.isReconfigure = false});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

enum _Mode { standalone, networked }

class _SetupScreenState extends State<SetupScreen> {
  _Mode _mode = _Mode.standalone;
  final _formKey = GlobalKey<FormState>();
  final _serverUrlController = TextEditingController();
  final _bearerTokenController = TextEditingController();
  final _certFingerprintController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.isReconfigure) {
      _preselectCurrentMode();
    }
  }

  /// Only the server URL is prefilled -- never the bearer token/certificate
  /// fingerprint, matching this app's existing pattern of requiring re-entry
  /// for sensitive changes (e.g. LockSetupScreen requiring the current PIN
  /// to disable app lock).
  Future<void> _preselectCurrentMode() async {
    final config = await widget.settingsStore.load();
    if (!mounted || config == null) {
      return;
    }
    switch (config) {
      case StandaloneConfig():
        setState(() => _mode = _Mode.standalone);
      case NetworkedConfig(:final serverBaseUrl):
        setState(() => _mode = _Mode.networked);
        _serverUrlController.text = serverBaseUrl.toString();
    }
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _bearerTokenController.dispose();
    _certFingerprintController.dispose();
    super.dispose();
  }

  void _applyConnectionQrPayload(ConnectionQrPayload? payload) {
    final l10n = AppLocalizations.of(context)!;
    if (payload == null) {
      setState(() => _error = l10n.setupConnectionQrInvalid);
      return;
    }
    setState(() {
      _serverUrlController.text = payload.serverUrl.toString();
      _bearerTokenController.text = payload.bearerToken;
      _certFingerprintController.text = payload.certSha256;
      _error = null;
    });
  }

  Future<void> _pasteConnectionInfo() async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clipboard?.text;
    if (!mounted) {
      return;
    }
    _applyConnectionQrPayload(text == null ? null : ConnectionQrPayload.tryParse(text));
  }

  Future<void> _scanConnectionQrCode() async {
    final scanned = await Navigator.push<String>(context, MaterialPageRoute(builder: (context) => const QrScanScreen()));
    if (!mounted || scanned == null) {
      return;
    }
    _applyConnectionQrPayload(ConnectionQrPayload.tryParse(scanned));
  }

  Future<bool> _confirmSwitch(AppLocalizations l10n) async {
    if (!widget.isReconfigure) {
      return true;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.setupSwitchWarningTitle),
        content: Text(l10n.setupSwitchWarningMessage),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.commonCancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.setupSwitchConfirm)),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _submitStandalone() async {
    final l10n = AppLocalizations.of(context)!;
    if (!await _confirmSwitch(l10n)) {
      return;
    }
    if (!mounted) {
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    await widget.settingsStore.saveStandalone();
    final config = await widget.settingsStore.load();
    final repository = await createBunnyRepository(config!);

    if (!mounted) {
      return;
    }
    widget.onConfigured(repository);
    _finishReconfigure();
  }

  Future<void> _submitNetworked() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final baseUrl = Uri.parse(_serverUrlController.text.trim());
    final bearerToken = _bearerTokenController.text.trim();
    final certFingerprint = _certFingerprintController.text.trim();

    final connectionError = await checkServerConnection(baseUrl: baseUrl, bearerToken: bearerToken, certificateSha256Fingerprint: certFingerprint);
    if (connectionError != null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _error = connectionError;
      });
      return;
    }

    if (!mounted) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    if (!await _confirmSwitch(l10n)) {
      if (mounted) {
        setState(() => _submitting = false);
      }
      return;
    }
    if (!mounted) {
      return;
    }

    await widget.settingsStore.saveNetworked(serverBaseUrl: baseUrl, bearerToken: bearerToken, certificateSha256Fingerprint: certFingerprint);
    final config = await widget.settingsStore.load();
    final repository = await createBunnyRepository(config!);

    if (!mounted) {
      return;
    }
    widget.onConfigured(repository);
    _finishReconfigure();
  }

  /// Unwinds the navigator back to the app's root after a successful
  /// reconfigure, landing on a fresh SearchesScreen bound to the new
  /// repository rather than leaving stale pushed routes (this screen,
  /// Settings) built against the old one.
  void _finishReconfigure() {
    if (widget.isReconfigure) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(widget.isReconfigure ? l10n.setupReconfigureTitle : l10n.setupScreenTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              SegmentedButton<_Mode>(
                segments: [
                  ButtonSegment(value: _Mode.standalone, label: Text(l10n.setupModeStandalone)),
                  ButtonSegment(value: _Mode.networked, label: Text(l10n.setupModeNetworked)),
                ],
                selected: {_mode},
                onSelectionChanged: _submitting ? null : (selection) => setState(() => _mode = selection.first),
              ),
              const SizedBox(height: 16),
              if (_mode == _Mode.standalone) ...[
                Text(l10n.setupStandaloneDescription),
              ] else ...[
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: _submitting ? null : _pasteConnectionInfo,
                      icon: const Icon(Icons.content_paste),
                      label: Text(l10n.setupPasteConnectionInfo),
                    ),
                    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS)
                      TextButton.icon(
                        onPressed: _submitting ? null : _scanConnectionQrCode,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: Text(l10n.setupScanQrCode),
                      ),
                  ],
                ),
                TextFormField(
                  controller: _serverUrlController,
                  enabled: !_submitting,
                  decoration: InputDecoration(labelText: l10n.setupServerUrlLabel, hintText: l10n.setupServerUrlHint),
                  validator: (value) {
                    final uri = Uri.tryParse(value ?? '');
                    if (uri == null || !uri.isAbsolute) {
                      return l10n.setupServerUrlInvalid;
                    }
                    return null;
                  },
                ),
                TextFormField(controller: _bearerTokenController, enabled: !_submitting, decoration: InputDecoration(labelText: l10n.setupBearerTokenLabel), validator: (value) => (value == null || value.trim().isEmpty) ? l10n.commonRequired : null),
                TextFormField(
                  controller: _certFingerprintController,
                  enabled: !_submitting,
                  decoration: InputDecoration(labelText: l10n.setupCertFingerprintLabel),
                  validator: (value) => (value == null || value.trim().isEmpty) ? l10n.commonRequired : null,
                ),
              ],
              const SizedBox(height: 16),
              if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _submitting
                    ? null
                    : () {
                        if (_mode == _Mode.standalone) {
                          _submitStandalone();
                        } else {
                          _submitNetworked();
                        }
                      },
                child: _submitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text(l10n.commonContinue),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
