import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';

/// Creates a new saved search. The query field's tag-autocomplete
/// (`BunnyRepository.tagAutocomplete`, M8.1) is debounced and only
/// re-completes the word currently being typed -- e621-style multi-tag
/// queries -- appending the picked tag rather than replacing the whole
/// field. Pops `true` on success so [SearchesScreen] knows to refresh.
class CreateSearchScreen extends StatefulWidget {
  final BunnyRepository repository;

  const CreateSearchScreen({super.key, required this.repository});

  @override
  State<CreateSearchScreen> createState() => _CreateSearchScreenState();
}

class _CreateSearchScreenState extends State<CreateSearchScreen> {
  final _formKey = GlobalKey<FormState>();
  final _labelController = TextEditingController();
  final _queryController = TextEditingController();
  final _intervalController = TextEditingController(text: '24');
  BunnySite _site = BunnySite.e621;
  List<BunnyTagStat> _suggestions = [];
  Timer? _debounce;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _queryController.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.removeListener(_onQueryChanged);
    _labelController.dispose();
    _queryController.dispose();
    _intervalController.dispose();
    super.dispose();
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
