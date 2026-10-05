import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../settings/sync_settings_store.dart';

/// Creates a new saved search. The query field's tag-autocomplete
/// (`BunnyRepository.tagAutocomplete`, M8.1) is debounced and only
/// re-completes the word currently being typed -- e621-style multi-tag
/// queries -- appending the picked tag rather than replacing the whole
/// field. The label field mirrors the query until the user types into it
/// directly (classic slug-follows-title UX), and the interval field
/// pre-fills from [syncSettingsStore]'s stored default rather than a
/// hardcoded value. Pops `true` on success so [SearchesScreen] knows to
/// refresh.
class CreateSearchScreen extends StatefulWidget {
  final BunnyRepository repository;
  final SyncSettingsStore syncSettingsStore;

  /// Pre-fills the site/query fields -- used by [TagBrowseScreen]'s "add to
  /// searches" action (M8.5.10). `null` (the default) preserves the blank
  /// form the FAB-driven flow has always shown.
  final BunnySite? initialSite;
  final String? initialQuery;

  const CreateSearchScreen({super.key, required this.repository, required this.syncSettingsStore, this.initialSite, this.initialQuery});

  @override
  State<CreateSearchScreen> createState() => _CreateSearchScreenState();
}

class _CreateSearchScreenState extends State<CreateSearchScreen> {
  final _formKey = GlobalKey<FormState>();
  final _labelController = TextEditingController();
  final _queryController = TextEditingController();
  final _intervalController = TextEditingController();
  BunnySite _site = BunnySite.e621;
  List<BunnyTagStat> _suggestions = [];
  Timer? _debounce;
  bool _submitting = false;
  bool _labelManuallyEdited = false;
  bool _mirroringLabel = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialSite != null) {
      _site = widget.initialSite!;
    }
    _queryController.addListener(_onQueryChanged);
    _queryController.addListener(_mirrorQueryIntoLabel);
    _labelController.addListener(_onLabelChanged);
    _loadDefaultInterval();
    if (widget.initialQuery != null) {
      _queryController.text = widget.initialQuery!;
    }
  }

  Future<void> _loadDefaultInterval() async {
    final hours = await widget.syncSettingsStore.loadDefaultIntervalHours();
    if (mounted) {
      _intervalController.text = '$hours';
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.removeListener(_onQueryChanged);
    _queryController.removeListener(_mirrorQueryIntoLabel);
    _labelController.removeListener(_onLabelChanged);
    _labelController.dispose();
    _queryController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  void _mirrorQueryIntoLabel() {
    if (_labelManuallyEdited) {
      return;
    }
    _mirroringLabel = true;
    _labelController.text = _queryController.text;
    _mirroringLabel = false;
  }

  void _onLabelChanged() {
    if (_mirroringLabel) {
      return;
    }
    _labelManuallyEdited = true;
  }

  String get _currentWord {
    final text = _queryController.text;
    final lastSpace = text.lastIndexOf(' ');
    return lastSpace == -1 ? text : text.substring(lastSpace + 1);
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    final word = _currentWord;
    if (word.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final suggestions = await widget.repository.tagAutocomplete(_site, word);
      if (mounted) {
        setState(() => _suggestions = suggestions);
      }
    });
  }

  void _applySuggestion(String tag) {
    final text = _queryController.text;
    final lastSpace = text.lastIndexOf(' ');
    final prefix = lastSpace == -1 ? '' : text.substring(0, lastSpace + 1);
    _queryController.value = TextEditingValue(text: '$prefix$tag ', selection: TextSelection.collapsed(offset: prefix.length + tag.length + 1));
    setState(() => _suggestions = []);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _submitting = true);

    await widget.repository.createSearch(_site, _labelController.text.trim(), _queryController.text.trim(), intervalHours: int.parse(_intervalController.text));

    if (!mounted) {
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.createSearchScreenTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              SegmentedButton<BunnySite>(
                segments: const [ButtonSegment(value: BunnySite.e621, label: Text('e621')), ButtonSegment(value: BunnySite.inkbunny, label: Text('Inkbunny'))],
                selected: {_site},
                onSelectionChanged: _submitting ? null : (selection) => setState(() => _site = selection.first),
              ),
              const SizedBox(height: 16),
              TextFormField(controller: _labelController, enabled: !_submitting, decoration: InputDecoration(labelText: l10n.createSearchLabelField), validator: (value) => (value == null || value.trim().isEmpty) ? l10n.commonRequired : null),
              TextFormField(controller: _queryController, enabled: !_submitting, decoration: InputDecoration(labelText: l10n.createSearchQueryField), validator: (value) => (value == null || value.trim().isEmpty) ? l10n.commonRequired : null),
              if (_suggestions.isNotEmpty)
                Wrap(spacing: 8, children: _suggestions.map((stat) => ActionChip(label: Text('${stat.name} (${stat.count})'), onPressed: () => _applySuggestion(stat.name))).toList()),
              TextFormField(
                controller: _intervalController,
                enabled: !_submitting,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l10n.createSearchIntervalLabel),
                validator: (value) => (int.tryParse(value ?? '') == null) ? l10n.commonRequired : null,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text(l10n.createSearchSubmit),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
