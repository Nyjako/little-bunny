import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../util/image_headers.dart';
import '../util/mouse_drag_scroll_behavior.dart';

/// Full-screen pinch-zoom + swipe-between-posts viewer (M8.5.9), opened by
/// tapping an image in [PostDetailScreen]. Image posts only -- video posts
/// keep using the in-place player on the detail page and are never routed
/// here, so every entry in [posts] is assumed to have a renderable image
/// [BunnyPost.fileUrl].
class FullScreenPostViewerScreen extends StatefulWidget {
  final List<BunnyPost> posts;
  final int initialIndex;
  final BunnyRepository repository;

  const FullScreenPostViewerScreen({super.key, required this.posts, required this.initialIndex, required this.repository});

  @override
  State<FullScreenPostViewerScreen> createState() => _FullScreenPostViewerScreenState();
}

class _FullScreenPostViewerScreenState extends State<FullScreenPostViewerScreen> {
  late final PageController _controller = PageController(initialPage: widget.initialIndex);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    widget.repository.markPostSeen(widget.posts[index].id);
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
                  // .customChild + an explicit childSize (rather than imageProvider:,
                  // which makes PhotoView infer size from the decoded image) keeps
                  // the original aspect ratio even when the platform's image codec
                  // misreports an animated GIF's true dimensions.
                  return PhotoViewGalleryPageOptions.customChild(
                    child: CachedNetworkImage(imageUrl: post.fileUrl!, httpHeaders: imageHeadersFor(post.site), fit: BoxFit.contain),
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
