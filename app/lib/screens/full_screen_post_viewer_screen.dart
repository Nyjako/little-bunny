import 'package:cached_network_image/cached_network_image.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:video_player/video_player.dart';

import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../settings/display_settings_store.dart';
import '../util/image_headers.dart';
import '../util/media_type.dart';
import '../util/mouse_drag_scroll_behavior.dart';
import '../widgets/download_progress_indicator.dart';
import '../widgets/gif_player.dart';

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
    this.onPageChanged,
  });

  @override
  State<FullScreenPostViewerScreen> createState() => _FullScreenPostViewerScreenState();
}

class _FullScreenPostViewerScreenState extends State<FullScreenPostViewerScreen> {
  late final PageController _controller = PageController(initialPage: widget.initialIndex);

  /// See `PostDetailScreen._preloadCount`'s doc comment -- same shape here.
  int _preloadCount = 3;

  @override
  void initState() {
    super.initState();
    _loadPreloadCountThenPreload();
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
                  if (isVideoExt(post.fileExt) && post.fileUrl != null) {
                    // minScale == maxScale locks PhotoView's own pan/zoom
                    // (otherwise it competes with Chewie's scrub/tap
                    // controls for the same gestures), while still letting
                    // the outer gallery's own horizontal swipe move between
                    // pages like every other entry.
                    return PhotoViewGalleryPageOptions.customChild(
                      child: _FullScreenVideoPage(post: post),
                      childSize: post.width > 0 && post.height > 0 ? Size(post.width.toDouble(), post.height.toDouble()) : null,
                      minScale: PhotoViewComputedScale.contained,
                      maxScale: PhotoViewComputedScale.contained,
                      heroAttributes: PhotoViewHeroAttributes(tag: post.id),
                    );
                  }
                  // .customChild + an explicit childSize (rather than imageProvider:,
                  // which makes PhotoView infer size from the decoded image) keeps
                  // the original aspect ratio even when the platform's image codec
                  // misreports an animated GIF's true dimensions.
                  // Image's own loadingBuilder, not CachedNetworkImage's
                  // progressIndicatorBuilder -- see PostDetailScreen's
                  // _buildMedia for why (the latter never settles under
                  // `flutter_test`'s pumpAndSettle).
                  final content = isGifExt(post.fileExt)
                      ? GifPlayer(imageUrl: post.fileUrl!, httpHeaders: imageHeadersFor(post.site))
                      : Image(
                          image: CachedNetworkImageProvider(post.fileUrl!, headers: imageHeadersFor(post.site)),
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) {
                              return child;
                            }
                            final total = loadingProgress.expectedTotalBytes;
                            return DownloadProgressIndicator(progress: total != null ? loadingProgress.cumulativeBytesLoaded / total : null);
                          },
                        );
                  return PhotoViewGalleryPageOptions.customChild(
                    child: content,
                    childSize: post.width > 0 && post.height > 0 ? Size(post.width.toDouble(), post.height.toDouble()) : null,
                    minScale: PhotoViewComputedScale.contained,
                    maxScale: PhotoViewComputedScale.covered * 3,
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

/// One video page inside the gallery -- same player setup as
/// `PostDetailScreen`'s own video branch (muted by default, looping,
/// post-metadata aspect ratio over the decoded video's own, since that one
/// can be wrong). A separate `StatefulWidget` so [VideoPlayerController]/
/// [ChewieController] init/dispose follows this page's own widget lifecycle
/// (created when `PhotoViewGallery.builder` builds it, disposed once
/// scrolled far enough away), the same way `_PostDetailPage` already does
/// inside `PostDetailScreen`'s own `PageView`.
class _FullScreenVideoPage extends StatefulWidget {
  final BunnyPost post;

  const _FullScreenVideoPage({required this.post});

  @override
  State<_FullScreenVideoPage> createState() => _FullScreenVideoPageState();
}

class _FullScreenVideoPageState extends State<_FullScreenVideoPage> {
  late final VideoPlayerController _videoController;
  ChewieController? _chewieController;

  @override
  void initState() {
    super.initState();
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.post.fileUrl!), httpHeaders: imageHeadersFor(widget.post.site) ?? const {});
    controller.setVolume(0);
    _videoController = controller;
    final aspectRatio = (widget.post.width > 0 && widget.post.height > 0) ? widget.post.width / widget.post.height : 16 / 9;
    controller.initialize().then((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        // allowFullScreen: false (unlike PostDetailScreen's own video player)
        // -- already inside this screen's own fullscreen gallery, so
        // Chewie's separate fullscreen route would be redundant.
        _chewieController = ChewieController(videoPlayerController: controller, aspectRatio: aspectRatio, autoPlay: true, looping: true, allowFullScreen: false, allowMuting: true);
      });
    });
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chewieController = _chewieController;
    if (chewieController == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Chewie(controller: chewieController);
  }
}
