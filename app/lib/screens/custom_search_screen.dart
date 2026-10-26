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

  @override
  void initState() {
    super.initState();
    _queryController.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.removeListener(_onQueryChanged);
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
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final suggestions = await widget.repository.tagAutocomplete(_site, tag);
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

  void _search() {
    final query = _queryController.text.trim();
    if (query.isEmpty) {
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
              onSelectionChanged: (selection) => setState(() => _site = selection.first),
            ),
            const SizedBox(height: 16),
            TextField(controller: _queryController, decoration: InputDecoration(labelText: l10n.createSearchQueryField), onSubmitted: (_) => _search()),
            if (_suggestions.isNotEmpty)
              Wrap(spacing: 8, children: _suggestions.map((stat) => ActionChip(label: Text('${stat.name} (${stat.count})'), onPressed: () => _applySuggestion(stat.name))).toList()),
            const SizedBox(height: 16),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _queryController,
              builder: (context, value, child) => FilledButton(onPressed: value.text.trim().isNotEmpty ? _search : null, child: Text(l10n.customSearchSubmit)),
            ),
          ],
        ),
      ),
    );
  }
}
