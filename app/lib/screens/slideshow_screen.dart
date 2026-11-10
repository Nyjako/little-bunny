import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../util/image_headers.dart';
import '../util/media_type.dart';
import '../widgets/post_media_page.dart';

/// Fullscreen, timer-driven slideshow over a fixed set of posts (M51) --
/// fetched once by the caller (a server-side random sample, see
/// `BunnyRepository.getSlideshowRandomPosts`), then cycled through locally
/// forever until the user closes this screen. Unlike
/// `FullScreenPostViewerScreen`, advancing is never manual (no swipe/pinch --
/// just [PostMediaPage]'s bare media, one at a time) and never blocks on a
/// video/gif finishing -- the interval ticks regardless of what's playing.
class SlideshowScreen extends StatefulWidget {
  final List<BunnyPost> posts;
  final Duration interval;
  final BunnyRepository repository;

  const SlideshowScreen({super.key, required this.posts, required this.interval, required this.repository});

  @override
  State<SlideshowScreen> createState() => _SlideshowScreenState();
}

class _SlideshowScreenState extends State<SlideshowScreen> {
  late List<int> _order;
  int _cursor = 0;
  Timer? _timer;
  bool _preloaded = false;

  @override
  void initState() {
    super.initState();
    _order = List.generate(widget.posts.length, (i) => i)..shuffle();
    _markSeen(_currentPost);
    _timer = Timer.periodic(widget.interval, (_) => _advance());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // precacheImage needs MediaQuery via context, not available yet during
    // initState (same reason FullScreenPostViewerScreen's own preload call
    // only ever runs after an async gap) -- didChangeDependencies is the
    // framework's own recommended place for context-dependent init work.
    // Guarded to run exactly once; this can otherwise fire again later if
    // an ancestor InheritedWidget changes.
    if (!_preloaded) {
      _preloaded = true;
      _preloadAll();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  BunnyPost get _currentPost => widget.posts[_order[_cursor]];

  void _markSeen(BunnyPost post) => widget.repository.markPostSeen(post.id);

  /// Every post's image/gif is precached up front (bounded by the user's
  /// own chosen count, so eagerly warming all of them -- not just a window
  /// around the current one, see `FullScreenPostViewerScreen._preloadAt` --
  /// is fine). Videos stay lazily initialized per [PostMediaPage]: this
  /// screen shows exactly one post at a time (a plain swap, not a
  /// `PageView`), so the previous page's `VideoPlayerController` is already
  /// disposed by the time the next one would be created -- never more than
  /// one live decoder, with no extra bookkeeping needed here.
  void _preloadAll() {
    for (final post in widget.posts) {
      if (isVideoExt(post.fileExt) || post.fileUrl == null) {
        continue;
      }
      precacheImage(CachedNetworkImageProvider(post.fileUrl!, headers: imageHeadersFor(post.site)), context);
    }
  }

  /// Reshuffles and loops back to the start once every post in [_order] has
  /// been shown once -- "reshuffle and keep going until closed," per M51 --
  /// rather than re-fetching from the server.
  void _advance() {
    setState(() {
      _cursor++;
      if (_cursor >= _order.length) {
        _order.shuffle();
        _cursor = 0;
      }
    });
    _markSeen(_currentPost);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(child: PostMediaPage(post: _currentPost)),
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
    );
  }
}
