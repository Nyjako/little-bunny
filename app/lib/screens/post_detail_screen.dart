import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../settings/display_settings_store.dart';
import '../settings/sync_settings_store.dart';
import '../util/image_headers.dart';
import 'full_screen_post_viewer_screen.dart';
import 'post_grid_screen.dart';
import 'tag_browse_screen.dart';

const _imageExtensions = {'jpg', 'jpeg', 'png', 'gif', 'webp'};
const _videoExtensions = {'webm', 'mp4'};

bool _isImage(BunnyPost post) => post.fileExt != null && _imageExtensions.contains(post.fileExt!.toLowerCase());

/// Full read-only metadata + media viewer for a single post (M8.4, redesigned
/// in M8.5.8 to surface categorized tags, sources, and e621 pool/parent/
/// child navigation). No favorite/vote/comment actions yet -- that's M8.5.14.
/// Marks the post seen once, on open, same as tapping it used to in
/// `PostGridScreen` before this screen existed.
class PostDetailScreen extends StatefulWidget {
  final BunnyPost post;
  final BunnyRepository repository;
  final DisplaySettingsStore displaySettingsStore;
  final SyncSettingsStore syncSettingsStore;

  /// The post list this post was opened from (e.g. a grid's currently loaded
  /// posts), used to seed [FullScreenPostViewerScreen]'s swipeable gallery
  /// when the media is tapped (M8.5.9) -- filtered down to image posts only,
  /// since videos keep using the in-place player here. `null` (the default,
  /// used when opening a post standalone, e.g. via a parent/child/pool chip)
  /// falls back to a single-post gallery of just [post].
  final List<BunnyPost>? siblingPosts;

  const PostDetailScreen({super.key, required this.post, required this.repository, required this.displaySettingsStore, required this.syncSettingsStore, this.siblingPosts});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  VideoPlayerController? _videoController;
  Future<void>? _videoInitFuture;

  late final Future<List<BunnyPostTag>> _tagsFuture;
  late final Future<List<String>> _sourcesFuture;
  Future<BunnyPostRelationships>? _relationshipsFuture;
  Future<List<int>>? _poolIdsFuture;

