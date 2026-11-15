import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../services/download_manager.dart';
import '../services/download_queue_service.dart';
import '../services/slideshow_prepare_service.dart';
import '../settings/download_settings_store.dart';
import '../util/create_pool_search_dialog.dart';
import '../util/tag_query.dart';
import '../widgets/post_grid_tile.dart';
import 'create_search_screen.dart';
import 'slideshow_screen.dart';

/// Create (when [slideshow] is null) or edit (otherwise) a persisted
/// slideshow (M51 v2): its label/default-count/max-total settings, which
/// searches/pools feed it (each with its own optional override count,
/// reroll, and remove actions, plus a thumbnail preview of what it's
/// currently committed), and a "Prepare" action that resolves/self-heals
/// its committed posts via [SlideshowPrepareService] before "Watch" plays
/// back whatever's ready through [SlideshowScreen].
///
/// In create mode, the searches/prepare sections only appear once the
/// initial Save has actually created the slideshow (a link needs a real
/// `slideshow_id` to attach to) -- there's no "nothing changed" case worth
/// threading a pop result back through, so [SlideshowsScreen] just
/// unconditionally refreshes on return instead.
class SlideshowEditScreen extends StatefulWidget {
  final BunnyRepository repository;
  final DownloadManager downloadManager;
  final DownloadSettingsStore downloadSettingsStore;
  final DownloadQueueService downloadQueueService;
  final BunnySlideshow? slideshow;

  const SlideshowEditScreen({
    super.key,
    required this.repository,
    required this.downloadManager,
    required this.downloadSettingsStore,
    required this.downloadQueueService,
    this.slideshow,
  });

  @override
  State<SlideshowEditScreen> createState() => _SlideshowEditScreenState();
}

