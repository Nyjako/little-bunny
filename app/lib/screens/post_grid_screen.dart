import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../services/download_queue_service.dart';
import '../settings/display_settings_store.dart';
import '../settings/download_settings_store.dart';
import '../util/post_navigation.dart';
import '../util/responsive.dart';
import '../widgets/post_grid_tile.dart';
import '../widgets/rich_markup_text.dart';
import 'post_detail_screen.dart';
import 'tag_browse_screen.dart';
import 'wiki_page_screen.dart';

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
  // Screen-local only, not persisted via DisplaySettingsStore -- same
  // precedent as _unseenOnly above (that store is scoped to display
  // presentation settings, not query filter criteria). Starts at "all"
  // (every bit set, including the UNKNOWN bit -- see kRatingMaskUnknown's
  // own doc comment) so a fresh screen shows every post, unfiltered. The
  // UNKNOWN bit is never toggled by any chip in _showFilterSheet below, so
  // it stays permanently set for the lifetime of this screen -- an
  // unrecognized rating is never silently hidden by a filter the UI doesn't
  // actually expose a control for.
  int _ratingMask = kRatingMaskAll;
  int _mediaMask = kMediaMaskAll;
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

  /// Set only by [_selectEntireSearch] -- the full fetched result of paging
  /// through every post this search matches (could be well beyond [_posts],
  /// which only ever holds what infinite scroll has loaded so far). `null`
  /// means the current selection is resolved from [_posts] instead (the
  /// normal, loaded-only case). Holding up to tens of thousands of
  /// [BunnyPost] objects here is a real memory cost (unlike [_posts], which
  /// infinite scroll deliberately keeps bounded) but an acceptable one for
  /// a short-lived bulk-selection action.
  List<BunnyPost>? _entireSearchSelection;

  /// The actual [BunnyPost]s behind [_selectedPostIds] -- resolved from
  /// [_entireSearchSelection] when a "select entire search" is active,
  /// otherwise from [_posts] (today's loaded-only behavior, unchanged).
  List<BunnyPost> get _selectedPosts => (_entireSearchSelection ?? _posts).where((post) => _selectedPostIds.contains(post.id)).toList();

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

  /// A pool description (M26) is always e621 text (`fetchPool` always hits
  /// e621's own endpoint, see [_loadPoolInfo]), so every cross-reference in
  /// one -- author, wiki, post, or another pool -- is e621-only too (M50).
  /// Each callback pops this dialog before navigating, same as the original
  /// pool-reference-only behavior.
  void _openAuthorFromDialog(String authorName) {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TagBrowseScreen(
          site: BunnySite.e621,
          query: authorName,
          repository: widget.repository,
          displaySettingsStore: widget.displaySettingsStore,
          downloadSettingsStore: widget.downloadSettingsStore,
          downloadQueueService: widget.downloadQueueService,
        ),
      ),
    );
  }

  void _openWikiPageFromDialog(String title) {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WikiPageScreen(
          title: title,
          repository: widget.repository,
          displaySettingsStore: widget.displaySettingsStore,
          downloadSettingsStore: widget.downloadSettingsStore,
          downloadQueueService: widget.downloadQueueService,
        ),
      ),
    );
  }

  Future<void> _openPostLinkFromDialog(AppLocalizations l10n, BunnySite site, int externalId) async {
    Navigator.pop(context);
    await openExternalPost(
      context: context,
      l10n: l10n,
      repository: widget.repository,
      site: site,
      externalId: externalId,
      displaySettingsStore: widget.displaySettingsStore,
      downloadSettingsStore: widget.downloadSettingsStore,
      downloadQueueService: widget.downloadQueueService,
    );
  }

  void _openRelatedPoolFromDialog(int poolId) {
    Navigator.pop(context);
    _openRelatedPool(poolId);
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
                  ? RichMarkupText(
                      text: description,
                      onOpenAuthor: _openAuthorFromDialog,
                      onOpenWiki: _openWikiPageFromDialog,
                      onOpenPost: (site, externalId) => _openPostLinkFromDialog(l10n, site, externalId),
                      onOpenPool: _openRelatedPoolFromDialog,
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
  Future<List<BunnyPost>> _fetchPage(int page) =>
      widget.repository.listSearchPosts(widget.search.id, unseenOnly: _unseenOnly, ratingMask: _ratingMask, mediaMask: _mediaMask, page: page);

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
  /// as opposed to [_refreshLoadedPages] below. Also drops any selection --
  /// a changed post set can make a prior "select entire search" snapshot
  /// (or even a plain loaded-only selection) stale/inconsistent with what's
  /// now showing.
  Future<void> _resetAndReload() async {
    setState(() {
      _posts.clear();
      _loading = true;
      _hasMore = true;
      _nextPage = 1;
      _selectedPostIds.clear();
      _entireSearchSelection = null;
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

  void _toggleRatingBit(int bit) {
    setState(() => _ratingMask ^= bit);
    _resetAndReload();
  }

  void _toggleMediaBit(int bit) {
    setState(() => _mediaMask ^= bit);
    _resetAndReload();
  }

  /// Rating/media-type toggle chips (M28) -- the matching post *set* changes
  /// on every toggle, so each one triggers [_resetAndReload] (not
  /// [_refreshLoadedPages]), same as [_toggleUnseenOnly] above. Colors mirror
  /// [ratingBadgeFor]'s own scheme. The sheet's own [StatefulBuilder] setState
  /// only re-renders the chips with this screen's already-updated masks --
  /// the actual state lives on [_PostGridScreenState], not the sheet.
  void _showFilterSheet(AppLocalizations l10n) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            void toggleRating(int bit) {
              _toggleRatingBit(bit);
              setSheetState(() {});
            }

            void toggleMedia(int bit) {
              _toggleMediaBit(bit);
              setSheetState(() {});
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.postGridFilterRatingLabel, style: Theme.of(sheetContext).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilterChip(
                          label: Text(l10n.postGridFilterRatingSafe),
                          selected: _ratingMask & kRatingMaskSafe != 0,
                          selectedColor: Colors.green.withValues(alpha: 0.3),
                          onSelected: (_) => toggleRating(kRatingMaskSafe),
                        ),
                        FilterChip(
                          label: Text(l10n.postGridFilterRatingQuestionable),
                          selected: _ratingMask & kRatingMaskQuestionable != 0,
                          selectedColor: Colors.amber.withValues(alpha: 0.3),
                          onSelected: (_) => toggleRating(kRatingMaskQuestionable),
                        ),
                        FilterChip(
                          label: Text(l10n.postGridFilterRatingExplicit),
                          selected: _ratingMask & kRatingMaskExplicit != 0,
                          selectedColor: Colors.red.withValues(alpha: 0.3),
                          onSelected: (_) => toggleRating(kRatingMaskExplicit),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(l10n.postGridFilterMediaLabel, style: Theme.of(sheetContext).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilterChip(
                          label: Text(l10n.postGridFilterMediaImage),
                          selected: _mediaMask & kMediaMaskImage != 0,
                          onSelected: (_) => toggleMedia(kMediaMaskImage),
                        ),
                        FilterChip(
                          label: Text(l10n.postGridFilterMediaVideo),
                          selected: _mediaMask & kMediaMaskVideo != 0,
                          onSelected: (_) => toggleMedia(kMediaMaskVideo),
                        ),
                        FilterChip(
                          label: Text(l10n.postGridFilterMediaGif),
                          selected: _mediaMask & kMediaMaskGif != 0,
                          onSelected: (_) => toggleMedia(kMediaMaskGif),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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
  /// (M34) exists to avoid. [_selectEntireSearch] below is the "I actually
  /// want everything, even unloaded" counterpart.
  void _selectAll() {
    setState(() {
      _entireSearchSelection = null;
      _selectedPostIds
        ..clear()
        ..addAll(_posts.map((post) => post.id));
    });
  }

  /// Pages through every post this search matches (not just what's loaded),
  /// via the same [_fetchPage] infinite scroll already uses -- so it
  /// automatically respects the current unseen-only filter too. Shows a
  /// cancelable, determinate progress dialog (using [BunnySearch.totalCount]
  /// as the expected total -- an estimate, not a guarantee, since it can be
  /// stale if posts arrived since the last sync). Sequential, one page at a
  /// time, matching this screen's/TagBrowseScreen's existing infinite-scroll
  /// convention rather than introducing a different, parallel-fetch pattern
  /// just for this one action.
  Future<void> _selectEntireSearch(AppLocalizations l10n) async {
    var cancelled = false;
    final fetchedCount = ValueNotifier<int>(0);
    final all = <BunnyPost>[];

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(l10n.postGridSelectEntireSearchDialogTitle),
        content: ValueListenableBuilder<int>(
          valueListenable: fetchedCount,
          builder: (context, count, child) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: widget.search.totalCount > 0 ? count / widget.search.totalCount : null),
              const SizedBox(height: 8),
              Text(l10n.postGridSelectEntireSearchProgress(count, widget.search.totalCount)),
            ],
          ),
        ),
        // Only flips the flag -- the fetch loop below is the single place
        // that pops this dialog (whether it exits via cancellation or an
        // empty page), so a cancel landing right as the fetch would have
        // finished normally can never double-pop.
        actions: [TextButton(onPressed: () => cancelled = true, child: Text(l10n.commonCancel))],
      ),
    );

    try {
      var page = 1;
      while (!cancelled) {
        final pageItems = await _fetchPage(page);
        if (pageItems.isEmpty) {
          break;
        }
        all.addAll(pageItems);
        fetchedCount.value = all.length;
        page++;
      }
      if (!mounted) {
        return;
      }
      Navigator.pop(context);
      if (!cancelled && all.isNotEmpty) {
        setState(() {
          _entireSearchSelection = all;
          _selectedPostIds
            ..clear()
            ..addAll(all.map((post) => post.id));
        });
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.postGridSelectEntireSearchError)));
    }
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
          // "Add/Exclude/Remove from current search" (M54 partial) forks
          // the saved search's own query into a brand-new, unsaved
          // TagBrowseScreen -- this saved search itself is never altered.
          currentSearchSite: widget.search.site,
          currentSearchQuery: widget.search.query,
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
    setState(() {
      _selectedPostIds.clear();
      _entireSearchSelection = null;
    });
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
      _entireSearchSelection = null;
    });
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
    setState(() {
      _selectedPostIds.clear();
      _entireSearchSelection = null;
    });
    await _refreshLoadedPages();
  }

  /// Enqueues the whole selection and returns immediately (M43) -- the
  /// actual fetch/write/checksum work, folder/auto-favorite/auto-upvote
  /// resolution, and action-queue draining all now live inside
  /// [DownloadQueueService] itself, reported through its notifier rather
  /// than this screen's own state. No `_refreshLoadedPages()` afterward:
  /// downloading never mutates any post field this grid displays (unlike
  /// [_massFavorite]/[_massVote], which call it themselves after their own
  /// direct, still-synchronous actions). Resolves via [_selectedPosts], so a
  /// "select entire search" selection enqueues every matched post, not just
  /// what [_posts] had loaded.
  ///
  /// When this screen is itself a pool browse ([_poolId] non-null, M65),
  /// goes through [DownloadQueueService.enqueuePool] instead, so
  /// [DownloadManager] files each post under a pool-named folder with a
  /// page-numbered filename. Each selected post's page is its position in
  /// the *full* pool ([_entireSearchSelection] ?? [_posts], whichever is
  /// currently backing [_selectedPosts]), not its position within just the
  /// selection -- selecting only some of a pool's posts must not renumber
  /// them. The pool's own fetched name ([_poolInfo], e621 only -- Inkbunny
  /// has no pool-metadata endpoint at all) is preferred; this search's own
  /// label is the fallback, covering both Inkbunny pools and an e621 pool
  /// whose metadata fetch hasn't landed yet.
  void _massDownload(AppLocalizations l10n) {
    final selected = _selectedPosts;
    if (selected.isEmpty) {
      return;
    }
    final poolId = _poolId;
    if (poolId != null) {
      final fullOrder = _entireSearchSelection ?? _posts;
      final pageByPostId = {for (final (index, post) in fullOrder.indexed) post.id: index + 1};
      widget.downloadQueueService.enqueuePool(selected, widget.repository, poolId: poolId, poolName: _poolInfo?.name ?? widget.search.label, pageByPostId: pageByPostId);
    } else {
      widget.downloadQueueService.enqueueAll(selected, widget.repository);
    }
    setState(() {
      _selectedPostIds.clear();
      _entireSearchSelection = null;
    });
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
          IconButton(icon: const Icon(Icons.select_all), tooltip: l10n.postGridSelectAll, onPressed: _selectAll),
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
        IconButton(icon: const Icon(Icons.filter_list), tooltip: l10n.postGridFilterTooltip, onPressed: () => _showFilterSheet(l10n)),
        IconButton(
          icon: _syncing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh),
          tooltip: l10n.postGridRefreshTooltip,
          onPressed: _syncing ? null : _refresh,
        ),
        PopupMenuButton<void>(
          itemBuilder: (context) => [
            PopupMenuItem(onTap: _markAllSeen, child: Text(l10n.postGridMarkAllSeen)),
            PopupMenuItem(onTap: () => _selectEntireSearch(l10n), child: Text(l10n.postGridSelectEntireSearch(widget.search.totalCount))),
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
