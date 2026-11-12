import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../util/tag_query.dart';
import '../widgets/e621_metatags_panel.dart';
import '../widgets/inkbunny_advanced_filters_panel.dart';

/// Creates a new saved search. The query field's tag-autocomplete
/// (`BunnyRepository.tagAutocomplete`, M8.1) is debounced and only
/// re-completes the tag token at the current cursor position (M9.6.7's
/// `tag_query.dart` pure functions) -- e621-style multi-tag queries --
/// appending the picked tag rather than replacing the whole field, and
/// stripping/reattaching a leading `-`/`~`/`(` so negated or grouped tags
/// still autocomplete correctly. The label field mirrors the query until the
/// user types into it directly (classic slug-follows-title UX), and the
/// interval field pre-fills from the server-wide default (M20 --
/// `repository.getDefaultSyncIntervalHours`) rather than a hardcoded value;
/// "use default interval" (also M20) keeps it tracking that default live
/// instead of freezing it at creation time. Pops `true` on success so
/// [SearchesScreen] knows to refresh.
class CreateSearchScreen extends StatefulWidget {
  final BunnyRepository repository;

  /// Pre-fills the site/query fields -- used by [TagBrowseScreen]'s "add to
  /// searches" action (M8.5.10). `null` (the default) preserves the blank
  /// form the FAB-driven flow has always shown.
  final BunnySite? initialSite;
  final String? initialQuery;

  /// Pre-fills the label field with a friendlier name than the raw query
  /// (e.g. a pool's own title, M9.6.3) -- when set, this also counts as the
  /// user having "manually" touched the label, so the query-mirroring
  /// behavior below never overwrites it.
  final String? initialLabel;

  /// Pre-fills the Inkbunny advanced-filter panel (M74) -- used the same way
  /// as [initialQuery], when a browse that already had filters applied gets
  /// saved as a real search via [TagBrowseScreen]'s own "add to searches"
  /// action.
  final InkbunnySearchFilters? initialInkbunnyFilters;

  const CreateSearchScreen({super.key, required this.repository, this.initialSite, this.initialQuery, this.initialLabel, this.initialInkbunnyFilters});

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
  Timer? _poolNameDebounce;

  /// Byte offset of the first syntax problem in the query field's current
  /// text (M28/M54), or null if it's valid. Mirrors settings_screen.dart's
  /// blacklist-field validation exactly -- see its own doc comment.
  int? _queryError;
  Timer? _queryValidateDebounce;

  /// Non-null once the tag token under the cursor exactly matches a known,
  /// currently-active e621 tag alias's antecedent (M54) -- e.g. typing
  /// `cat` sets this to `('cat', 'domestic_cat')`, shown as a plain
  /// informational hint below the query field. Deliberately non-blocking:
  /// this never rewrites the field itself, it just tells the user their
  /// tag resolves to a different canonical name server-side, same as
  /// e621's own search UI does. e621-only -- Inkbunny has no alias concept.
  (String tag, String canonical)? _aliasHint;
  Timer? _aliasCheckDebounce;

  /// Non-empty once the tag token under the cursor has at least one active
  /// e621 tag implication (M54) -- e.g. typing `hyper_breasts` sets this to
  /// `[hyper_breasts, huge_breasts, big_breasts, breasts]`, shown joined by
  /// " -> " below the query field. Same non-blocking, e621-only treatment
  /// as [_aliasHint] -- see [resolveTagImplicationChain]'s own doc comment
  /// for how a tag with more than one direct implication is handled.
  List<String> _implicationChain = const [];
  Timer? _implicationCheckDebounce;
  bool _submitting = false;
  bool _labelManuallyEdited = false;
  bool _mirroringLabel = false;
  bool _autoFavorite = false;
  bool _autoUpvote = false;
  bool _usesDefaultInterval = true;
  List<BunnyGroup> _groups = [];
  int _groupId = 0;
  InkbunnySearchFilters _inkbunnyFilters = const InkbunnySearchFilters();

  @override
  void initState() {
    super.initState();
    if (widget.initialSite != null) {
      _site = widget.initialSite!;
    }
    if (widget.initialInkbunnyFilters != null) {
      _inkbunnyFilters = widget.initialInkbunnyFilters!;
    }
    _queryController.addListener(_onQueryChanged);
    _queryController.addListener(_onQueryChangedValidate);
    _queryController.addListener(_onQueryChangedCheckAlias);
    _queryController.addListener(_onQueryChangedCheckImplication);
    _queryController.addListener(_mirrorQueryIntoLabel);
    _labelController.addListener(_onLabelChanged);
    _loadDefaultInterval();
    _loadGroups();
    if (widget.initialQuery != null) {
      _queryController.text = widget.initialQuery!;
    }
    if (widget.initialLabel != null) {
      _labelController.text = widget.initialLabel!;
      _labelManuallyEdited = true;
    }
  }