class _SlideshowEditScreenState extends State<SlideshowEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _labelController = TextEditingController();
  final _defaultCountController = TextEditingController();
  final _maxTotalController = TextEditingController();
  final _intervalController = TextEditingController(text: '5');

  int? _slideshowId;
  bool _submitting = false;
  bool _loadingLinks = false;
  List<BunnySlideshowSearch> _links = [];
  List<BunnySearch> _allSearches = [];
  Map<int, List<BunnySlideshowPost>> _postsBySearchId = {};

  bool _preparing = false;
  SlideshowPrepareReport? _prepareReport;
  String? _prepareError;

  /// Per-slideshow tag exclusion (additive to the global per-site blacklist,
  /// see [BunnyRepository.getSlideshowBlacklist]'s own doc comment) --
  /// mirrors `SettingsScreen`'s own blacklist editor state, minus the site
  /// selector and e621-sync button (neither applies to a per-slideshow,
  /// site-agnostic list; rules always validate under e621's dialect).
  List<String> _slideshowBlacklistTags = [];
  final _slideshowBlacklistTagController = TextEditingController();
  int? _slideshowBlacklistQueryError;
  Timer? _slideshowBlacklistValidateDebounce;
  List<BunnyTagStat> _slideshowBlacklistSuggestions = [];
  Timer? _slideshowBlacklistAutocompleteDebounce;

  /// Debounces [_onDownloadQueueChanged] below -- the queue service notifies
  /// on every status transition (queued -> downloading -> succeeded/failed),
  /// which for a large slideshow's worth of downloads could otherwise mean
  /// a refresh (a few repository round-trips) firing once per post.
  Timer? _prepareRefreshDebounce;

  @override
  void initState() {
    super.initState();
    final slideshow = widget.slideshow;
    if (slideshow != null) {
      _slideshowId = slideshow.id;
      _labelController.text = slideshow.label;
      _defaultCountController.text = slideshow.defaultPostsPerSearch?.toString() ?? '';
      _maxTotalController.text = slideshow.maxTotalPosts?.toString() ?? '';
      unawaited(_loadLinks());
      unawaited(_loadSlideshowBlacklist());
      // Re-derives readiness on every open, not just after an explicit
      // "Prepare" tap -- without this, a slideshow prepared in an earlier
      // session always came back up with Watch disabled until the user
      // tapped Prepare again, even though everything was already downloaded
      // and sitting on disk the whole time.
      unawaited(_refreshPrepareReportQuietly());
    }
    _slideshowBlacklistTagController.addListener(_onSlideshowBlacklistTagChanged);
    _slideshowBlacklistTagController.addListener(_onSlideshowBlacklistTagChangedAutocomplete);
    // So "ready to watch" ticks up live as downloads actually finish,
    // instead of only ever updating on another explicit "Prepare" tap --
    // watching never waited for every post to be ready (see
    // SlideshowPrepareService's own doc comment), but discovering a post
    // had actually become ready meanwhile did, until now.
    widget.downloadQueueService.addListener(_onDownloadQueueChanged);
  }

  @override
  void dispose() {
    _labelController.dispose();
    _defaultCountController.dispose();
    _maxTotalController.dispose();
    _intervalController.dispose();
    _slideshowBlacklistValidateDebounce?.cancel();
    _slideshowBlacklistAutocompleteDebounce?.cancel();
    _slideshowBlacklistTagController.removeListener(_onSlideshowBlacklistTagChanged);
    _slideshowBlacklistTagController.removeListener(_onSlideshowBlacklistTagChangedAutocomplete);
    _slideshowBlacklistTagController.dispose();
    _prepareRefreshDebounce?.cancel();
    widget.downloadQueueService.removeListener(_onDownloadQueueChanged);
    super.dispose();
  }

  /// Only refreshes once the user has already tapped "Prepare" at least
  /// once this session (`_prepareReport != null`) -- before that, there's
  /// nothing to refresh, and this must never be what first kicks off
  /// downloading a slideshow's posts on its own.
  void _onDownloadQueueChanged() {
    if (_prepareReport == null || _preparing) {
      return;
    }
    _prepareRefreshDebounce?.cancel();
    _prepareRefreshDebounce = Timer(const Duration(seconds: 2), _refreshPrepareReportQuietly);
  }

  /// Same work as [_prepare], minus the `_preparing` flag and minus any
  /// actual downloading -- runs in the background in response to the
  /// download queue's own progress, and once up front from [initState] (so
  /// Watch comes back unlocked on reopen without needing a fresh "Prepare"
  /// tap), not a user tap, so the "Prepare" button shouldn't flicker into
  /// its disabled/spinner state for either. `enqueueMissing: false` (M78) is
  /// what makes this safe to run unprompted: a post that's merely missing
  /// (e.g. its file was deleted out-of-band since the last real Prepare) is
  /// reported as such, never silently re-enqueued just because this screen
  /// happened to reopen.
  Future<void> _refreshPrepareReportQuietly() async {
    final slideshowId = _slideshowId;
    if (slideshowId == null) {
      return;
    }
    final service = SlideshowPrepareService(
      repository: widget.repository,
      downloadQueueService: widget.downloadQueueService,
      downloadManager: widget.downloadManager,
      downloadSettingsStore: widget.downloadSettingsStore,
    );
    try {
      final report = await service.prepare(slideshowId, enqueueMissing: false);
      if (mounted) {
        setState(() => _prepareReport = report);
      }
    } catch (_) {
      // Best-effort background refresh -- a failure here just means the
      // next explicit "Prepare" tap (or the next queue change) tries again,
      // same as any other transient failure already tolerated in this flow.
    }
  }

  void _onSlideshowBlacklistTagChanged() {
    _slideshowBlacklistValidateDebounce?.cancel();
    final text = _slideshowBlacklistTagController.text;
    _slideshowBlacklistValidateDebounce = Timer(const Duration(milliseconds: 300), () async {
      final errorPos = await widget.repository.validateTagQuery(BunnySite.e621, text);
      if (mounted) {
        setState(() => _slideshowBlacklistQueryError = errorPos);
      }
    });
  }

  int get _slideshowBlacklistCursorOffset {
    final selectionOffset = _slideshowBlacklistTagController.selection.baseOffset;
    return selectionOffset >= 0 ? selectionOffset : _slideshowBlacklistTagController.text.length;
  }

  void _onSlideshowBlacklistTagChangedAutocomplete() {
    _slideshowBlacklistAutocompleteDebounce?.cancel();
    final text = _slideshowBlacklistTagController.text;
    final (start, end) = tagTokenRangeAt(text, _slideshowBlacklistCursorOffset);
    final tag = text.substring(start, end);
    if (tag.isEmpty) {
      setState(() => _slideshowBlacklistSuggestions = []);
      return;
    }
    _slideshowBlacklistAutocompleteDebounce = Timer(const Duration(seconds: 3), () async {
      final suggestions = await widget.repository.tagAutocomplete(BunnySite.e621, tag);
      if (mounted) {
        setState(() => _slideshowBlacklistSuggestions = suggestions);
      }
    });
  }

  void _applySlideshowBlacklistSuggestion(String tag) {
    final (newText, newCursor) = applyTagSuggestion(_slideshowBlacklistTagController.text, _slideshowBlacklistCursorOffset, tag);
    _slideshowBlacklistTagController.value = TextEditingValue(text: newText, selection: TextSelection.collapsed(offset: newCursor));
    setState(() => _slideshowBlacklistSuggestions = []);
  }

  Future<void> _loadSlideshowBlacklist() async {
    final id = _slideshowId;
    if (id == null) {
      return;
    }
    final tags = await widget.repository.getSlideshowBlacklist(id);
    if (mounted) {
      setState(() => _slideshowBlacklistTags = tags);
    }
  }

  Future<void> _addSlideshowBlacklistTag() async {
    final tag = _slideshowBlacklistTagController.text.trim();
    if (tag.isEmpty || _slideshowBlacklistQueryError != null) {
      return;
    }
    await widget.repository.addSlideshowBlacklistTag(_slideshowId!, tag);
    _slideshowBlacklistTagController.clear();
    setState(() => _slideshowBlacklistQueryError = null);
    await _loadSlideshowBlacklist();
  }

  Future<void> _removeSlideshowBlacklistTag(String tag) async {
    await widget.repository.removeSlideshowBlacklistTag(_slideshowId!, tag);
    await _loadSlideshowBlacklist();
  }

  bool get _isCreated => _slideshowId != null;

  int? _parseOptionalInt(String text) {
    final trimmed = text.trim();
    return trimmed.isEmpty ? null : int.tryParse(trimmed);
  }

  String? _validateOptionalCount(AppLocalizations l10n, String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return int.tryParse(value.trim()) == null ? l10n.commonMustBeANumber : null;
  }

  String _searchLabel(int searchId) => _allSearches.where((search) => search.id == searchId).firstOrNull?.label ?? 'search #$searchId';

  Future<void> _loadLinks() async {
    final id = _slideshowId;
    if (id == null) {
      return;
    }
    setState(() => _loadingLinks = true);
    final links = await widget.repository.slideshowSearchList(id);
    final allSearches = await widget.repository.listSearches();
    final posts = await widget.repository.slideshowPostsList(id);
    final grouped = <int, List<BunnySlideshowPost>>{};
    for (final entry in posts) {
      grouped.putIfAbsent(entry.searchId, () => []).add(entry);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _links = links;
      _allSearches = allSearches;
      _postsBySearchId = grouped;
      _loadingLinks = false;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final label = _labelController.text.trim();
    final defaultCount = _parseOptionalInt(_defaultCountController.text);
    final maxTotal = _parseOptionalInt(_maxTotalController.text);
    setState(() => _submitting = true);
    final id = _slideshowId;
    if (id == null) {
      final created = await widget.repository.slideshowCreate(label, defaultPostsPerSearch: defaultCount, maxTotalPosts: maxTotal);
      if (!mounted) {
        return;
      }
      setState(() {
        _slideshowId = created;
        _submitting = false;
      });
      await _loadLinks();
      await _loadSlideshowBlacklist();
    } else {
      await widget.repository.slideshowUpdate(id, label, defaultPostsPerSearch: defaultCount, maxTotalPosts: maxTotal);
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _addSearches() async {
    final existingIds = _links.map((link) => link.searchId).toSet();
    await showDialog<void>(context: context, builder: (context) => _AddSearchDialog(repository: widget.repository, slideshowId: _slideshowId!, existingSearchIds: existingIds));
    await _loadLinks();
  }

  Future<void> _editOverrideCount(BunnySlideshowSearch link) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: link.overrideCount?.toString() ?? '');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.slideshowEditOverrideCountDialogTitle(_searchLabel(link.searchId))),
        content: TextField(controller: controller, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: l10n.slideshowEditOverrideCountField), autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.commonCancel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.slideshowEditSaveButton)),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await widget.repository.slideshowSearchAdd(_slideshowId!, link.searchId, overrideCount: _parseOptionalInt(controller.text));
    await _loadLinks();
  }

  Future<void> _rerollSearch(BunnySlideshowSearch link) async {
    await widget.repository.slideshowRerollSearch(_slideshowId!, link.searchId);
    await _loadLinks();
  }

  Future<void> _rerollAll() async {
    await widget.repository.slideshowRerollAll(_slideshowId!);
    await _loadLinks();
  }

  /// Best-effort (same tolerance as every other local-filesystem cleanup in
  /// this app, see `SlideshowsScreen._deleteLocalFiles`) -- a file that
  /// can't be removed (a `content://` SAF uri, or one already gone) is
  /// simply left alone.
  Future<void> _deleteLocalFilesForPosts(List<BunnyPost> posts) async {
    try {
      final folder = await widget.downloadSettingsStore.loadDestinationFolder();
      if (folder == null) {
        return;
      }
      for (final post in posts) {
        final path = await widget.downloadManager.localFilePathFor(post, folder);
        if (path == null || path.startsWith('content://')) {
          continue;
        }
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (_) {
      // Best-effort.
    }
  }

  Future<void> _removeSearch(BunnySlideshowSearch link) async {
    final l10n = AppLocalizations.of(context)!;
    final label = _searchLabel(link.searchId);
    var deleteFiles = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(l10n.slideshowEditRemoveSearchDialogTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.slideshowEditRemoveSearchDialogContent(label)),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: deleteFiles,
                onChanged: (value) => setDialogState(() => deleteFiles = value ?? false),
                title: Text(l10n.slideshowsDeleteAlsoFilesLabel),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.commonCancel)),
            TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.commonRemove)),
          ],
        ),
      ),
    );
    if (confirmed != true) {
      return;
    }
    final committedPosts = (_postsBySearchId[link.searchId] ?? const []).map((entry) => entry.post).toList(growable: false);
    await widget.repository.slideshowSearchRemove(_slideshowId!, link.searchId);
    if (deleteFiles) {
      await _deleteLocalFilesForPosts(committedPosts);
    }
    await _loadLinks();
  }

  Future<void> _prepare() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _preparing = true;
      _prepareError = null;
    });
    final service = SlideshowPrepareService(
      repository: widget.repository,
      downloadQueueService: widget.downloadQueueService,
      downloadManager: widget.downloadManager,
      downloadSettingsStore: widget.downloadSettingsStore,
    );
    try {
      final report = await service.prepare(_slideshowId!);
      if (!mounted) {
        return;
      }
      setState(() {
        _prepareReport = report;
        _preparing = false;
      });
    } on SlideshowPrepareException {
      if (!mounted) {
        return;
      }
      setState(() {
        _preparing = false;
        _prepareError = l10n.slideshowEditNoDestinationFolderMessage;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _preparing = false;
        _prepareError = l10n.slideshowEditPrepareErrorMessage;
      });
    }
  }

  /// Re-resolves each ready post's own local path right before playing --
  /// [_prepareReport] is a snapshot that could technically be a moment
  /// stale (e.g. a file removed from disk out-of-band since the last
  /// Prepare pass). Resolves every post's path in one batched call
  /// ([DownloadManager.batchLocalFilePathFor]) rather than one `await` per
  /// post -- confirmed live as the cause of this action hanging on Android
  /// and taking the better part of a minute even on desktop for a large
  /// slideshow, the exact same per-post-SAF-round-trip problem
  /// [SlideshowPrepareService.prepare] already had to be fixed for.
  ///
  /// Anything that no longer resolves (the file's own post deleted,
  /// corrupted, or moved out-of-band since Prepare ran) is dropped from
  /// this viewing *and* replaced in the slideshow itself via
  /// [BunnyRepository.slideshowReplacePost] -- same self-healing remedy
  /// [SlideshowPrepareService.prepare] already applies to a persistently
  /// failed download, so a subsequent Prepare downloads a fresh
  /// replacement instead of this screen quietly feeding the same dead post
  /// back into every future Watch. Best-effort: a replace failure (e.g. its
  /// search has nothing left to pick) just leaves the dead post out of this
  /// viewing, same as before.
  Future<void> _watch() async {
    final report = _prepareReport;
    final slideshowId = _slideshowId;
    if (report == null || report.readyCount == 0 || slideshowId == null) {
      return;
    }
    final folder = await widget.downloadSettingsStore.loadDestinationFolder();
    if (folder == null || !mounted) {
      return;
    }
    final readyStatuses = report.posts.where((status) => status.readiness == SlideshowPostReadiness.ready).toList(growable: false);
    final paths = await widget.downloadManager.batchLocalFilePathFor(readyStatuses.map((status) => status.post).toList(growable: false), folder);
    final playable = <BunnyPost>[];
    for (final status in readyStatuses) {
      if (paths.containsKey(status.post.id)) {
        playable.add(status.post);
      } else {
        try {
          await widget.repository.slideshowReplacePost(slideshowId, status.searchId, status.post.id);
        } catch (_) {
          // No other post left in that search to replace it with -- leave
          // the dead post committed, same as prepare()'s own unreplaceable
          // case; it's just left out of this particular viewing.
        }
      }
    }
    if (playable.isEmpty || !mounted) {
      return;
    }
    final seconds = int.tryParse(_intervalController.text.trim()) ?? 5;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => SlideshowScreen(posts: playable, localFilePaths: paths, interval: Duration(seconds: seconds), repository: widget.repository)),
    );
  }

  Widget _searchLinkTile(AppLocalizations l10n, BunnySlideshowSearch link) {
    final posts = _postsBySearchId[link.searchId] ?? const [];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_searchLabel(link.searchId)),
            subtitle: Text(link.overrideCount != null ? l10n.slideshowEditOverrideCountSet(link.overrideCount!) : l10n.slideshowEditOverrideUsesDefault),
            onTap: () => _editOverrideCount(link),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: const Icon(Icons.shuffle), tooltip: l10n.slideshowEditRerollSearchTooltip, onPressed: () => _rerollSearch(link)),
                IconButton(icon: const Icon(Icons.delete_outline), tooltip: l10n.slideshowEditRemoveSearchTooltip, onPressed: () => _removeSearch(link)),
              ],
            ),
          ),
          if (posts.isNotEmpty)
            SizedBox(
              height: 90,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: posts.length,
                separatorBuilder: (context, index) => const SizedBox(width: 4),
                itemBuilder: (context, index) {
                  final post = posts[index].post;
                  return SizedBox(width: 90, child: PostGridTile(post: post, imageUrl: post.previewUrl ?? post.fileUrl, onTap: () {}));
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _slideshowBlacklistSection(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.slideshowEditBlacklistHeading, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_slideshowBlacklistTags.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(l10n.slideshowEditBlacklistEmpty))
        else
          Wrap(spacing: 8, runSpacing: 4, children: _slideshowBlacklistTags.map((tag) => Chip(label: Text(tag), onDeleted: () => _removeSlideshowBlacklistTag(tag))).toList()),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const Key('slideshowEditBlacklistAddField'),
                controller: _slideshowBlacklistTagController,
                decoration: InputDecoration(labelText: l10n.slideshowEditBlacklistAddLabel, errorText: _slideshowBlacklistQueryError != null ? l10n.tagQueryInvalidSyntax : null),
                onSubmitted: (_) => _addSlideshowBlacklistTag(),
              ),
            ),
            IconButton(icon: const Icon(Icons.add), onPressed: _slideshowBlacklistQueryError != null ? null : _addSlideshowBlacklistTag),
          ],
        ),
        if (_slideshowBlacklistSuggestions.isNotEmpty)
          Wrap(
            spacing: 8,
            children: _slideshowBlacklistSuggestions.map((stat) => ActionChip(label: Text('${stat.name} (${stat.count})'), onPressed: () => _applySlideshowBlacklistSuggestion(stat.name))).toList(),
          ),
      ],
    );
  }

  Widget _prepareSection(AppLocalizations l10n) {
    final report = _prepareReport;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.slideshowEditPrepareHeading, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton(
                onPressed: _preparing ? null : _prepare,
                child: _preparing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text(l10n.slideshowEditPrepareButton),
              ),
              const SizedBox(width: 12),
              OutlinedButton(onPressed: (report?.readyCount ?? 0) == 0 ? null : _watch, child: Text(l10n.slideshowEditWatchButton)),
            ],
          ),
          if (_prepareError != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_prepareError!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          if (report != null) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: report.posts.isEmpty ? 0 : report.readyCount / report.posts.length),
            const SizedBox(height: 4),
            Text(l10n.slideshowEditPrepareSummary(report.readyCount, report.missingCount, report.inProgressCount, report.replacedCount, report.unreplaceableCount)),
            for (final status in report.posts.where((status) => status.readiness == SlideshowPostReadiness.unreplaceable))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(l10n.slideshowEditUnreplaceableReason(_searchLabel(status.searchId), status.reason ?? ''), style: Theme.of(context).textTheme.bodySmall),
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(_isCreated ? l10n.slideshowEditEditTitle : l10n.slideshowEditCreateTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _labelController,
                enabled: !_submitting,
                decoration: InputDecoration(labelText: l10n.slideshowEditLabelField),
                validator: (value) => (value == null || value.trim().isEmpty) ? l10n.commonRequired : null,
              ),
              TextFormField(
                controller: _defaultCountController,
                enabled: !_submitting,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l10n.slideshowEditDefaultCountField),
                validator: (value) => _validateOptionalCount(l10n, value),
              ),
              TextFormField(
                controller: _maxTotalController,
                enabled: !_submitting,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l10n.slideshowEditMaxTotalField),
                validator: (value) => _validateOptionalCount(l10n, value),
              ),
              TextFormField(
                controller: _intervalController,
                enabled: !_submitting,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l10n.slideshowEditIntervalField),
                validator: (value) => (int.tryParse((value ?? '').trim()) == null) ? l10n.commonMustBeANumber : null,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _submitting ? null : _save,
                child: _submitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text(l10n.slideshowEditSaveButton),
              ),
              if (_isCreated) ...[
                const Divider(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(l10n.slideshowEditSearchesHeading, style: Theme.of(context).textTheme.titleMedium),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(onPressed: _links.isEmpty ? null : _rerollAll, child: Text(l10n.slideshowEditRerollAllButton)),
                        IconButton(icon: const Icon(Icons.add), tooltip: l10n.slideshowEditAddSearchTooltip, onPressed: _addSearches),
                      ],
                    ),
                  ],
                ),
                if (_loadingLinks)
                  const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
                else if (_links.isEmpty)
                  Padding(padding: const EdgeInsets.all(16), child: Text(l10n.slideshowEditSearchesEmptyState))
                else
                  ..._links.map((link) => _searchLinkTile(l10n, link)),
                const Divider(height: 32),
                _slideshowBlacklistSection(l10n),
                const Divider(height: 32),
                _prepareSection(l10n),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The slideshow editor's "add search" picker (M51 v2 follow-up): split into
