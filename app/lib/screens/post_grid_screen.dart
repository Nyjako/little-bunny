import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../services/download_manager.dart';
import '../settings/display_settings_store.dart';
import '../settings/download_settings_store.dart';
import '../util/responsive.dart';
import '../widgets/post_grid_tile.dart';
import 'post_detail_screen.dart';
import 'tag_browse_screen.dart';

/// Shows a [BunnySearch]'s cached posts as a thumbnail grid, with an unseen
/// marker overlay and an "unseen only" filter (M8.3). Tapping a post opens
/// [PostDetailScreen] (M8.4), which marks it seen on open; the grid reloads
/// on return so the cleared marker shows up immediately.
class PostGridScreen extends StatefulWidget {
  final BunnySearch search;
  final BunnyRepository repository;
  final DisplaySettingsStore displaySettingsStore;
  final DownloadSettingsStore downloadSettingsStore;

  /// Pure logic, no required construction dependencies -- same reasoning as
  /// [PostDetailScreen.downloadManager] (M9.4): defaults to a real instance,
  /// overridden in widget tests with a fake HTTP client.
  final DownloadManager downloadManager;

  const PostGridScreen({
    super.key,
    required this.search,
    required this.repository,
    required this.displaySettingsStore,
    required this.downloadSettingsStore,
    this.downloadManager = const DownloadManager(),
  });

  @override
  State<PostGridScreen> createState() => _PostGridScreenState();
}

class _PostGridScreenState extends State<PostGridScreen> {
  bool _unseenOnly = false;
  bool _syncing = false;
  Future<List<BunnyPost>>? _postsFuture;
  // Sensible defaults (match DisplaySettingsStore's own) so the first frame
  // doesn't flash a different column count before the real value loads.
  PreviewQuality _previewQuality = PreviewQuality.thumbnail;
  int _gridColumns = 3;

  /// Non-empty means selection mode is active (M9.2) -- there's no separate
  /// boolean flag, since "at least one post selected" and "in selection
  /// mode" are the same condition here (deselecting the last post exits the
  /// mode automatically).
  final Set<int> _selectedPostIds = {};

  bool get _selectionMode => _selectedPostIds.isNotEmpty;

  /// Non-null while a mass download (M9.5) is running -- drives the
  /// contextual app bar's "n/total downloaded" progress title and disables
  /// the other mass-action icons for the duration (deliberately sequential,
  /// no parallel download queue, see the M9 plan's reasoning).
  (int done, int total)? _massDownloadProgress;

  /// Non-null only when this search is itself a pool browse ("pool:`<id>`"),
  /// same convention as [TagBrowseScreen._poolId] -- parsed once up front
  /// rather than re-parsed on every build.
  int? get _poolId {
    if (!widget.search.query.startsWith('pool:')) {
      return null;
    }
    return int.tryParse(widget.search.query.substring(5));
  }

  /// The pool's own metadata (description + cross-referenced pools, M26) --
  /// fetched best-effort alongside the post grid; a failure here just means
  /// the info button's dialog falls back to "no description" (see below).
  BunnyPoolInfo? _poolInfo;

  @override
  void initState() {
    super.initState();
    _postsFuture = _loadPosts();
    _loadDisplaySettings();
    _loadPoolInfo();
  }

  Future<void> _loadPoolInfo() async {
    final poolId = _poolId;
    if (poolId == null) {
      return;
    }
    try {
      final info = await widget.repository.fetchPool(poolId);
      if (mounted) {
        setState(() => _poolInfo = info);
      }
    } catch (_) {
      // Best-effort, see _poolInfo's doc comment.
    }
  }

