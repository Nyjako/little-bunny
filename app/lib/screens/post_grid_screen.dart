import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../services/download_queue_service.dart';
import '../settings/display_settings_store.dart';
import '../settings/download_settings_store.dart';
import '../util/responsive.dart';
import '../widgets/pool_description_text.dart';
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
  final DownloadQueueService downloadQueueService;

  const PostGridScreen({
    super.key,
    required this.search,
    required this.repository,
    required this.displaySettingsStore,
    required this.downloadSettingsStore,
    required this.downloadQueueService,
  });

  @override
  State<PostGridScreen> createState() => _PostGridScreenState();
}

class _PostGridScreenState extends State<PostGridScreen> {
  bool _unseenOnly = false;
  bool _syncing = false;
  // Sensible defaults (match DisplaySettingsStore's own) so the first frame
  // doesn't flash a different column count before the real value loads.
  PreviewQuality _previewQuality = PreviewQuality.thumbnail;
  int _gridColumns = 3;

  /// Infinite scroll (M34) -- a search can accumulate thousands of cached
  /// posts (e.g. a long-running favorites search), and `listSearchPosts`
  /// returning them all in one unbounded response routinely took minutes
  /// and timed out client-side. Same shape as `TagBrowseScreen`'s own
  /// infinite scroll (`_loadInitial`/`_loadMore`/`_maybeLoadMore`), just
  /// paging through the local cache instead of a live site search.
  final List<BunnyPost> _posts = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _nextPage = 1;
  final _scrollController = ScrollController();

  /// Non-empty means selection mode is active (M9.2) -- there's no separate
  /// boolean flag, since "at least one post selected" and "in selection
  /// mode" are the same condition here (deselecting the last post exits the
  /// mode automatically).
  final Set<int> _selectedPostIds = {};

