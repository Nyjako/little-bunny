import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../settings/display_settings_store.dart';
import '../util/image_headers.dart';
import '../widgets/rating_badge.dart';
import 'post_detail_screen.dart';

/// Shows a [BunnySearch]'s cached posts as a thumbnail grid, with an unseen
/// marker overlay and an "unseen only" filter (M8.3). Tapping a post opens
/// [PostDetailScreen] (M8.4), which marks it seen on open; the grid reloads
/// on return so the cleared marker shows up immediately.
class PostGridScreen extends StatefulWidget {
  final BunnySearch search;
  final BunnyRepository repository;
  final DisplaySettingsStore displaySettingsStore;

  const PostGridScreen({super.key, required this.search, required this.repository, required this.displaySettingsStore});

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

  Future<void> _openPost(BunnyPost post) async {
    await Navigator.push(context, MaterialPageRoute(builder: (context) => PostDetailScreen(post: post, repository: widget.repository, displaySettingsStore: widget.displaySettingsStore)));
    if (!mounted) {
      return;
    }
    setState(() {
      _postsFuture = _loadPosts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
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
      ),
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
              final imageUrl = _imageUrlFor(post);
              return GestureDetector(
                key: ValueKey(post.id),
                onTap: () => _openPost(post),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (imageUrl != null) CachedNetworkImage(imageUrl: imageUrl, httpHeaders: imageHeadersFor(post.site), fit: BoxFit.cover) else const ColoredBox(color: Colors.black12),
                    if (!post.isSeen) Positioned(top: 4, right: 4, child: Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle))),
                    Positioned(top: 4, left: 4, child: RatingBadge(site: post.site, rating: post.rating)),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        color: Colors.black54,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.arrow_upward, size: 10, color: Colors.white),
                                Text('${post.score}', style: const TextStyle(color: Colors.white, fontSize: 10)),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.favorite, size: 10, color: Colors.white),
                                Text('${post.favCount}', style: const TextStyle(color: Colors.white, fontSize: 10)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
