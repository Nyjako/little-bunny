import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../repository/bunny_repository.dart';
import '../repository/bunny_repository_factory.dart';
import '../settings/repository_settings_store.dart';
import '../settings/server_connection_check.dart';

/// Shown on first launch (no persisted [BunnyRepositoryConfig] yet): lets the
/// user pick standalone (FFI) or networked (HTTP) mode and, once it's
/// confirmed to actually work, persists it via [RepositorySettingsStore] and
/// hands the ready-to-use [BunnyRepository] back to [onConfigured].
class SetupScreen extends StatefulWidget {
  final RepositorySettingsStore settingsStore;
  final ValueChanged<BunnyRepository> onConfigured;

  const SetupScreen({super.key, required this.settingsStore, required this.onConfigured});

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
  void dispose() {
    _serverUrlController.dispose();
    _bearerTokenController.dispose();
    _certFingerprintController.dispose();
    super.dispose();
  }

  Future<void> _submitStandalone() async {
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

    await widget.settingsStore.saveNetworked(serverBaseUrl: baseUrl, bearerToken: bearerToken, certificateSha256Fingerprint: certFingerprint);
    final config = await widget.settingsStore.load();
    final repository = await createBunnyRepository(config!);

    if (!mounted) {
      return;
    }
    widget.onConfigured(repository);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.setupScreenTitle)),
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
