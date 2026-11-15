import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
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
/// top of a manual step. M78 adds a pause toggle (tap the middle zone
/// between left/right, or press spacebar) that only gates the automatic
/// timer -- manual stepping still works while paused -- plus a bottom bar
/// with favorite/upvote buttons, positioned clear of the image itself.
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

  /// M78 -- tapping the middle zone or pressing spacebar toggles this,
  /// which only ever gates the *automatic* interval timer; manual
  /// prev/next (tap the edges, arrow keys) still works while paused, and
  /// deliberately does not itself resume the timer (see [_goNext]/
  /// [_goPrevious]'s own doc comments) -- stepping through a few posts by
  /// hand while paused shouldn't silently restart autoplay underneath you.
  bool _paused = false;

  /// Per-post-id local overrides (M78) -- [widget.posts] is immutable, so a
  /// favorite/vote tap can't just mutate the current post's own fields the
  /// way `PostDetailScreen._applyOptimisticUpdate` does. Absent here means
  /// "use the post's own cached isFavorited/userVote" (whatever sync last
  /// stored); present means a later vote/favorite was queued successfully
  /// against the real one this session, which should win.
  final Map<int, bool> _favoriteOverrides = {};
  final Map<int, int> _voteOverrides = {};

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
  /// this one -- unless [_paused] (M78), in which case it stays paused:
  /// stepping through a few posts by hand shouldn't silently resume autoplay.
  void _goNext() {
    _advance();
    if (!_paused) {
      _startTimer();
    }
  }

  /// Manual "previous" (tap the left half / Left arrow, M76) -- steps back
  /// one post within the current shuffle, wrapping to its end rather than
  /// reshuffling: there's no "previous shuffle" left to go back to once
  /// [_advance] has already moved past it. Same [_paused] gate as [_goNext].
  void _goPrevious() {
    setState(() => _cursor = _cursor == 0 ? _order.length - 1 : _cursor - 1);
    _markSeen(_currentPost);
    if (!_paused) {
      _startTimer();
    }
  }

  /// Tap the middle zone or press spacebar (M78) -- pauses/resumes only the
  /// automatic interval timer. Manual navigation keeps working regardless
  /// of this flag (see [_goNext]/[_goPrevious]).
  void _togglePause() {
    setState(() => _paused = !_paused);
    if (_paused) {
      _timer?.cancel();
    } else {
      _startTimer();
    }
  }

  bool _isFavorited(BunnyPost post) => _favoriteOverrides[post.id] ?? post.isFavorited;

  int _voteFor(BunnyPost post) => _voteOverrides[post.id] ?? post.userVote;

  /// Same queueFavoriteAdd/queueFavoriteRemove + immediate processQueue
  /// drain `PostDetailScreen._toggleFavorite` already uses -- just recorded
  /// into [_favoriteOverrides] instead of replacing an immutable post field.
  Future<void> _toggleFavorite(AppLocalizations l10n) async {
    final post = _currentPost;
    final wasFavorited = _isFavorited(post);
    bool succeeded;
    try {
      if (wasFavorited) {
        await widget.repository.queueFavoriteRemove(post.id);
      } else {
        await widget.repository.queueFavoriteAdd(post.id);
      }
      final stats = await widget.repository.processQueue();
      succeeded = stats.actionsFailed == 0;
    } catch (_) {
      succeeded = false;
    }
    if (!mounted) {
      return;
    }
    if (!succeeded) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.postDetailActionFailed)));
      return;
    }
    setState(() => _favoriteOverrides[post.id] = !wasFavorited);
  }

  /// e621 only (no vote API on Inkbunny, same gate the upvote button itself
  /// uses). Always queues an upvote (score 1), same as
  /// `PostDetailScreen._vote`'s own upvote button -- toggling an existing
  /// upvote back off is the repository/native layer's own behavior, not
  /// something decided client-side.
  Future<void> _toggleUpvote(AppLocalizations l10n) async {
    final post = _currentPost;
    final wasUpvoted = _voteFor(post) == 1;
    bool succeeded;
    try {
      await widget.repository.queueVote(post.id, 1);
      final stats = await widget.repository.processQueue();
      succeeded = stats.actionsFailed == 0;
    } catch (_) {
      succeeded = false;
    }
    if (!mounted) {
      return;
    }
    if (!succeeded) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.postDetailActionFailed)));
      return;
    }
    setState(() => _voteOverrides[post.id] = wasUpvoted ? 0 : 1);
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _goNext();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _goPrevious();
    } else if (event.logicalKey == LogicalKeyboardKey.space) {
      _togglePause();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final post = _currentPost;
    final isFavorited = _isFavorited(post);
    final isUpvoted = _voteFor(post) == 1;
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
            Center(child: PostMediaPage(key: ValueKey(post.id), post: post, localFilePath: widget.localFilePaths[post.id])),
            Row(
              children: [
                Expanded(flex: 2, child: GestureDetector(key: const Key('slideshowPrevZone'), behavior: HitTestBehavior.translucent, onTap: _goPrevious)),
                // Narrower middle zone (M78) -- pauses/resumes autoplay;
                // the wider flanks either side stay prev/next, same as
                // before, so this doesn't eat into their own hit area much.
                Expanded(flex: 1, child: GestureDetector(key: const Key('slideshowPauseZone'), behavior: HitTestBehavior.translucent, onTap: _togglePause)),
                Expanded(flex: 2, child: GestureDetector(key: const Key('slideshowNextZone'), behavior: HitTestBehavior.translucent, onTap: _goNext)),
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
            // A bottom bar (M78), not overlapping the image itself -- the
            // same middle-tap-zone Row above already covers this strip too,
            // but these buttons sit on top of it in the Stack, so they
            // still receive their own taps first.
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                top: false,
                child: ColoredBox(
                  color: Colors.black45,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: Icon(isFavorited ? Icons.favorite : Icons.favorite_border, color: isFavorited ? Colors.red : Colors.white),
                        tooltip: isFavorited ? l10n.postDetailFavoriteRemoveTooltip : l10n.postDetailFavoriteAddTooltip,
                        onPressed: () => _toggleFavorite(l10n),
                      ),
                      if (post.site == BunnySite.e621)
                        IconButton(
                          icon: Icon(Icons.arrow_upward, color: isUpvoted ? Colors.green : Colors.white),
                          tooltip: l10n.postDetailUpvoteTooltip,
                          onPressed: () => _toggleUpvote(l10n),
                        ),
                      IconButton(
                        icon: Icon(_paused ? Icons.play_arrow : Icons.pause, color: Colors.white),
                        tooltip: _paused ? l10n.slideshowResumeTooltip : l10n.slideshowPauseTooltip,
                        onPressed: _togglePause,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