  bool get _selectionMode => _selectedPostIds.isNotEmpty;

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
    _loadInitial();
    _loadDisplaySettings();
    _loadPoolInfo();
    _scrollController.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_maybeLoadMore)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadPoolInfo() async {
    final poolId = _poolId;
    // fetchPool always hits e621's GET /pools/{id} -- Inkbunny has no
    // equivalent pool-metadata endpoint at all (M28), and pool ids aren't
    // shared/comparable across sites, so calling it for an Inkbunny pool
    // search would risk silently showing an unrelated e621 pool's
    // description if the numeric id happens to collide.
    if (poolId == null || widget.search.site != BunnySite.e621) {
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
          downloadQueueService: widget.downloadQueueService,
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
              hasDescription
                  ? PoolDescriptionText(
                      description: description,
                      onOpenPool: (poolId) {
                        Navigator.pop(context);
                        _openRelatedPool(poolId);
                      },
                    )
                  : Text(l10n.postGridPoolInfoNoDescription),
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
  Future<List<BunnyPost>> _fetchPage(int page) => widget.repository.listSearchPosts(widget.search.id, unseenOnly: _unseenOnly, page: page);

  Future<void> _loadInitial() async {
    final page = await _fetchPage(1);
    if (!mounted) {
      return;
    }
    setState(() {
      _posts.addAll(page);
      _loading = false;
      _hasMore = page.isNotEmpty;
      _nextPage = 2;
    });
  }

  // Same "any non-empty page might have more" convention as TagBrowseScreen.
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) {
      return;
    }
    setState(() => _loadingMore = true);
    final page = await _fetchPage(_nextPage);
    if (!mounted) {
      return;
    }
    setState(() {
      _posts.addAll(page);
      _loadingMore = false;
      _hasMore = page.isNotEmpty;
      _nextPage++;
    });
  }

  void _maybeLoadMore() {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  /// Full reset back to page 1 -- for when the matching post *set* itself
  /// changes (the unseen filter, or a sync that may have added new posts),
  /// as opposed to [_refreshLoadedPages] below.
  Future<void> _resetAndReload() async {
    setState(() {
      _posts.clear();
      _loading = true;
      _hasMore = true;
      _nextPage = 1;
    });
    await _loadInitial();
  }

  /// Re-fetches exactly the pages already loaded and replaces [_posts] with
  /// the result, rather than resetting to page 1 -- for actions that only
  /// change already-loaded posts' own fields (seen state, a vote/favorite)
  /// without changing which posts match this search, so scroll position and
  /// how far the user has already scrolled stay put.
  Future<void> _refreshLoadedPages() async {
    final loadedPageCount = _nextPage - 1;
    final pages = await Future.wait(List.generate(loadedPageCount, (i) => _fetchPage(i + 1)));
    if (!mounted) {
      return;
    }
    setState(() {
      _posts
        ..clear()
        ..addAll(pages.expand((page) => page));
    });
  }

  void _toggleUnseenOnly() {
    setState(() => _unseenOnly = !_unseenOnly);
    _resetAndReload();
  }

  Future<void> _refresh() async {
    setState(() => _syncing = true);
    await widget.repository.syncDueSearches();
    if (!mounted) {
      return;
    }
    setState(() => _syncing = false);
    await _resetAndReload();
  }

  Future<void> _markAllSeen() async {
    await widget.repository.markAllSeen(widget.search.id);
    await _refreshLoadedPages();
  }

  /// Scoped to posts already loaded via infinite scroll, not every post
  /// matching this search -- fetching every remaining page first would
  /// reintroduce the same unbounded-load problem this screen's pagination
  /// (M34) exists to avoid.
  void _selectAll() {
    setState(() {
      _selectedPostIds
        ..clear()
        ..addAll(_posts.map((post) => post.id));
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
          downloadQueueService: widget.downloadQueueService,
          siblingPosts: posts,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    await _refreshLoadedPages();
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
    setState(() => _selectedPostIds.clear());
    await _refreshLoadedPages();
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
    setState(() => _selectedPostIds.clear());
    await _refreshLoadedPages();
  }

  /// Enqueues the whole selection and returns immediately (M43) -- the
  /// actual fetch/write/checksum work, folder/auto-favorite/auto-upvote
  /// resolution, and action-queue draining all now live inside
  /// [DownloadQueueService] itself, reported through its notifier rather
  /// than this screen's own state. No `_refreshLoadedPages()` afterward:
  /// downloading never mutates any post field this grid displays (unlike
  /// [_massFavorite]/[_massVote], which call it themselves after their own
  /// direct, still-synchronous actions).
  void _massDownload(AppLocalizations l10n) {
    final selected = _posts.where((post) => _selectedPostIds.contains(post.id)).toList();
    if (selected.isEmpty) {
      return;
    }
    widget.downloadQueueService.enqueueAll(selected, widget.repository);
    setState(() => _selectedPostIds.clear());
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.postGridMassDownloadQueued(selected.length))));
  }

  AppBar _buildAppBar(AppLocalizations l10n, BuildContext context) {
    final toolbarHeight = isWideScreen(context) ? compactToolbarHeight : null;
    if (_selectionMode) {
      final votingEnabled = widget.search.site != BunnySite.inkbunny;
      return AppBar(
        toolbarHeight: toolbarHeight,
        leading: IconButton(icon: const Icon(Icons.close), tooltip: l10n.postGridExitSelectionTooltip, onPressed: _exitSelectionMode),
        title: Text(l10n.postGridSelectionCount(_selectedPostIds.length)),
        actions: [
          IconButton(icon: const Icon(Icons.favorite), tooltip: l10n.postGridMassFavoriteTooltip, onPressed: _massFavorite),
          if (votingEnabled) IconButton(icon: const Icon(Icons.arrow_upward), tooltip: l10n.postGridMassUpvoteTooltip, onPressed: () => _massVote(1)),
          if (votingEnabled) IconButton(icon: const Icon(Icons.arrow_downward), tooltip: l10n.postGridMassDownvoteTooltip, onPressed: () => _massVote(-1)),
          IconButton(icon: const Icon(Icons.download), tooltip: l10n.postGridMassDownloadTooltip, onPressed: () => _massDownload(l10n)),
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _posts.isEmpty
          ? Center(child: Text(l10n.postGridEmptyState))
          : GridView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(4),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: _gridColumns, crossAxisSpacing: 4, mainAxisSpacing: 4),
              itemCount: _posts.length + (_loadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= _posts.length) {
                  return const Center(child: CircularProgressIndicator());
                }
                final post = _posts[index];
                return PostGridTile(
                  key: ValueKey(post.id),
                  post: post,
                  imageUrl: _imageUrlFor(post),
                  selected: _selectedPostIds.contains(post.id),
                  onTap: () => _onTileTap(_posts, post),
                  onLongPress: () => _toggleSelection(post.id),
                  selectionMode: _selectionMode,
                );
              },
            ),
    );
  }
}
