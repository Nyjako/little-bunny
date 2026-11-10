import 'dart:async';

import 'package:flutter/material.dart';

import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../widgets/post_media_page.dart';

/// Fullscreen, timer-driven slideshow over a fixed set of posts, played back
/// from local files already on disk (M51 v2 -- superseding v1's live
/// network streaming, see `SlideshowPrepareService`/`SlideshowEditScreen`
/// for how [posts]/[localFilePaths] get resolved before this screen ever
/// opens), cycled through locally forever until the user closes this
/// screen. Unlike `FullScreenPostViewerScreen`, advancing is never manual
/// (no swipe/pinch -- just [PostMediaPage]'s bare media, one at a time) and
/// never blocks on a video/gif finishing -- the interval ticks regardless
/// of what's playing.
class SlideshowScreen extends StatefulWidget {
  final List<BunnyPost> posts;

  /// Every entry in [posts] must have a matching key here (M51 v2 -- a
  /// caller only ever passes the subset of a slideshow's committed posts
  /// that [SlideshowPrepareReport.readyPosts] already confirmed are on
  /// disk, so there's no network-fallback branch to fall back to if one's
  /// missing).
  final Map<int, String> localFilePaths;
  final Duration interval;
  final BunnyRepository repository;

  const SlideshowScreen({super.key, required this.posts, required this.localFilePaths, required this.interval, required this.repository});

  @override
  State<SlideshowScreen> createState() => _SlideshowScreenState();
}

class _SlideshowScreenState extends State<SlideshowScreen> {
  late List<int> _order;
  int _cursor = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _order = List.generate(widget.posts.length, (i) => i)..shuffle();
    _markSeen(_currentPost);
    _timer = Timer.periodic(widget.interval, (_) => _advance());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  BunnyPost get _currentPost => widget.posts[_order[_cursor]];

  void _markSeen(BunnyPost post) => widget.repository.markPostSeen(post.id);

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
          Center(child: PostMediaPage(post: _currentPost, localFilePath: widget.localFilePaths[_currentPost.id])),
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
