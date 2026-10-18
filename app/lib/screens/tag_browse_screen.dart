import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../settings/display_settings_store.dart';
import '../settings/download_settings_store.dart';
import '../util/responsive.dart';
import '../widgets/post_grid_tile.dart';
import 'create_search_screen.dart';
import 'post_detail_screen.dart';

/// Click-through browsing for a tag or artist name tapped elsewhere in the
/// app (M8.5.10): runs a stateless live search (`BunnyRepository.
/// previewSearch`) and shows the results as a grid, without creating a saved
/// search. An app bar action offers to save the query as a real search via
/// [CreateSearchScreen], pre-filled. M9.6.2 turned the originally single-page
/// preview into an infinite scroll: scrolling near the bottom of the grid
/// fetches and appends the next page, so a tag with hundreds of thousands of
/// matches is still fully reachable rather than stuck on the first 320.
class TagBrowseScreen extends StatefulWidget {
  final BunnySite site;
  final String query;
  final BunnyRepository repository;
  final DisplaySettingsStore displaySettingsStore;
  final DownloadSettingsStore downloadSettingsStore;

  /// Pre-fills the label field when the user chooses to save this browse as
  /// a search (e.g. a pool's own title, M9.6.3) -- `null` leaves the label
  /// field mirroring [query] like every other browse-to-save flow.
  final String? initialLabel;

  /// Overrides [query]-based fetching with a custom page-fetch callback when
  /// set (M10.3 -- used for Inkbunny's "my own favorites", which has no
  /// expressible query string). When set, the "add to searches" action is
  /// omitted entirely (there's no query string to save) and [query] itself is
  /// never read for fetching, only as the default app bar title.
  final Future<List<BunnyPost>> Function(int page)? customFetch;

  /// Overrides the app bar title -- defaults to [query] (today's behavior)
  /// when `null`, which doesn't make sense to show verbatim when
  /// [customFetch] is set.
  final String? title;

  const TagBrowseScreen({
    super.key,
    required this.site,
    required this.query,
    required this.repository,
    required this.displaySettingsStore,
    required this.downloadSettingsStore,
    this.initialLabel,
    this.customFetch,
    this.title,
  });

  @override
  State<TagBrowseScreen> createState() => _TagBrowseScreenState();
}

class _TagBrowseScreenState extends State<TagBrowseScreen> {
  final List<BunnyPost> _posts = [];
  final Set<int> _seenPostIds = {};
  final _scrollController = ScrollController();
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _nextPage = 1;
  PreviewQuality _previewQuality = PreviewQuality.thumbnail;
  int _gridColumns = 3;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _loadDisplaySettings();
    _scrollController.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_maybeLoadMore)
      ..dispose();
    super.dispose();
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

  void _appendPage(List<BunnyPost> page) {
    for (final post in page) {
      if (_seenPostIds.add(post.id)) {
        _posts.add(post);
      }
    }
  }

  /// e621's own default sort is newest-first (by post id) -- right for a
  /// normal tag browse, but backwards for a pool (M9.6.3's live preview,
  /// M22's ordering fix), which reads like a comic: page 1 should come
  /// first. Unlike [PostGridScreen] (which reorders an already-fully-synced
  /// local list by reversing it), this is a live, paginated e621 search, so
  /// the fix has to ask the site itself to sort ascending -- reversing one
  /// page at a time wouldn't produce a correct overall order across pages.
  Future<List<BunnyPost>> _fetchPage(int page) {
    final customFetch = widget.customFetch;
    if (customFetch != null) {
      return customFetch(page);
    }
    final query = widget.query.startsWith('pool:') ? '${widget.query} order:id' : widget.query;
    return widget.repository.previewSearch(widget.site, query, page: page);
  }

  Future<void> _loadInitial() async {
    final page = await _fetchPage(1);
    if (!mounted) {
      return;
    }
    setState(() {
      _appendPage(page);
      _loading = false;
      _hasMore = page.isNotEmpty;
      _nextPage = 2;
    });
  }

  // An empty page means there's nothing more to fetch; any non-empty page
  // (even a short one) is treated as "there might be more" rather than
  // comparing against the site's own page size -- e621's limit lives only in
  // bunny_core (see BUNNY_CORE_SYNC_E621_PAGE_LIMIT), not here, and this way
  // never silently drifts out of sync with it. Worst case: one extra request
  // that comes back empty before _hasMore flips to false.
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
      _appendPage(page);
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

  String? _imageUrlFor(BunnyPost post) {
    if (_previewQuality == PreviewQuality.medium && post.sampleUrl != null) {
      return post.sampleUrl;
    }
    return post.previewUrl;
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
  }

  Future<void> _addToSearches() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            CreateSearchScreen(repository: widget.repository, initialSite: widget.site, initialQuery: widget.query, initialLabel: widget.initialLabel),
      ),
    );
    if (created == true && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: isWideScreen(context) ? compactToolbarHeight : null,
        title: Text(widget.title ?? widget.query),
        actions: widget.customFetch == null ? [IconButton(icon: const Icon(Icons.add), tooltip: l10n.tagBrowseAddToSearchesTooltip, onPressed: _addToSearches)] : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _posts.isEmpty
          ? Center(child: Text(l10n.tagBrowseEmptyState))
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
                return PostGridTile(key: ValueKey(post.id), post: post, imageUrl: _imageUrlFor(post), onTap: () => _openPost(_posts, post));
              },
            ),
    );
  }
}
