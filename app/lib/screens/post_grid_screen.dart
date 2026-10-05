import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../settings/display_settings_store.dart';
import '../settings/download_settings_store.dart';
import '../settings/sync_settings_store.dart';
import '../widgets/post_grid_tile.dart';
import 'post_detail_screen.dart';

/// Shows a [BunnySearch]'s cached posts as a thumbnail grid, with an unseen
/// marker overlay and an "unseen only" filter (M8.3). Tapping a post opens
/// [PostDetailScreen] (M8.4), which marks it seen on open; the grid reloads
/// on return so the cleared marker shows up immediately.
class PostGridScreen extends StatefulWidget {
  final BunnySearch search;
  final BunnyRepository repository;
  final DisplaySettingsStore displaySettingsStore;
  final SyncSettingsStore syncSettingsStore;
  final DownloadSettingsStore downloadSettingsStore;

  const PostGridScreen({super.key, required this.search, required this.repository, required this.displaySettingsStore, required this.syncSettingsStore, required this.downloadSettingsStore});

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

  @override
  void initState() {
    super.initState();
    _postsFuture = _loadPosts();
    _loadDisplaySettings();
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

  Future<void> _openPost(List<BunnyPost> posts, BunnyPost post) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PostDetailScreen(
          post: post,
          repository: widget.repository,
          displaySettingsStore: widget.displaySettingsStore,
          syncSettingsStore: widget.syncSettingsStore,
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

  AppBar _buildAppBar(AppLocalizations l10n) {
    if (_selectionMode) {
      final votingEnabled = widget.search.site != BunnySite.inkbunny;
      return AppBar(
        leading: IconButton(icon: const Icon(Icons.close), tooltip: l10n.postGridExitSelectionTooltip, onPressed: _exitSelectionMode),
        title: Text(l10n.postGridSelectionCount(_selectedPostIds.length)),
        actions: [
          IconButton(icon: const Icon(Icons.favorite), tooltip: l10n.postGridMassFavoriteTooltip, onPressed: _massFavorite),
          if (votingEnabled) IconButton(icon: const Icon(Icons.arrow_upward), tooltip: l10n.postGridMassUpvoteTooltip, onPressed: () => _massVote(1)),
          if (votingEnabled) IconButton(icon: const Icon(Icons.arrow_downward), tooltip: l10n.postGridMassDownvoteTooltip, onPressed: () => _massVote(-1)),
        ],
      );
    }
    return AppBar(
      title: Text(widget.search.label),
      actions: [
        IconButton(icon: Icon(_unseenOnly ? Icons.visibility_off : Icons.visibility), tooltip: l10n.postGridUnseenOnlyTooltip, onPressed: _toggleUnseenOnly),
        IconButton(
          icon: _syncing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh),
          tooltip: l10n.postGridRefreshTooltip,
          onPressed: _syncing ? null : _refresh,
        ),
        PopupMenuButton<void>(
          itemBuilder: (context) => [PopupMenuItem(onTap: _markAllSeen, child: Text(l10n.postGridMarkAllSeen))],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: _buildAppBar(l10n),
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
              );
            },
          );
        },
      ),
    );
  }
}