/// Searches/Pools tabs with pinned items first, same presentation
/// [SearchesScreen] already uses, instead of one flat unsorted list. Each row
/// is tap-to-add-immediately rather than check-several-then-confirm --
/// bulk-adding several at once is now [SearchesScreen]'s own selection
/// mode's job (its "Add to slideshow" bulk action), so this picker only
/// needs to support picking one at a time, as many times in a row as the
/// user likes before dismissing it. A "+ New search"/"+ New pool" entry at
/// the top of each tab pushes/opens this app's existing create flow and,
/// on success, links the newly created search/pool to this slideshow too.
class _AddSearchDialog extends StatefulWidget {
  final BunnyRepository repository;
  final int slideshowId;
  final Set<int> existingSearchIds;

  const _AddSearchDialog({required this.repository, required this.slideshowId, required this.existingSearchIds});

  @override
  State<_AddSearchDialog> createState() => _AddSearchDialogState();
}

class _AddSearchDialogState extends State<_AddSearchDialog> {
  bool _loading = true;
  List<BunnySearch> _allSearches = [];

  /// Added during this dialog's lifetime -- on top of [_AddSearchDialog.existingSearchIds]
  /// (which only reflects links that existed when the dialog opened), so a
  /// row disappears from its tab the moment it's tapped, without having to
  /// reload the parent screen's own links mid-dialog.
  final Set<int> _addedIds = {};

