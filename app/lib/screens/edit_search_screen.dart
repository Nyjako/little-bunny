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

  /// Byte offset of the first syntax problem in the query field's current
  /// text (M28/M54), or null if it's valid. See CreateSearchScreen's own
  /// doc comment -- the site here never changes so there's no re-validate-
  /// on-site-switch case to handle.
  int? _queryError;
  Timer? _queryValidateDebounce;

  /// See CreateSearchScreen's own doc comment (M54) -- the site here never
  /// changes so there's no re-check-on-site-switch case to handle.
  (String tag, String canonical)? _aliasHint;
  Timer? _aliasCheckDebounce;

  /// See CreateSearchScreen's own doc comment (M54).
  List<String> _implicationChain = const [];
  Timer? _implicationCheckDebounce;
  bool _submitting = false;
  late bool _autoFavorite = widget.search.autoFavorite;
  late bool _autoUpvote = widget.search.autoUpvote;
  late int _autoFavoriteStars = widget.search.autoFavoriteStars;
  late bool _usesDefaultInterval = widget.search.usesDefaultInterval;
  late int _groupId = widget.search.groupId;
  List<BunnyGroup> _groups = [];

  @override
  void initState() {
    super.initState();
    _queryController.addListener(_onQueryChanged);
    _queryController.addListener(_onQueryChangedValidate);
    _queryController.addListener(_onQueryChangedCheckAlias);
    _queryController.addListener(_onQueryChangedCheckImplication);
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    final groups = await widget.repository.listGroups();
    if (mounted) {
      setState(() => _groups = groups);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryValidateDebounce?.cancel();
    _aliasCheckDebounce?.cancel();
    _implicationCheckDebounce?.cancel();
    _queryController.removeListener(_onQueryChanged);
    _queryController.removeListener(_onQueryChangedValidate);
    _queryController.removeListener(_onQueryChangedCheckAlias);
    _queryController.removeListener(_onQueryChangedCheckImplication);
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
    if (tag.length < tagAutocompleteMinPrefixLength || tagHasWildcard(tag)) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(seconds: 3), () async {
      final suggestions = await widget.repository.tagAutocomplete(widget.search.site, tag);
      if (mounted) {
        setState(() => _suggestions = suggestions);
      }
    });
  }

  void _onQueryChangedValidate() {
    _queryValidateDebounce?.cancel();
    final text = _queryController.text;
    _queryValidateDebounce = Timer(const Duration(milliseconds: 300), () async {
      final errorPos = await widget.repository.validateTagQuery(widget.search.site, text);
      if (mounted) {
        setState(() => _queryError = errorPos);
      }
    });
  }

  void _onQueryChangedCheckAlias() {
    _aliasCheckDebounce?.cancel();
    if (widget.search.site != BunnySite.e621) {
      return;
    }
    final text = _queryController.text;
    final (start, end) = tagTokenRangeAt(text, _cursorOffset);
    final (_, tag) = splitTagPrefix(text.substring(start, end));
    if (tag.length < 2 || tagHasWildcard(tag)) {
      setState(() => _aliasHint = null);
      return;
    }
    _aliasCheckDebounce = Timer(const Duration(seconds: 3), () async {
      final aliases = await widget.repository.searchTagAliases(tag);
      final match = aliases.where((alias) => alias.status == 'active' && alias.antecedentName == tag && alias.consequentName != null).firstOrNull;
      if (mounted) {
        setState(() => _aliasHint = match != null ? (tag, match.consequentName!) : null);
      }
    });
  }

  void _onQueryChangedCheckImplication() {
    _implicationCheckDebounce?.cancel();
    if (widget.search.site != BunnySite.e621) {
      return;
    }
    final text = _queryController.text;
    final (start, end) = tagTokenRangeAt(text, _cursorOffset);
    final (_, tag) = splitTagPrefix(text.substring(start, end));
    if (tag.length < 2 || tagHasWildcard(tag)) {
      setState(() => _implicationChain = const []);
      return;
    }
    _implicationCheckDebounce = Timer(const Duration(seconds: 3), () async {
      final chain = await resolveTagImplicationChain(widget.repository, tag);
      if (mounted) {
        setState(() => _implicationChain = chain);
      }
    });
  }

  void _applySuggestion(String tag) {
    final (newText, newCursor) = applyTagSuggestion(_queryController.text, _cursorOffset, tag);
    _queryController.value = TextEditingValue(text: newText, selection: TextSelection.collapsed(offset: newCursor));
    setState(() => _suggestions = []);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _queryError != null) {
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
      usesDefaultInterval: _usesDefaultInterval,
    );
    if (_groupId != widget.search.groupId) {
      await widget.repository.setSearchGroup(widget.search.id, _groupId);
    }

    if (!mounted) {
      return;
    }
    Navigator.pop(context, true);
  }

  /// Moved here from the searches list row (M14.1), so deleting a search no
  /// longer needs a dedicated row icon -- same confirmation dialog shape
  /// the row used to show, just triggered from this screen's app bar now.
  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.searchesRemoveDialogTitle),
        content: Text(l10n.searchesRemoveDialogContent(widget.search.label)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.commonCancel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.commonRemove)),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await widget.repository.deleteSearch(widget.search.id);
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
      appBar: AppBar(title: Text(l10n.editSearchScreenTitle), actions: [IconButton(icon: const Icon(Icons.delete), tooltip: l10n.editSearchDeleteTooltip, onPressed: _submitting ? null : _delete)]),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Text(l10n.editSearchSiteLabel(widget.search.site.toWireString())),
              const SizedBox(height: 16),
              TextFormField(controller: _labelController, enabled: !_submitting, decoration: InputDecoration(labelText: l10n.createSearchLabelField), validator: (value) => (value == null || value.trim().isEmpty) ? l10n.commonRequired : null),
              // No required-field validator here -- see CreateSearchScreen's
              // own comment on this same field: an empty/whitespace query is
              // intentionally valid and means "everything".
              TextFormField(
                controller: _queryController,
                enabled: !_submitting,
                decoration: InputDecoration(labelText: l10n.createSearchQueryField, errorText: _queryError != null ? l10n.tagQueryInvalidSyntax : null),
              ),
              if (_aliasHint != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(l10n.tagAliasHint(_aliasHint!.$1, _aliasHint!.$2), style: Theme.of(context).textTheme.bodySmall)),
              if (_implicationChain.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_implicationChain.join(' → '), style: Theme.of(context).textTheme.bodySmall)),
              if (_suggestions.isNotEmpty)
                Wrap(spacing: 8, children: _suggestions.map((stat) => ActionChip(label: Text('${stat.name} (${stat.count})'), onPressed: () => _applySuggestion(stat.name))).toList()),
              TextFormField(
                controller: _intervalController,
                enabled: !_submitting && !_usesDefaultInterval,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l10n.createSearchIntervalLabel),
                validator: (value) => _usesDefaultInterval ? null : (int.tryParse(value ?? '') == null) ? l10n.commonRequired : null,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.createSearchUsesDefaultIntervalLabel),
                value: _usesDefaultInterval,
                onChanged: _submitting ? null : (value) => setState(() => _usesDefaultInterval = value),
              ),
              DropdownButtonFormField<int>(
                // DropdownButtonFormField only reads initialValue once, on
                // first build -- the key forces a fresh instance (and so a
                // fresh initialValue read) the moment [_loadGroups] resolves,
                // so a search that's actually in a group doesn't render as
                // "No group" forever just because the list arrived a frame
                // late. [_groupId] itself always holds the real value either
                // way -- this only affects what's shown before any edit.
                key: ValueKey('groupField-${_groups.isNotEmpty}'),
                initialValue: _groups.any((group) => group.id == _groupId) ? _groupId : 0,
                decoration: InputDecoration(labelText: l10n.createSearchGroupLabel),
                items: [
                  DropdownMenuItem(value: 0, child: Text(l10n.createSearchGroupNone)),
                  ..._groups.map((group) => DropdownMenuItem(value: group.id, child: Text(group.name))),
                ],
                onChanged: _submitting ? null : (value) => setState(() => _groupId = value ?? 0),
              ),
              const SizedBox(height: 16),
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
                onPressed: _submitting || _queryError != null ? null : _submit,
                child: _submitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text(l10n.editSearchSubmit),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
