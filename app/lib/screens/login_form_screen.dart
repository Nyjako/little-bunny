import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';

/// Per-site login form (e621: username + API key; Inkbunny: username +
/// password). Verifies the credentials against the real site (M7.1) before
/// saving them -- pops `true` on success so [AccountsScreen] knows to
/// refresh, `false`/nothing if the user backs out.
class LoginFormScreen extends StatefulWidget {
  final BunnySite site;
  final BunnyRepository repository;

  const LoginFormScreen({super.key, required this.site, required this.repository});

  @override
  State<LoginFormScreen> createState() => _LoginFormScreenState();
}

class _LoginFormScreenState extends State<LoginFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _secretController = TextEditingController();
  bool _submitting = false;
  String? _error;

  bool get _isE621 => widget.site == BunnySite.e621;

  @override
  void dispose() {
    _usernameController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final username = _usernameController.text.trim();
    final secret = _secretController.text;

    try {
      await widget.repository.verifyAccount(widget.site, username, secret);
    } on BunnyRepositoryException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _error = e.message;
      });
      return;
    }

    await widget.repository.setAccount(widget.site, username, secret);

    if (!mounted) {
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.loginScreenTitle(_isE621 ? 'e621' : 'Inkbunny'))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(controller: _usernameController, enabled: !_submitting, decoration: InputDecoration(labelText: l10n.loginUsernameLabel), validator: (value) => (value == null || value.trim().isEmpty) ? l10n.commonRequired : null),
              TextFormField(
                controller: _secretController,
                enabled: !_submitting,
                obscureText: !_isE621,
                decoration: InputDecoration(labelText: _isE621 ? l10n.loginApiKeyLabel : l10n.loginPasswordLabel),
                validator: (value) => (value == null || value.isEmpty) ? l10n.commonRequired : null,
              ),
              const SizedBox(height: 16),
              if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text(l10n.loginSubmit),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