  void _openRelatedPool(int poolId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TagBrowseScreen(
          site: widget.search.site,
          query: 'pool:$poolId',
          repository: widget.repository,
          displaySettingsStore: widget.displaySettingsStore,
          downloadSettingsStore: widget.downloadSettingsStore,
        ),
      ),
    );
  }

  void _showPoolInfo(AppLocalizations l10n) {
    final info = _poolInfo;
    if (info == null) {
      return;
    }
    final description = info.description;
    final hasDescription = description != null && description.isNotEmpty;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(info.name ?? l10n.postGridPoolInfoTitle),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.postGridPoolInfoPostCount(info.postCount), style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 8),
              Text(hasDescription ? description : l10n.postGridPoolInfoNoDescription),
              if (info.referencedPoolIds.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(l10n.tagBrowseRelatedPoolsLabel, style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  children: info.referencedPoolIds
                      .map(
                        (poolId) => ActionChip(
                          label: Text(l10n.tagBrowseRelatedPoolChip(poolId)),
                          onPressed: () {
                            Navigator.pop(context);
                            _openRelatedPool(poolId);
                          },
                        ),
                      )
                      .toList(),
                ),
              ],
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.postGridPoolInfoCloseButton))],
      ),
    );
  }

  Future<void> _loadDisplaySettings() async {
    final quality = await widget.displaySettingsStore.loadPreviewQuality();
    final columns = await widget.displaySettingsStore.loadGridColumns();
    if (!mounted) {
      return;
    }
    setState(() {
      _previewQuality = quality;
      _gridColumns = columns;
    });
  }

  String? _imageUrlFor(BunnyPost post) {
    if (_previewQuality == PreviewQuality.medium && post.sampleUrl != null) {
      return post.sampleUrl;
    }
    return post.previewUrl;
  }

  /// The repository returns newest-first (by the site's own creation date)
  /// for a normal search's feed. A pool search (isPool) instead comes back
  /// already ordered by e621's own pool order (M26, server-side) -- no
  /// client-side reordering needed here anymore; guessing "reverse upload
  /// order" (M22, this comment's old approach) was wrong whenever a pool's
  /// pages were uploaded out of sequence, a common occurrence for ongoing
  /// comics.
  Future<List<BunnyPost>> _loadPosts() => widget.repository.listSearchPosts(widget.search.id, unseenOnly: _unseenOnly);

  void _toggleUnseenOnly() {
    setState(() {
      _unseenOnly = !_unseenOnly;
      _postsFuture = _loadPosts();
    });
  }

  Future<void> _refresh() async {
    setState(() => _syncing = true);
    await widget.repository.syncDueSearches();
    if (!mounted) {
      return;
    }
    setState(() {
      _syncing = false;
      _postsFuture = _loadPosts();
    });
  }

  Future<void> _markAllSeen() async {
    await widget.repository.markAllSeen(widget.search.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _postsFuture = _loadPosts();
    });
  }

  Future<void> _selectAll() async {
    final posts = await (_postsFuture ?? Future.value(const <BunnyPost>[]));
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedPostIds
        ..clear()
        ..addAll(posts.map((post) => post.id));
    });
  }

  Future<void> _openPost(List<BunnyPost> posts, BunnyPost post) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PostDetailScreen(
          post: post,
          repository: widget.repository,
          displaySettingsStore: widget.displaySettingsStore,
          downloadSettingsStore: widget.downloadSettingsStore,
          siblingPosts: posts,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _postsFuture = _loadPosts();
    });
  }

  void _toggleSelection(int postId) {
    setState(() {
      if (!_selectedPostIds.remove(postId)) {
        _selectedPostIds.add(postId);
      }
    });
  }

  void _onTileTap(List<BunnyPost> posts, BunnyPost post) {
    if (_selectionMode) {
      _toggleSelection(post.id);
    } else {
      _openPost(posts, post);
    }
  }

  void _exitSelectionMode() {
    setState(() => _selectedPostIds.clear());
  }

  Future<void> _massFavorite() async {
    final ids = _selectedPostIds.toList();
    for (final id in ids) {
      await widget.repository.queueFavoriteAdd(id);
    }
    await widget.repository.processQueue();
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedPostIds.clear();
      _postsFuture = _loadPosts();
    });
  }

  Future<void> _massVote(int score) async {
    final ids = _selectedPostIds.toList();
    for (final id in ids) {
      await widget.repository.queueVote(id, score);
    }
    await widget.repository.processQueue();
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedPostIds.clear();
      _postsFuture = _loadPosts();
    });
  }

  Future<void> _massDownload(AppLocalizations l10n) async {
    final allPosts = await (_postsFuture ?? Future.value(const <BunnyPost>[]));
    final selected = allPosts.where((post) => _selectedPostIds.contains(post.id)).toList();
    if (!mounted || selected.isEmpty) {
      return;
    }

    final folder = await widget.downloadSettingsStore.loadDestinationFolder();
    if (!mounted) {
      return;
    }
    if (folder == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.postGridMassDownloadSummary(0, 0, selected.length))));
      return;
    }

    final autoFavorite = await widget.downloadSettingsStore.loadAutoFavoriteOnDownload();
    final autoUpvote = await widget.downloadSettingsStore.loadAutoUpvoteOnDownload();
    if (!mounted) {
      return;
    }

    setState(() => _massDownloadProgress = (0, selected.length));
    var succeeded = 0;
    var mismatched = 0;
    var failed = 0;
    for (final post in selected) {
      final result = await widget.downloadManager.downloadPost(post, widget.repository, folder, autoFavorite: autoFavorite, autoUpvote: autoUpvote);
      switch (result.outcome) {
        case DownloadOutcome.verified:
          succeeded++;
        case DownloadOutcome.checksumMismatch:
          mismatched++;
        case DownloadOutcome.noFileUrl || DownloadOutcome.failed:
          failed++;
      }
      if (!mounted) {
        return;
      }
      setState(() => _massDownloadProgress = (succeeded + mismatched + failed, selected.length));
    }

    if ((autoFavorite || autoUpvote) && succeeded + mismatched > 0) {
      await widget.repository.processQueue();
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _massDownloadProgress = null;
      _selectedPostIds.clear();
      _postsFuture = _loadPosts();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.postGridMassDownloadSummary(succeeded, mismatched, failed))));
  }

  AppBar _buildAppBar(AppLocalizations l10n, BuildContext context) {
    final toolbarHeight = isWideScreen(context) ? compactToolbarHeight : null;
    if (_selectionMode) {
      final votingEnabled = widget.search.site != BunnySite.inkbunny;
      final progress = _massDownloadProgress;
      final busy = progress != null;
      return AppBar(
        toolbarHeight: toolbarHeight,
        leading: IconButton(icon: const Icon(Icons.close), tooltip: l10n.postGridExitSelectionTooltip, onPressed: busy ? null : _exitSelectionMode),
        title: Text(busy ? l10n.postGridMassDownloadProgress(progress.$1, progress.$2) : l10n.postGridSelectionCount(_selectedPostIds.length)),
        actions: [
          IconButton(icon: const Icon(Icons.favorite), tooltip: l10n.postGridMassFavoriteTooltip, onPressed: busy ? null : _massFavorite),
          if (votingEnabled) IconButton(icon: const Icon(Icons.arrow_upward), tooltip: l10n.postGridMassUpvoteTooltip, onPressed: busy ? null : () => _massVote(1)),
          if (votingEnabled) IconButton(icon: const Icon(Icons.arrow_downward), tooltip: l10n.postGridMassDownvoteTooltip, onPressed: busy ? null : () => _massVote(-1)),
          IconButton(
            icon: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download),
            tooltip: l10n.postGridMassDownloadTooltip,
            onPressed: busy ? null : () => _massDownload(l10n),
          ),
        ],
      );
    }
    return AppBar(
      toolbarHeight: toolbarHeight,
      title: Text(widget.search.label),
      actions: [
        if (_poolInfo != null) IconButton(icon: const Icon(Icons.info_outline), tooltip: l10n.postGridPoolInfoTooltip, onPressed: () => _showPoolInfo(l10n)),
        IconButton(icon: Icon(_unseenOnly ? Icons.visibility_off : Icons.visibility), tooltip: l10n.postGridUnseenOnlyTooltip, onPressed: _toggleUnseenOnly),
        IconButton(
          icon: _syncing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh),
          tooltip: l10n.postGridRefreshTooltip,
          onPressed: _syncing ? null : _refresh,
        ),
        PopupMenuButton<void>(
          itemBuilder: (context) => [
            PopupMenuItem(onTap: _markAllSeen, child: Text(l10n.postGridMarkAllSeen)),
            PopupMenuItem(onTap: _selectAll, child: Text(l10n.postGridSelectAll)),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: _buildAppBar(l10n, context),
      body: FutureBuilder<List<BunnyPost>>(
        future: _postsFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final posts = snapshot.data!;
          if (posts.isEmpty) {
            return Center(child: Text(l10n.postGridEmptyState));
          }
          return GridView.builder(
            padding: const EdgeInsets.all(4),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: _gridColumns, crossAxisSpacing: 4, mainAxisSpacing: 4),
            itemCount: posts.length,
            itemBuilder: (context, index) {
              final post = posts[index];
              return PostGridTile(
                key: ValueKey(post.id),
                post: post,
                imageUrl: _imageUrlFor(post),
                selected: _selectedPostIds.contains(post.id),
                onTap: () => _onTileTap(posts, post),
                onLongPress: () => _toggleSelection(post.id),
                selectionMode: _selectionMode,
              );
            },
          );
        },
      ),
    );
  }
}
