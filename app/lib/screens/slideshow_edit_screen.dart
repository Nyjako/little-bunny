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
import '../widgets/post_grid_tile.dart';
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
    }
  }

  @override
  void dispose() {
    _labelController.dispose();
    _defaultCountController.dispose();
    _maxTotalController.dispose();
    _intervalController.dispose();
    super.dispose();
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
    } else {
      await widget.repository.slideshowUpdate(id, label, defaultPostsPerSearch: defaultCount, maxTotalPosts: maxTotal);
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _addSearches() async {
    final l10n = AppLocalizations.of(context)!;
    final existingIds = _links.map((link) => link.searchId).toSet();
    final candidates = _allSearches.where((search) => !existingIds.contains(search.id)).toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.slideshowEditNoMoreSearchesToAdd)));
      return;
    }
    final selected = <int>{};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(l10n.slideshowEditAddSearchDialogTitle),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: candidates
                  .map(
                    (search) => CheckboxListTile(
                      value: selected.contains(search.id),
                      onChanged: (value) => setDialogState(() {
                        if (value == true) {
                          selected.add(search.id);
                        } else {
                          selected.remove(search.id);
                        }
                      }),
                      title: Text(search.label),
                    ),
                  )
                  .toList(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.commonCancel)),
            TextButton(onPressed: selected.isEmpty ? null : () => Navigator.pop(context, true), child: Text(l10n.slideshowEditAddSearchSubmit)),
          ],
        ),
      ),
    );
    if (confirmed != true) {
      return;
    }
    for (final searchId in selected) {
      await widget.repository.slideshowSearchAdd(_slideshowId!, searchId);
    }
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
  /// Prepare pass); anything that no longer resolves is simply left out of
  /// this viewing rather than failing the whole action.
  Future<void> _watch() async {
    final report = _prepareReport;
    if (report == null || report.readyCount == 0) {
      return;
    }
    final folder = await widget.downloadSettingsStore.loadDestinationFolder();
    if (folder == null || !mounted) {
      return;
    }
    final paths = <int, String>{};
    final playable = <BunnyPost>[];
    for (final post in report.readyPosts) {
      final path = await widget.downloadManager.localFilePathFor(post, folder);
      if (path != null) {
        paths[post.id] = path;
        playable.add(post);
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
            Text(l10n.slideshowEditPrepareSummary(report.readyCount, report.inProgressCount, report.replacedCount, report.unreplaceableCount)),
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
                _prepareSection(l10n),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
