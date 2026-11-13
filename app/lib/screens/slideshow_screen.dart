import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../widgets/post_media_page.dart';

/// Fullscreen, timer-driven slideshow over a fixed set of posts, played back
/// from local files already on disk (M51 v2 -- superseding v1's live
/// network streaming, see `SlideshowPrepareService`/`SlideshowEditScreen`
/// for how [posts]/[localFilePaths] get resolved before this screen ever
/// opens), cycled through locally forever until the user closes this
/// screen. The interval auto-advances regardless of what's playing (never
/// blocks on a video/gif finishing), but M76 adds manual control on top of
/// that: tapping the left/right half of the screen or pressing the
/// Left/Right arrow keys steps to the previous/next post immediately and
/// restarts the interval timer, so auto-advance doesn't also fire right on
/// top of a manual step.
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

  /// Grabs keyboard focus on open so arrow keys work without the user
  /// needing to click into the screen first -- there's nothing else on
  /// this fullscreen view that would otherwise want it.
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _order = List.generate(widget.posts.length, (i) => i)..shuffle();
    _markSeen(_currentPost);
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.interval, (_) => _advance());
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

  /// Manual "next" (tap the right half / Right arrow, M76) -- same
  /// post-order step as the timer's own [_advance], but also restarts the
  /// interval timer so auto-advance doesn't fire again right on top of
  /// this one.
  void _goNext() {
    _advance();
    _startTimer();
  }

  /// Manual "previous" (tap the left half / Left arrow, M76) -- steps back
  /// one post within the current shuffle, wrapping to its end rather than
  /// reshuffling: there's no "previous shuffle" left to go back to once
  /// [_advance] has already moved past it.
  void _goPrevious() {
    setState(() => _cursor = _cursor == 0 ? _order.length - 1 : _cursor - 1);
    _markSeen(_currentPost);
    _startTimer();
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _goNext();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _goPrevious();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKey,
        child: Stack(
          children: [
            // A post-specific key, not just a plain PostMediaPage(...) --
            // without one, every post reuses the exact same Stack slot, so
            // Flutter keeps the old State alive across _advance()/_goNext()
            // instead of rebuilding it. Image.file (Linux/Windows, a plain
            // path) tolerates that since it diffs by ImageProvider equality
            // and reloads anyway, but _LocalContentUriImage/GifPlayer/the
            // video controller (Android SAF content:// paths) only ever
            // read their bytes once in initState -- confirmed live as why
            // the slideshow got stuck on the first post on Android (auto
            // *and* manual advance alike): the cursor moved, but the
            // on-screen media silently kept rendering the first post's
            // already-loaded bytes forever.
            Center(child: PostMediaPage(key: ValueKey(_currentPost.id), post: _currentPost, localFilePath: widget.localFilePaths[_currentPost.id])),
            Row(
              children: [
                Expanded(child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: _goPrevious)),
                Expanded(child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: _goNext)),
              ],
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