  @override
  void initState() {
    super.initState();
    unawaited(_reloadSearches());
  }

  Future<void> _reloadSearches() async {
    final searches = await widget.repository.listSearches();
    if (!mounted) {
      return;
    }
    setState(() {
      _allSearches = searches;
      _loading = false;
    });
  }

  List<BunnySearch> _candidatesOf(bool isPool) =>
      _allSearches.where((search) => search.isPool == isPool && !widget.existingSearchIds.contains(search.id) && !_addedIds.contains(search.id)).toList()
        ..sort((a, b) {
          if (a.pinned == b.pinned) {
            return 0;
          }
          return a.pinned ? -1 : 1;
        });

  Future<void> _addSearch(BunnySearch search) async {
    await widget.repository.slideshowSearchAdd(widget.slideshowId, search.id);
    if (!mounted) {
      return;
    }
    setState(() => _addedIds.add(search.id));
  }

  /// Pushes [CreateSearchScreen], reloads the candidate list on success, and
  /// immediately links whichever new id just appeared -- there's no
  /// checkbox state to pre-check any more (Part 1), so "created" and "added
  /// to this slideshow" happen together in one step.
  Future<void> _createSearchAndAdd() async {
    final created = await Navigator.push<bool>(context, MaterialPageRoute(builder: (context) => CreateSearchScreen(repository: widget.repository)));
    if (created != true) {
      return;
    }
    await _reloadAndAddNewest();
  }

