import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../services/download_manager.dart';
import '../settings/display_settings_store.dart';
import '../settings/download_settings_store.dart';
import '../util/image_headers.dart';
import '../util/media_type.dart';
import '../util/mouse_drag_scroll_behavior.dart';
import '../widgets/post_media_page.dart';

/// Full-screen pinch-zoom + swipe-between-posts viewer (M8.5.9), opened by
/// tapping an image in [PostDetailScreen]. [posts] can mix images and videos
/// (M35) -- a video page plays in place via [Chewie] with zoom/pan disabled,
/// same player setup `PostDetailScreen` already uses, so swiping past a
/// video shows/plays it instead of silently skipping over it.
class FullScreenPostViewerScreen extends StatefulWidget {
  final List<BunnyPost> posts;
  final int initialIndex;
  final BunnyRepository repository;
  final DisplaySettingsStore displaySettingsStore;
  final DownloadManager downloadManager;
  final DownloadSettingsStore downloadSettingsStore;

  /// See [PostDetailScreen.poolId]/[PostDetailScreen.poolName]/
  /// [PostDetailScreen.pageByPostId] -- threaded straight through from
  /// there (M83), same reasoning: an already-downloaded pool post is filed
  /// under its pool's own folder, not the regular per-artist one, so this
  /// viewer's own local-file lookup needs the same pool context to find it.
  final int? poolId;
  final String? poolName;
  final Map<int, int> pageByPostId;

  /// Called live on every swipe here (not just once on exit), so whatever
  /// opened this screen can keep its own notion of "the current post" in
  /// sync without depending on how this screen eventually closes (close
  /// button vs. system back gesture both just pop, with no custom result).
  final ValueChanged<BunnyPost>? onPageChanged;

  const FullScreenPostViewerScreen({
    super.key,
    required this.posts,
    required this.initialIndex,
    required this.repository,
    this.displaySettingsStore = const DisplaySettingsStore(),
    this.downloadManager = const DownloadManager(),
    this.downloadSettingsStore = const DownloadSettingsStore(),
    this.poolId,
    this.poolName,
    this.pageByPostId = const {},
    this.onPageChanged,
  });

  @override
  State<FullScreenPostViewerScreen> createState() => _FullScreenPostViewerScreenState();
}

class _FullScreenPostViewerScreenState extends State<FullScreenPostViewerScreen> {
  late final PageController _controller = PageController(initialPage: widget.initialIndex);

  /// See `PostDetailScreen._preloadCount`'s doc comment -- same shape here.
  int _preloadCount = 3;

  /// Resolved once up front for every post in [FullScreenPostViewerScreen.
  /// posts] (M83), not lazily per page -- [DownloadManager.batchLocalFilePathFor]
  /// exists specifically to avoid one slow platform-channel round trip per
  /// post under Android's SAF (see its own doc comment), so resolving here
  /// in one batch call keeps that guarantee instead of each
  /// [PhotoViewGalleryPageOptions] page resolving its own. A post missing
  /// from this map simply has no local copy yet -- [PostMediaPage] falls
  /// back to fetching it over the network, same as before this existed.
  /// Starts empty, same as [PostDetailScreen]'s own local-file future: the
  /// very first frame(s) may briefly show the network path, swapping to the
  /// local one the moment this resolves.
  Map<int, String> _localFilePaths = {};

  @override
  void initState() {
    super.initState();
    _loadPreloadCountThenPreload();
    _resolveLocalFilePaths();
  }

  Future<void> _resolveLocalFilePaths() async {
    try {
      final folder = await widget.downloadSettingsStore.loadDestinationFolder();
      if (folder == null) {
        return;
      }
      final paths = await widget.downloadManager.batchLocalFilePathFor(widget.posts, folder, poolId: widget.poolId ?? 0, poolName: widget.poolName, pageByPostId: widget.pageByPostId);
      if (!mounted) {
        return;
      }
      setState(() => _localFilePaths = paths);
    } catch (_) {
      // Best-effort, same tolerance as every other local-filesystem check
      // in this app -- a failure here just means falling back to the
      // network, not a crash.
    }
  }

  Future<void> _loadPreloadCountThenPreload() async {
    final count = await widget.displaySettingsStore.loadImagePreloadCount();
    if (!mounted) {
      return;
    }
    setState(() => _preloadCount = count);
    _preloadAround(widget.initialIndex);
  }

  void _preloadAround(int index) {
    for (var offset = 1; offset <= _preloadCount; offset++) {
      _preloadAt(index - offset);
      _preloadAt(index + offset);
    }
  }

  void _preloadAt(int index) {
    if (index < 0 || index >= widget.posts.length) {
      return;
    }
    final post = widget.posts[index];
    if (isVideoExt(post.fileExt) || post.fileUrl == null) {
      return;
    }
    // Already resolved to a local copy (M83) -- nothing to precache over
    // the network, and PostMediaPage reads it straight off disk either way.
    if (_localFilePaths.containsKey(post.id)) {
      return;
    }
    precacheImage(CachedNetworkImageProvider(post.fileUrl!, headers: imageHeadersFor(post.site)), context);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    widget.repository.markPostSeen(widget.posts[index].id);
    _preloadAround(index);
    widget.onPageChanged?.call(widget.posts[index]);
  }

  void _goToDelta(int delta) {
    final current = _controller.page?.round() ?? widget.initialIndex;
    final target = current + delta;
    if (target < 0 || target >= widget.posts.length) {
      return;
    }
    _controller.animateToPage(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _goToDelta(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _goToDelta(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: _handleKey,
        child: Stack(
          children: [
            ScrollConfiguration(
              behavior: const MouseDragScrollBehavior(),
              child: PhotoViewGallery.builder(
                pageController: _controller,
                itemCount: widget.posts.length,
                onPageChanged: _onPageChanged,
                backgroundDecoration: const BoxDecoration(color: Colors.black),
                builder: (context, index) {
                  final post = widget.posts[index];
                  final isVideo = isVideoExt(post.fileExt) && post.fileUrl != null;
                  // minScale == maxScale locks PhotoView's own pan/zoom for a
                  // video (otherwise it competes with Chewie's scrub/tap
                  // controls for the same gestures), while still letting the
                  // outer gallery's own horizontal swipe move between pages
                  // like every other entry. .customChild + an explicit
                  // childSize (rather than imageProvider:, which makes
                  // PhotoView infer size from the decoded image) keeps the
                  // original aspect ratio even when the platform's image
                  // codec misreports an animated GIF's true dimensions.
                  return PhotoViewGalleryPageOptions.customChild(
                    child: PostMediaPage(post: post, localFilePath: _localFilePaths[post.id]),
                    childSize: post.width > 0 && post.height > 0 ? Size(post.width.toDouble(), post.height.toDouble()) : null,
                    minScale: PhotoViewComputedScale.contained,
                    maxScale: isVideo ? PhotoViewComputedScale.contained : PhotoViewComputedScale.covered * 3,
                    heroAttributes: PhotoViewHeroAttributes(tag: post.id),
                  );
                },
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: SafeArea(
                child: DecoratedBox(
                  decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                  child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
