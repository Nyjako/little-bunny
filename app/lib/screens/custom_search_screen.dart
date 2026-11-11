import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../services/download_queue_service.dart';
import '../settings/display_settings_store.dart';
import '../settings/download_settings_store.dart';
import '../util/tag_query.dart';
import 'tag_browse_screen.dart';

/// A free-text entry point into a live, unsaved [TagBrowseScreen] (M54
/// partial) -- type any space-separated e621/Inkbunny query (tags, with
/// optional `-`/`~` prefixes) and preview it without creating a saved
/// search. Deliberately not a refactor of [CreateSearchScreen] (which this
/// otherwise closely mirrors, down to reusing the exact same
/// `tag_query.dart` autocomplete pattern) -- a small, self-contained screen
/// here avoids any risk to that already-shipped, tested one; this screen
/// has no label/interval/group/auto-favorite fields at all, since it never
/// saves anything.
class CustomSearchScreen extends StatefulWidget {
  final BunnyRepository repository;
  final DisplaySettingsStore displaySettingsStore;
  final DownloadSettingsStore downloadSettingsStore;
  final DownloadQueueService downloadQueueService;

  const CustomSearchScreen({
    super.key,
    required this.repository,
    required this.displaySettingsStore,
    required this.downloadSettingsStore,
    required this.downloadQueueService,
  });

  @override
  State<CustomSearchScreen> createState() => _CustomSearchScreenState();
}

class _CustomSearchScreenState extends State<CustomSearchScreen> {
  final _queryController = TextEditingController();
  BunnySite _site = BunnySite.e621;
  List<BunnyTagStat> _suggestions = [];
  Timer? _debounce;

  /// Byte offset of the first syntax problem in the query field's current
  /// text (M28/M54), or null if it's valid. See CreateSearchScreen's own
  /// doc comment for the full pattern this mirrors.
  int? _queryError;
  Timer? _queryValidateDebounce;

  /// See CreateSearchScreen's own doc comment (M54).
  (String tag, String canonical)? _aliasHint;
  Timer? _aliasCheckDebounce;

  /// See CreateSearchScreen's own doc comment (M54).
  List<String> _implicationChain = const [];
  Timer? _implicationCheckDebounce;

  @override
  void initState() {
    super.initState();
    _queryController.addListener(_onQueryChanged);
    _queryController.addListener(_onQueryChangedValidate);
    _queryController.addListener(_onQueryChangedCheckAlias);
    _queryController.addListener(_onQueryChangedCheckImplication);
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
    _queryController.dispose();
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
      final suggestions = await widget.repository.tagAutocomplete(_site, tag);
      if (mounted) {
        setState(() => _suggestions = suggestions);
      }
    });
  }

  void _onQueryChangedValidate() {
    _queryValidateDebounce?.cancel();
    final text = _queryController.text;
    _queryValidateDebounce = Timer(const Duration(milliseconds: 300), () async {
      final errorPos = await widget.repository.validateTagQuery(_site, text);
      if (mounted) {
        setState(() => _queryError = errorPos);
      }
    });
  }

  void _onQueryChangedCheckAlias() {
    _aliasCheckDebounce?.cancel();
    if (_site != BunnySite.e621) {
      setState(() => _aliasHint = null);
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
    if (_site != BunnySite.e621) {
      setState(() => _implicationChain = const []);
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

  void _search() {
    final query = _queryController.text.trim();
    // An empty query is intentionally allowed -- see bunny_tag_query.h's own
    // doc comment: it's syntactically valid on both sites and just means
    // "everything" (the newest uploads, same as browsing with no filter).
    if (_queryError != null) {
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TagBrowseScreen(
          site: _site,
          query: query,
          repository: widget.repository,
          displaySettingsStore: widget.displaySettingsStore,
          downloadSettingsStore: widget.downloadSettingsStore,
          downloadQueueService: widget.downloadQueueService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.customSearchScreenTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            SegmentedButton<BunnySite>(
              segments: const [ButtonSegment(value: BunnySite.e621, label: Text('e621')), ButtonSegment(value: BunnySite.inkbunny, label: Text('Inkbunny'))],
              selected: {_site},
              onSelectionChanged: (selection) {
                setState(() => _site = selection.first);
                _onQueryChangedValidate();
                _onQueryChangedCheckAlias();
                _onQueryChangedCheckImplication();
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _queryController,
              decoration: InputDecoration(labelText: l10n.createSearchQueryField, errorText: _queryError != null ? l10n.tagQueryInvalidSyntax : null),
              onSubmitted: (_) => _search(),
            ),
            if (_aliasHint != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(l10n.tagAliasHint(_aliasHint!.$1, _aliasHint!.$2), style: Theme.of(context).textTheme.bodySmall)),
            if (_implicationChain.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_implicationChain.join(' → '), style: Theme.of(context).textTheme.bodySmall)),
            if (_suggestions.isNotEmpty)
              Wrap(spacing: 8, children: _suggestions.map((stat) => ActionChip(label: Text('${stat.name} (${stat.count})'), onPressed: () => _applySuggestion(stat.name))).toList()),
            const SizedBox(height: 16),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _queryController,
              builder: (context, value, child) => FilledButton(onPressed: _queryError == null ? _search : null, child: Text(l10n.customSearchSubmit)),
            ),
          ],
        ),
      ),
    );
  }
}
