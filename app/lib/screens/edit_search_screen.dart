import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../util/tag_query.dart';

/// Edits an existing saved search -- opened via long-press on its
/// [SearchesScreen] row (M9.7.2), replacing the old quick heart-toggle icon.
/// Mirrors [CreateSearchScreen]'s form (label/query/interval/auto-favorite/
/// auto-upvote, with the same tag-autocomplete behavior), plus an
/// Inkbunny-only 1-3 star favorite-level picker. The site itself is not
/// editable -- shown as plain text -- to avoid orphaning already-synced
/// posts tagged to the old site. Pops `true` on success so [SearchesScreen]
/// knows to refresh.
class EditSearchScreen extends StatefulWidget {
  final BunnyRepository repository;
  final BunnySearch search;

  const EditSearchScreen({super.key, required this.repository, required this.search});

  @override
  State<EditSearchScreen> createState() => _EditSearchScreenState();
}

class _EditSearchScreenState extends State<EditSearchScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _labelController = TextEditingController(text: widget.search.label);
  late final _queryController = TextEditingController(text: widget.search.query);
  late final _intervalController = TextEditingController(text: '${widget.search.intervalHours}');
  List<BunnyTagStat> _suggestions = [];
  Timer? _debounce;
  bool _submitting = false;
  late bool _autoFavorite = widget.search.autoFavorite;
  late bool _autoUpvote = widget.search.autoUpvote;
  late int _autoFavoriteStars = widget.search.autoFavoriteStars;

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

  int get _cursorOffset {
    final selectionOffset = _queryController.selection.baseOffset;
    return selectionOffset >= 0 ? selectionOffset : _queryController.text.length;
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    final text = _queryController.text;
    final (start, end) = tagTokenRangeAt(text, _cursorOffset);
    final (_, tag) = splitTagPrefix(text.substring(start, end));
    if (tag.isEmpty || tagHasWildcard(tag)) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final suggestions = await widget.repository.tagAutocomplete(widget.search.site, tag);
      if (mounted) {
        setState(() => _suggestions = suggestions);
      }
    });
  }

  void _applySuggestion(String tag) {
    final (newText, newCursor) = applyTagSuggestion(_queryController.text, _cursorOffset, tag);
    _queryController.value = TextEditingValue(text: newText, selection: TextSelection.collapsed(offset: newCursor));
    setState(() => _suggestions = []);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _submitting = true);

    await widget.repository.updateSearch(
      widget.search.id,
      _labelController.text.trim(),
      _queryController.text.trim(),
      intervalHours: int.parse(_intervalController.text),
      autoFavorite: _autoFavorite,
      autoFavoriteStars: _autoFavoriteStars,
      autoUpvote: widget.search.site == BunnySite.e621 && _autoUpvote,
    );

    if (!mounted) {
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isInkbunny = widget.search.site == BunnySite.inkbunny;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.editSearchScreenTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Text(l10n.editSearchSiteLabel(widget.search.site.toWireString())),
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
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.createSearchAutoFavoriteLabel),
                value: _autoFavorite,
                onChanged: _submitting ? null : (value) => setState(() => _autoFavorite = value),
              ),
              if (isInkbunny) ...[
                const SizedBox(height: 8),
                Text(l10n.editSearchStarsLabel),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  segments: const [ButtonSegment(value: 1, label: Text('1')), ButtonSegment(value: 2, label: Text('2')), ButtonSegment(value: 3, label: Text('3'))],
                  selected: {_autoFavoriteStars},
                  onSelectionChanged: _submitting ? null : (selection) => setState(() => _autoFavoriteStars = selection.first),
                ),
              ],
              if (!isInkbunny)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.createSearchAutoUpvoteLabel),
                  value: _autoUpvote,
                  onChanged: _submitting ? null : (value) => setState(() => _autoUpvote = value),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text(l10n.editSearchSubmit),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