  Future<void> _loadDefaultInterval() async {
    final hours = await widget.repository.getDefaultSyncIntervalHours();
    if (mounted) {
      _intervalController.text = '$hours';
    }
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
    _poolNameDebounce?.cancel();
    _queryValidateDebounce?.cancel();
    _aliasCheckDebounce?.cancel();
    _implicationCheckDebounce?.cancel();
    _queryController.removeListener(_onQueryChanged);
    _queryController.removeListener(_onQueryChangedValidate);
    _queryController.removeListener(_onQueryChangedCheckAlias);
    _queryController.removeListener(_onQueryChangedCheckImplication);
    _queryController.removeListener(_mirrorQueryIntoLabel);
    _labelController.removeListener(_onLabelChanged);
    _labelController.dispose();
    _queryController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  static final _poolQueryPattern = RegExp(r'^pool:(\d+)$');

  void _mirrorQueryIntoLabel() {
    if (_labelManuallyEdited) {
      return;
    }
    _mirroringLabel = true;
    _labelController.text = _queryController.text;
    _mirroringLabel = false;
    _maybeFetchPoolName();
  }

  /// A raw `pool:<id>` query typed directly (rather than reached via
  /// `TagBrowseScreen`'s "add to searches" action or the Pools tab's "add
  /// pool by ID" dialog, both of which already fetch the pool's own name as
  /// the label) would otherwise mirror the literal `pool:12345` text -- this
  /// upgrades that to the pool's real title once it resolves, same
  /// fetch-then-fallback-to-literal-on-failure shape those other two flows
  /// already established. `widget.initialLabel` already covers that case so
  /// skip the redundant fetch when it's set.
  void _maybeFetchPoolName() {
    _poolNameDebounce?.cancel();
    if (_site != BunnySite.e621 || widget.initialLabel != null) {
      return;
    }
    final query = _queryController.text.trim();
    final match = _poolQueryPattern.firstMatch(query);
    if (match == null) {
      return;
    }
    final poolId = int.parse(match.group(1)!);
    _poolNameDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final pool = await widget.repository.fetchPool(poolId);
        final name = pool.name;
        if (!mounted || _labelManuallyEdited || name == null || name.isEmpty) {
          return;
        }
        _mirroringLabel = true;
        _labelController.text = name;
        _mirroringLabel = false;
      } catch (_) {
        // Leave the literal "pool:<id>" mirror in place.
      }
    });
  }

  void _onLabelChanged() {
    if (_mirroringLabel) {
      return;
    }
    _labelManuallyEdited = true;
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _queryError != null) {
      return;
    }
    setState(() => _submitting = true);

    final id = await widget.repository.createSearch(
      _site,
      _labelController.text.trim(),
      _queryController.text.trim(),
      intervalHours: int.parse(_intervalController.text),
      autoFavorite: _autoFavorite,
      autoUpvote: _site == BunnySite.e621 && _autoUpvote,
      usesDefaultInterval: _usesDefaultInterval,
      inkbunnySearchInMask: _inkbunnyFilters.searchInMask,
      inkbunnyFieldJoinType: _inkbunnyFilters.fieldJoinType,
      inkbunnyStringJoinType: _inkbunnyFilters.stringJoinType,
      inkbunnyUsername: _inkbunnyFilters.username,
      inkbunnySubmissionTypeMask: _inkbunnyFilters.submissionTypeMask,
      inkbunnyDaysLimit: _inkbunnyFilters.daysLimit,
      inkbunnyOrderBy: _inkbunnyFilters.orderBy,
      inkbunnyRandom: _inkbunnyFilters.random,
      inkbunnyScraps: _inkbunnyFilters.scraps,
    );
    if (_groupId != 0) {
      await widget.repository.setSearchGroup(id, _groupId);
    }

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
                onSelectionChanged: _submitting
                    ? null
                    : (selection) {
                        setState(() => _site = selection.first);
                        _onQueryChangedValidate();
                        _onQueryChangedCheckAlias();
                        _onQueryChangedCheckImplication();
                      },
              ),
              const SizedBox(height: 16),
              TextFormField(controller: _labelController, enabled: !_submitting, decoration: InputDecoration(labelText: l10n.createSearchLabelField), validator: (value) => (value == null || value.trim().isEmpty) ? l10n.commonRequired : null),
              // No required-field validator here -- an empty/whitespace query is
              // syntactically valid on both sites and just means "everything"
              // (bunny_tag_query.h's own doc comment), e.g. a plain "newest
              // uploads" saved search with no filtering at all.
              TextFormField(
                controller: _queryController,
                enabled: !_submitting,
                decoration: InputDecoration(labelText: l10n.createSearchQueryField, errorText: _queryError != null ? l10n.tagQueryInvalidSyntax : null),
              ),
              if (_aliasHint != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(l10n.tagAliasHint(_aliasHint!.$1, _aliasHint!.$2), style: Theme.of(context).textTheme.bodySmall)),
              if (_implicationChain.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_implicationChain.join(' → '), style: Theme.of(context).textTheme.bodySmall)),
              if (_suggestions.isNotEmpty)
                Wrap(spacing: 8, children: _suggestions.map((stat) => ActionChip(label: Text('${stat.name} (${stat.count})'), onPressed: () => _applySuggestion(stat.name))).toList()),
              if (_site == BunnySite.e621) E621MetatagsPanel(queryController: _queryController, enabled: !_submitting),
              if (_site == BunnySite.inkbunny) InkbunnyAdvancedFiltersPanel(value: _inkbunnyFilters, enabled: !_submitting, onChanged: (filters) => setState(() => _inkbunnyFilters = filters)),
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
                initialValue: _groupId,
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
              if (_site == BunnySite.e621)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.createSearchAutoUpvoteLabel),
                  value: _autoUpvote,
                  onChanged: _submitting ? null : (value) => setState(() => _autoUpvote = value),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _submitting || _queryError != null ? null : _submit,
                child: _submitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text(l10n.createSearchSubmit),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
