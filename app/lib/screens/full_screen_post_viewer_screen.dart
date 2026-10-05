import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../util/image_headers.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PhotoViewGallery.builder(
        pageController: _controller,
        itemCount: widget.posts.length,
        onPageChanged: _onPageChanged,
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        builder: (context, index) {
          final post = widget.posts[index];
          return PhotoViewGalleryPageOptions(
            imageProvider: CachedNetworkImageProvider(post.fileUrl!, headers: imageHeadersFor(post.site)),
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 3,
            heroAttributes: PhotoViewHeroAttributes(tag: post.id),
          );
        },
      ),
    );
  }
}