  @override
  void initState() {
    super.initState();
    widget.repository.markPostSeen(widget.post.id);

    _tagsFuture = widget.repository.getPostTagsByCategory(widget.post.id);
    _sourcesFuture = widget.repository.getPostSources(widget.post.id);
    if (widget.post.site == BunnySite.e621) {
      _relationshipsFuture = widget.repository.getPostRelationships(widget.post.id);
      _poolIdsFuture = widget.repository.getPostPoolIds(widget.post.id);
    }

    final ext = widget.post.fileExt?.toLowerCase();
    final url = widget.post.fileUrl;
    if (ext != null && _videoExtensions.contains(ext) && url != null) {
      final controller = VideoPlayerController.networkUrl(Uri.parse(url), httpHeaders: imageHeadersFor(widget.post.site) ?? const {});
      _videoController = controller;
      _videoInitFuture = controller.initialize().then((_) {
        if (!mounted) {
          return;
        }
        controller.setLooping(true);
        controller.play();
        setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  void _toggleVideoPlayback() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    setState(() {
      controller.value.isPlaying ? controller.pause() : controller.play();
    });
  }

  void _openFullScreenViewer() {
    final images = (widget.siblingPosts ?? [widget.post]).where(_isImage).toList();
    final index = images.indexWhere((p) => p.id == widget.post.id);
    if (index == -1) {
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (context) => FullScreenPostViewerScreen(posts: images, initialIndex: index, repository: widget.repository)));
  }

  Widget _buildMedia(AppLocalizations l10n) {
    final post = widget.post;
    final ext = post.fileExt?.toLowerCase();
    if (ext == null || post.fileUrl == null) {
      return const SizedBox(height: 200);
    }
    final aspectRatio = (post.width > 0 && post.height > 0) ? post.width / post.height : 16 / 9;
    // Capped rather than purely aspect-ratio-driven -- an unbounded height
    // here would let a very tall/narrow image fill (or exceed) the whole
    // viewport, burying every metadata section below the fold.
    final maxHeight = MediaQuery.sizeOf(context).height * 0.6;
    Widget bounded(Widget child) => ConstrainedBox(constraints: BoxConstraints(maxHeight: maxHeight), child: AspectRatio(aspectRatio: aspectRatio, child: child));
    if (_imageExtensions.contains(ext)) {
      return GestureDetector(onTap: _openFullScreenViewer, child: bounded(CachedNetworkImage(imageUrl: post.fileUrl!, httpHeaders: imageHeadersFor(post.site), fit: BoxFit.contain)));
    }
    if (_videoExtensions.contains(ext)) {
      return FutureBuilder<void>(
        future: _videoInitFuture,
        builder: (context, snapshot) {
          final controller = _videoController!;
          if (snapshot.connectionState != ConnectionState.done) {
            return bounded(const Center(child: CircularProgressIndicator()));
          }
          return GestureDetector(onTap: _toggleVideoPlayback, child: ConstrainedBox(constraints: BoxConstraints(maxHeight: maxHeight), child: AspectRatio(aspectRatio: controller.value.aspectRatio, child: VideoPlayer(controller))));
        },
      );
    }
    return SizedBox(height: 200, child: Center(child: Text(l10n.postDetailUnsupportedFormat(ext))));
  }

  Widget _metadataRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 100, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold))), Expanded(child: Text(value))]),
  );

  Future<void> _copyPostId(AppLocalizations l10n) async {
    await Clipboard.setData(ClipboardData(text: '${widget.post.externalId}'));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.postDetailIdCopied)));
  }

  static String _titleCase(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  void _openTagBrowse(String query) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => TagBrowseScreen(site: widget.post.site, query: query, repository: widget.repository, displaySettingsStore: widget.displaySettingsStore, syncSettingsStore: widget.syncSettingsStore)),
    );
  }

  Widget _tagsSection(AppLocalizations l10n) => FutureBuilder<List<BunnyPostTag>>(
    future: _tagsFuture,
    builder: (context, snapshot) {
      final tags = snapshot.data ?? const [];
      if (tags.isEmpty) {
        return const SizedBox.shrink();
      }
      final grouped = <String?, List<BunnyPostTag>>{};
      for (final tag in tags) {
        grouped.putIfAbsent(tag.category, () => []).add(tag);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          for (final entry in grouped.entries) ...[
            Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(entry.key == null ? l10n.postDetailTagsLabel : _titleCase(entry.key!), style: Theme.of(context).textTheme.titleSmall)),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(spacing: 4, runSpacing: 4, children: entry.value.map((tag) => ActionChip(label: Text(tag.name), onPressed: () => _openTagBrowse(tag.name))).toList()),
            ),
          ],
        ],
      );
    },
  );

  Future<void> _launchSource(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _sourcesSection(AppLocalizations l10n) => FutureBuilder<List<String>>(
    future: _sourcesFuture,
    builder: (context, snapshot) {
      final sources = snapshot.data ?? const [];
      if (sources.isEmpty) {
        return const SizedBox.shrink();
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(l10n.postDetailSourcesLabel, style: Theme.of(context).textTheme.titleSmall)),
          for (final url in sources)
            InkWell(
              onTap: () => _launchSource(url),
              child: Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(url, style: const TextStyle(color: Colors.blue, decoration: TextDecoration.underline))),
            ),
        ],
      );
    },
  );

  Future<void> _openExternalPost(AppLocalizations l10n, int externalId) async {
    try {
      final postId = await widget.repository.fetchPost(widget.post.site, externalId);
      final post = await widget.repository.getPost(postId);
      if (!mounted) {
        return;
      }
      await Navigator.push(context, MaterialPageRoute(builder: (context) => PostDetailScreen(post: post, repository: widget.repository, displaySettingsStore: widget.displaySettingsStore, syncSettingsStore: widget.syncSettingsStore)));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.postDetailOpenPostFailed)));
    }
  }

  Widget _relationshipsSection(AppLocalizations l10n) {
    final future = _relationshipsFuture;
    if (future == null) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<BunnyPostRelationships>(
      future: future,
      builder: (context, snapshot) {
        final relationships = snapshot.data;
        if (relationships == null || (!relationships.hasParent && relationships.children.isEmpty)) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(),
            if (relationships.hasParent) ...[
              Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(l10n.postDetailParentLabel, style: Theme.of(context).textTheme.titleSmall)),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(spacing: 4, children: [ActionChip(label: Text('#${relationships.parentExternalId}'), onPressed: () => _openExternalPost(l10n, relationships.parentExternalId!))]),
              ),
            ],
            if (relationships.children.isNotEmpty) ...[
              Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(l10n.postDetailChildrenLabel, style: Theme.of(context).textTheme.titleSmall)),
              Wrap(spacing: 4, runSpacing: 4, children: relationships.children.map((id) => ActionChip(label: Text('#$id'), onPressed: () => _openExternalPost(l10n, id))).toList()),
            ],
          ],
        );
      },
    );
  }

  Future<void> _openPool(AppLocalizations l10n, int poolId) async {
    try {
      final searches = await widget.repository.listSearches();
      final existing = searches.where((search) => search.site == BunnySite.e621 && search.query == 'pool:$poolId');
      BunnySearch? target = existing.isEmpty ? null : existing.first;

      if (target == null) {
        if (!mounted) {
          return;
        }
        final create = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.postDetailCreatePoolSearchDialogTitle),
            content: Text(l10n.postDetailCreatePoolSearchDialogContent(poolId)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.commonCancel)),
              TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.createPoolSearchSubmit)),
            ],
          ),
        );
        if (create != true) {
          return;
        }

        String label = 'pool:$poolId';
        try {
          final info = await widget.repository.fetchPool(poolId);
          if (info.name != null && info.name!.isNotEmpty) {
            label = info.name!;
          }
        } catch (_) {
          // Fall back to the default label above.
        }

        final searchId = await widget.repository.createSearch(BunnySite.e621, label, 'pool:$poolId');
        final refreshed = await widget.repository.listSearches();
        target = refreshed.firstWhere((search) => search.id == searchId);
      }

      if (!mounted) {
        return;
      }
      await Navigator.push(context, MaterialPageRoute(builder: (context) => PostGridScreen(search: target!, repository: widget.repository, displaySettingsStore: widget.displaySettingsStore, syncSettingsStore: widget.syncSettingsStore)));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.postDetailOpenPostFailed)));
    }
  }

  Widget _poolsSection(AppLocalizations l10n) {
    final future = _poolIdsFuture;
    if (future == null) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<List<int>>(
      future: future,
      builder: (context, snapshot) {
        final poolIds = snapshot.data ?? const [];
        if (poolIds.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(),
            Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(l10n.postDetailPoolsLabel, style: Theme.of(context).textTheme.titleSmall)),
            Wrap(spacing: 4, runSpacing: 4, children: poolIds.map((id) => ActionChip(label: Text('#$id'), onPressed: () => _openPool(l10n, id))).toList()),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final post = widget.post;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.postDetailScreenTitle)),
      body: ListView(
        children: [
          _buildMedia(l10n),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (post.title != null && post.title!.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(post.title!, style: Theme.of(context).textTheme.titleLarge)),
                post.artist != null && post.artist!.isNotEmpty
                    ? InkWell(onTap: () => _openTagBrowse(post.artist!), child: _metadataRow(l10n.postDetailArtistLabel, post.artist!))
                    : _metadataRow(l10n.postDetailArtistLabel, l10n.postDetailUnknownValue),
                if (post.description != null && post.description!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8, bottom: 8), child: Text(post.description!)),
                const Divider(),
                InkWell(onTap: () => _copyPostId(l10n), child: _metadataRow(l10n.postDetailIdLabel, '${post.externalId}')),
                _metadataRow(l10n.postDetailRatingLabel, post.rating ?? l10n.postDetailUnknownValue),
                _metadataRow(l10n.postDetailScoreLabel, '${post.score}'),
                _metadataRow(l10n.postDetailFavoritesLabel, '${post.favCount}'),
                _metadataRow(l10n.postDetailCommentsLabel, '${post.commentCount}'),
                _metadataRow(l10n.postDetailDimensionsLabel, '${post.width}x${post.height}'),
                _metadataRow(l10n.postDetailCreatedLabel, post.createdAtSite ?? l10n.postDetailUnknownValue),
                _tagsSection(l10n),
                _sourcesSection(l10n),
                _relationshipsSection(l10n),
                _poolsSection(l10n),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