  Future<void> _createPoolAndAdd() async {
    final created = await showCreatePoolSearchDialog(context, widget.repository);
    if (!created) {
      return;
    }
    await _reloadAndAddNewest();
  }

  Future<void> _reloadAndAddNewest() async {
    final beforeIds = _allSearches.map((search) => search.id).toSet();
    final refreshed = await widget.repository.listSearches();
    if (!mounted) {
      return;
    }
    setState(() => _allSearches = refreshed);
    final newlyCreated = refreshed.where((search) => !beforeIds.contains(search.id));
    if (newlyCreated.isNotEmpty) {
      await _addSearch(newlyCreated.first);
    }
  }

  Widget _candidateTab(AppLocalizations l10n, {required bool isPool, required String createLabel, required VoidCallback onCreate, required String emptyLabel}) {
    final candidates = _candidatesOf(isPool);
    return ListView(
      children: [
        ListTile(leading: const Icon(Icons.add), title: Text(createLabel), onTap: onCreate),
        if (candidates.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text(emptyLabel, style: Theme.of(context).textTheme.bodySmall))
        else
          ...candidates.map((search) => ListTile(title: Text(search.label), onTap: () => _addSearch(search))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.slideshowEditAddSearchDialogTitle),
      content: SizedBox(
        width: double.maxFinite,
        height: 420,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    TabBar(tabs: [Tab(text: l10n.searchesTabSearches), Tab(text: l10n.searchesTabPools)]),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _candidateTab(l10n, isPool: false, createLabel: l10n.slideshowEditNewSearchOption, onCreate: _createSearchAndAdd, emptyLabel: l10n.slideshowEditNoMoreSearchesToAdd),
                          _candidateTab(l10n, isPool: true, createLabel: l10n.slideshowEditNewPoolOption, onCreate: _createPoolAndAdd, emptyLabel: l10n.slideshowEditNoMorePoolsToAdd),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.slideshowEditAddSearchDoneButton))],
    );
  }
}
