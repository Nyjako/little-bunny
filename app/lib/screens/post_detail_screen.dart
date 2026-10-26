import 'package:cached_network_image/cached_network_image.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../services/download_manager.dart';
import '../services/download_queue_service.dart';
import '../settings/display_settings_store.dart';
import '../settings/download_settings_store.dart';
import '../util/image_headers.dart';
import '../util/media_type.dart';
import '../util/mouse_drag_scroll_behavior.dart';
import '../util/post_navigation.dart';
import '../util/responsive.dart';
import '../widgets/download_progress_indicator.dart';
import '../widgets/gif_player.dart';
import '../widgets/rating_badge.dart';
import '../widgets/rich_markup_text.dart';
import 'create_search_screen.dart';
import 'full_screen_post_viewer_screen.dart';
import 'tag_browse_screen.dart';
import 'wiki_page_screen.dart';

/// Tags are grouped by category (M8.5.3) and then sorted into this fixed
/// order (M9.6.5) rather than whatever order they happened to arrive in --
/// any category not in this list (including `null`, Inkbunny's single
/// uncategorized bucket) is grouped last instead of being dropped.
const _tagCategoryOrder = ['artist', 'character', 'copyright', 'species', 'general', 'meta'];

/// The tag long-press context menu's options (M52).
enum _TagMenuAction { search, addToSearches, addToBlacklist, showWiki, copy }

const _imageExtensions = {'jpg', 'jpeg', 'png', 'gif', 'webp'};

bool _isImage(BunnyPost post) => post.fileExt != null && _imageExtensions.contains(post.fileExt!.toLowerCase());

/// Rebuilds [post] with the given fields adjusted -- used to optimistically
/// reflect a favorite/vote action (M8.5.14) in the UI immediately, without
/// waiting for a resync. No `copyWith` exists on [BunnyPost] (nothing else
/// needed one), so this just lists every field once, same manual-
/// reconstruction approach `FakeBunnyRepository._markedSeen` already uses.
BunnyPost _applyOptimisticUpdate(BunnyPost post, {bool? isFavorited, int favCountDelta = 0, int scoreDelta = 0, int scoreUpDelta = 0, int scoreDownDelta = 0, int? userVote, int? favoriteStars}) => BunnyPost(
  id: post.id,
  site: post.site,
  externalId: post.externalId,
  artist: post.artist,
  title: post.title,
  description: post.description,
  rating: post.rating,
  score: post.score + scoreDelta,
  scoreUp: post.scoreUp + scoreUpDelta,
  scoreDown: post.scoreDown + scoreDownDelta,
  favCount: post.favCount + favCountDelta,
  commentCount: post.commentCount,
  fileUrl: post.fileUrl,
  fileExt: post.fileExt,
  fileMd5: post.fileMd5,
  previewUrl: post.previewUrl,
  width: post.width,
  height: post.height,
  createdAtSite: post.createdAtSite,
  cachedAt: post.cachedAt,
  isSeen: post.isSeen,
  isFavorited: isFavorited ?? post.isFavorited,
  sampleUrl: post.sampleUrl,
  userVote: userVote ?? post.userVote,
  favoriteStars: favoriteStars ?? post.favoriteStars,
);

/// Full read-only metadata + media viewer for a single post (M8.4, redesigned
/// in M8.5.8 to surface categorized tags, sources, and e621 pool/parent/
/// child navigation; M8.5.14 added favorite/vote actions). No comment
/// actions yet -- that's M9's scope.
///
/// A thin shell (M22): the actual per-post content lives in [_PostDetailPage]
/// below, wrapped in a [PageView] here so swiping/dragging/arrow-keys moves
/// between posts in [siblingPosts] without leaving this screen, the same way
/// [FullScreenPostViewerScreen] already does for images (M8.5.9).
class PostDetailScreen extends StatefulWidget {
  final BunnyPost post;
  final BunnyRepository repository;
  final DisplaySettingsStore displaySettingsStore;
  final DownloadSettingsStore downloadSettingsStore;

  /// Pure logic, no required construction dependencies (unlike the settings
  /// stores above, which are threaded from `main.dart` for a single source of
  /// truth) -- defaults to a real instance, overridden in widget tests with a
  /// fake HTTP client via [DownloadManager.client].
  final DownloadManager downloadManager;

  final DownloadQueueService downloadQueueService;

  /// The post list this post was opened from (e.g. a grid's currently loaded
  /// posts) -- both the posts this screen itself pages through (M22) and,
  /// filtered down to image posts only, the sub-gallery [_PostDetailPage]
  /// seeds [FullScreenPostViewerScreen] with when the media is tapped
  /// (M8.5.9). `null` (the default, used when opening a post standalone, e.g.
  /// via a parent/child/pool chip) falls back to a single-post list of just
  /// [post] in both places.
  final List<BunnyPost>? siblingPosts;

  const PostDetailScreen({
    super.key,
    required this.post,
    required this.repository,
    required this.displaySettingsStore,
    required this.downloadSettingsStore,
    required this.downloadQueueService,
    this.downloadManager = const DownloadManager(),
    this.siblingPosts,
  });

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  late final List<BunnyPost> _posts;
  late final int _initialIndex;
  late final PageController _pageController;

  /// How many images on each side of the current page to [_preloadAround] --
  /// loaded async (settings live in SharedPreferences) so it starts at the
  /// settings' own default (3) and updates once the real saved value
  /// arrives, rather than blocking the first frame on it.
  int _preloadCount = 3;

  @override
  void initState() {
    super.initState();
    _posts = widget.siblingPosts ?? [widget.post];
    final index = _posts.indexWhere((p) => p.id == widget.post.id);
    _initialIndex = index == -1 ? 0 : index;
    _pageController = PageController(initialPage: _initialIndex);
    // onPageChanged (below) never fires for the page a PageView starts on --
    // mirrors FullScreenPostViewerScreen's own mark-seen-on-page-change
    // timing (only when a page actually becomes active, never just because
    // PageView pre-built it as the next/previous page).
    _markSeenWithRetry(_posts[_initialIndex].id);
    _loadPreloadCountThenPreload();
    // M47: keeps the screen from sleeping mid-session while looking at a
    // post (and while swiping through siblingPosts) -- disabled again in
    // dispose() once this screen is actually left, not just backgrounded by
    // e.g. the fullscreen viewer being pushed on top of it.
    WakelockPlus.enable();
  }

  /// [precacheImage] needs a [BuildContext] -- by the time this resolves
  /// (SharedPreferences is async), the first frame has already built, so
  /// `context` is valid, same reasoning as every other post-initState async
  /// load on this screen.
  Future<void> _loadPreloadCountThenPreload() async {
    final count = await widget.displaySettingsStore.loadImagePreloadCount();
    if (!mounted) {
      return;
    }
    setState(() => _preloadCount = count);
    _preloadAround(_initialIndex);
  }

  /// Precaches up to [_preloadCount] images on each side of [index] (image
  /// posts only -- video posts stream rather than precache) so swiping
  /// either direction shows an already-decoded image instead of a spinner.
  void _preloadAround(int index) {
    for (var offset = 1; offset <= _preloadCount; offset++) {
      _preloadAt(index - offset);
      _preloadAt(index + offset);
    }
  }

  void _preloadAt(int index) {
    if (index < 0 || index >= _posts.length) {
      return;
    }
    final post = _posts[index];
    if (!_isImage(post) || post.fileUrl == null) {
      return;
    }
    precacheImage(CachedNetworkImageProvider(post.fileUrl!, headers: imageHeadersFor(post.site)), context);
  }

  @override
  void dispose() {
    _pageController.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  /// Fire-and-forget by design (same as before this retry existed) --
  /// nothing here blocks swiping to the next post or navigating away. One
  /// retry covers a transient failure (e.g. this request racing a
  /// concurrently slow one on the server) without a full retry queue; a
  /// second failure is swallowed silently, same as the original contract --
  /// reopening the post tries again. Without this, a swiped-past post
  /// whose single markPostSeen call happened to fail stayed unseen
  /// indefinitely with no visible error and no way to notice.
  Future<void> _markSeenWithRetry(int postId) async {
    try {
      await widget.repository.markPostSeen(postId);
    } catch (_) {
      try {
        await widget.repository.markPostSeen(postId);
      } catch (_) {
        // Give up silently -- see this method's doc comment.
      }
    }
  }

  void _onPageChanged(int index) {
    _markSeenWithRetry(_posts[index].id);
    _preloadAround(index);
  }

  /// Keeps this screen's own [PageView] in sync with whatever post the user
  /// swiped to inside [FullScreenPostViewerScreen] -- called live on every
  /// page change there (see [_PostDetailPage.onFullScreenPostChanged]'s doc
  /// comment), not just once when fullscreen closes, so there's no visible
  /// snap-back regardless of how fullscreen is exited (close button, system
  /// back gesture, ...).
  void _jumpToPost(BunnyPost post) {
    final index = _posts.indexWhere((p) => p.id == post.id);
    if (index != -1) {
      _pageController.jumpToPage(index);
    }
  }

  void _goToDelta(int delta) {
    final current = _pageController.page?.round() ?? _initialIndex;
    final target = current + delta;
    if (target < 0 || target >= _posts.length) {
      return;
    }
    _pageController.animateToPage(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
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
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKey,
      child: ScrollConfiguration(
        behavior: const MouseDragScrollBehavior(),
        child: PageView.builder(
          controller: _pageController,
          itemCount: _posts.length,
          onPageChanged: _onPageChanged,
          itemBuilder: (context, index) => _PostDetailPage(
            key: ValueKey(_posts[index].id),
            post: _posts[index],
            repository: widget.repository,
            displaySettingsStore: widget.displaySettingsStore,
            downloadSettingsStore: widget.downloadSettingsStore,
            downloadManager: widget.downloadManager,
            downloadQueueService: widget.downloadQueueService,
            siblingPosts: widget.siblingPosts,
            onFullScreenPostChanged: _jumpToPost,
          ),
        ),
      ),
    );
  }
}

/// The actual single-post content [PostDetailScreen] above pages through --
/// every field/method here means exactly what it meant on the old
/// `PostDetailScreen` before M22's refactor split it in two.
class _PostDetailPage extends StatefulWidget {
  final BunnyPost post;
  final BunnyRepository repository;
  final DisplaySettingsStore displaySettingsStore;
  final DownloadSettingsStore downloadSettingsStore;
  final DownloadManager downloadManager;
  final DownloadQueueService downloadQueueService;
  final List<BunnyPost>? siblingPosts;

  /// Called live as the user swipes inside [FullScreenPostViewerScreen]
  /// (not just once on exit) so the outer [PostDetailScreen]'s own
  /// [PageView] already shows the right page the moment fullscreen is
  /// closed, instead of snapping back to whichever post this page was
  /// originally built for.
  final ValueChanged<BunnyPost>? onFullScreenPostChanged;

  const _PostDetailPage({
    super.key,
    required this.post,
    required this.repository,
    required this.displaySettingsStore,
    required this.downloadSettingsStore,
    required this.downloadManager,
    required this.downloadQueueService,
    this.siblingPosts,
    this.onFullScreenPostChanged,
  });

  @override
  State<_PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<_PostDetailPage> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  Future<void>? _videoInitFuture;

  late final Future<List<BunnyPostTag>> _tagsFuture;
  late final Future<List<String>> _sourcesFuture;
  Future<BunnyPostRelationships>? _relationshipsFuture;
  Future<List<int>>? _poolIdsFuture;

  /// Not `late final` like the futures above -- posting a new comment
  /// reassigns this to a fresh fetch so the new comment shows up without a
  /// full screen reload.
  Future<List<BunnyComment>>? _commentsFuture;
  final _commentController = TextEditingController();
  bool _commentAnonymous = false;
  bool _postingComment = false;

  /// Whether a file already sits at [DownloadManager.isDownloaded]'s
  /// deterministic local path -- a per-device filesystem fact (M42), not a
  /// server-tracked one (a download recorded from one device used to show
  /// as already-downloaded on every other device sharing the same server).
  /// Reassigned after a successful download so the button's filled/checkmark
  /// state (M9.4) updates without a full screen reload -- same "not late
  /// final" reasoning as [_commentsFuture].
  late Future<bool> _isDownloadedFuture;

  /// Mutable local copy of [widget.post], so favorite/vote taps can update
  /// the displayed score/favCount/isFavorited immediately (M8.5.14) without
  /// a round trip. Identity-ish fields (site/externalId/fileExt/...) never
  /// change via these actions, so every other method still reads straight
  /// from `widget.post`.
  late BunnyPost _post;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    // Marking this post seen is the outer PostDetailScreen's job now (M22) --
    // it does so on initial build and on every subsequent page change, never
    // here, since PageView can build this widget for a page it's only
    // pre-rendering ahead of time, before the user actually swipes to it.

    // _refreshedPost gates tags/sources (not downloads/relationships/pools/
    // comments -- those are either user-owned or e621-only, where sync
    // already returns full data) behind a fresh live fetch: a sync pass only
    // ever stores what the *search/listing* endpoint returned, which for
    // Inkbunny specifically omits tags, full file dimensions, and comment
    // count entirely (only present on a full per-submission fetch) -- the
    // detail page otherwise showed literally nothing for a Inkbunny post,
    // tags included. For e621 (whose search endpoint already returns
    // everything) this just keeps vote/favorite counts current, matching the
    // "update counts on view" ask directly.
    final refreshedPost = _refreshPost();
    _tagsFuture = refreshedPost.then((_) => widget.repository.getPostTagsByCategory(widget.post.id));
    _sourcesFuture = refreshedPost.then((_) => widget.repository.getPostSources(widget.post.id));
    _isDownloadedFuture = _checkIsDownloaded();
    if (widget.post.site == BunnySite.e621) {
      _relationshipsFuture = widget.repository.getPostRelationships(widget.post.id);
      _poolIdsFuture = widget.repository.getPostPoolIds(widget.post.id);
      _commentsFuture = widget.repository.getPostComments(widget.post.id);
    }

    _maybeInitVideo(widget.post);
  }

  /// Refetches this post live from its site and updates [_post] before
  /// [_tagsFuture]/[_sourcesFuture] (and, via [_maybeInitVideo], a
  /// not-yet-known-to-be-a-video post) load -- see the call site's doc
  /// comment for why. Best-effort: falls back to showing whatever was
  /// already cached if this fails (e.g. offline), same as every other
  /// network call on this page.
  Future<BunnyPost> _refreshPost() async {
    try {
      await widget.repository.fetchPost(widget.post.site, widget.post.externalId);
      final fresh = await widget.repository.getPost(widget.post.id);
      if (mounted) {
        setState(() => _post = fresh);
        _maybeInitVideo(fresh);
      }
      return fresh;
    } catch (_) {
      return widget.post;
    }
  }

  /// No-op if a video controller already exists (either this is the second
  /// call, from [_refreshPost] after [initState] already found a video via
  /// cached data, or [post] still isn't a video) -- [initState] calls this
  /// with the cached (possibly fileExt/fileUrl-less, for Inkbunny) post
  /// first, and [_refreshPost] calls it again once fresh data arrives, so a
  /// video that only becomes knowable post-refresh still gets a player.
  void _maybeInitVideo(BunnyPost post) {
    if (_videoController != null) {
      return;
    }
    final ext = post.fileExt?.toLowerCase();
    final url = post.fileUrl;
    if (!isVideoExt(ext) || url == null) {
      return;
    }
    final controller = VideoPlayerController.networkUrl(Uri.parse(url), httpHeaders: imageHeadersFor(post.site) ?? const {});
    // Muted by default -- setVolume takes effect on the controller's value
    // immediately (synchronously, before the first await inside it), so
    // this reaches the platform side once initialize() completes below
    // without a separate "apply volume after init" step.
    controller.setVolume(0);
    _videoController = controller;
    final aspectRatio = (post.width > 0 && post.height > 0) ? post.width / post.height : 16 / 9;
    _videoInitFuture = controller.initialize().then((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        // Pass the post-metadata aspect ratio rather than letting Chewie
        // fall back to the decoded video's own reported value -- fixes
        // stretching for sources whose reported aspect ratio is wrong,
        // mirroring the fix already applied to the full-screen image
        // viewer (M9.6.1) for the same class of bug.
        _chewieController = ChewieController(videoPlayerController: controller, aspectRatio: aspectRatio, autoPlay: true, looping: true, allowFullScreen: true, allowMuting: true);
      });
    });
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController?.dispose();
    _commentController.dispose();
    super.dispose();
  }

  // Previously applied the optimistic UI update unconditionally, even when
  // processQueue()'s own stats reported the action as failed (e.g. no
  // account configured, or a rejected request) -- the toggle looked like it
  // took effect for the rest of this screen's lifetime, but nothing was
  // ever actually persisted (bunny_core only updates the local favorites
  // mirror on a *successful* action), so reopening the post later showed the
  // real, unfavorited state. Checking actionsFailed here means a failed
  // action now surfaces an error instead of lying about what happened.
  Future<void> _toggleFavorite(AppLocalizations l10n) async {
    final wasFavorited = _post.isFavorited;
    bool succeeded;
    try {
      if (wasFavorited) {
        await widget.repository.queueFavoriteRemove(_post.id);
      } else {
        await widget.repository.queueFavoriteAdd(_post.id);
      }
      // Drains immediately rather than waiting for the next scheduled pass
      // (M5.3), so the action actually reaches the site right away.
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
    setState(() {
      _post = _applyOptimisticUpdate(_post, isFavorited: !wasFavorited, favCountDelta: wasFavorited ? -1 : 1);
    });
  }

  /// Inkbunny's favorite is a single 1-3 star tier (not e621's plain
  /// favorite/unfavorite toggle) -- tapping the already-selected tier's heart
  /// removes the favorite entirely, same as tapping [_toggleFavorite]'s heart
  /// a second time would; tapping any other heart re-favorites at that tier
  /// (Inkbunny's API only has "favorite at level N", not "change level", so
  /// this always goes through queueFavoriteAdd even when already favorited).
  Future<void> _setInkbunnyFavoriteStars(AppLocalizations l10n, int stars) async {
    final wasFavorited = _post.isFavorited;
    final removing = wasFavorited && _post.favoriteStars == stars;
    bool succeeded;
    try {
      if (removing) {
        await widget.repository.queueFavoriteRemove(_post.id);
      } else {
        await widget.repository.queueFavoriteAdd(_post.id, stars: stars);
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
    setState(() {
      _post = _applyOptimisticUpdate(
        _post,
        isFavorited: !removing,
        favCountDelta: removing ? -1 : (wasFavorited ? 0 : 1),
        favoriteStars: removing ? 0 : stars,
      );
    });
  }

  Future<void> _vote(AppLocalizations l10n, int score) async {
    bool succeeded;
    try {
      await widget.repository.queueVote(_post.id, score);
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
    setState(() {
      _post = _applyOptimisticUpdate(_post, scoreDelta: score, scoreUpDelta: score > 0 ? 1 : 0, scoreDownDelta: score < 0 ? 1 : 0, userVote: score);
    });
  }

  Future<bool> _checkIsDownloaded() async {
    final folder = await widget.downloadSettingsStore.loadDestinationFolder();
    if (folder == null) {
      return false;
    }
    return widget.downloadManager.isDownloaded(_post, folder);
  }

  /// Enqueues and returns immediately (M43) -- the actual fetch/write/
  /// checksum work now lives entirely inside [DownloadQueueService],
  /// reported through its notifier rather than this screen's own state.
  /// [_isDownloadedFuture] deliberately isn't refreshed here: there's no
  /// "download finished" callback to hook anymore by design (the whole
  /// point is this screen doesn't wait), so the download-done icon only
  /// updates the next time this screen is (re)opened, not live while
  /// staying on the same post's page -- an accepted, documented limitation.
  void _queueDownload(AppLocalizations l10n) {
    widget.downloadQueueService.enqueue(_post, widget.repository);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.postDetailDownloadQueued)));
  }

  Widget _downloadButton(AppLocalizations l10n) {
    final canDownload = _post.fileUrl != null;
    return FutureBuilder<bool>(
      future: _isDownloadedFuture,
      builder: (context, snapshot) {
        final alreadyDownloaded = snapshot.data ?? false;
        return IconButton(
          icon: Icon(alreadyDownloaded ? Icons.download_done : Icons.download),
          tooltip: l10n.postDetailDownloadTooltip,
          onPressed: canDownload ? () => _queueDownload(l10n) : null,
        );
      },
    );
  }

  /// One tappable icon+count group in [_infoBar] -- a bare `IconButton` has
  /// no room for a label, so each of upvote/downvote/favorite (M9.6.5) is a
  /// `TextButton.icon` instead, wrapped in its own `Tooltip` the same way
  /// `IconButton`'s own `tooltip` param already wraps it internally.
  Widget _statAction({required IconData icon, required int count, required String tooltip, required VoidCallback? onPressed, Color? color}) => Tooltip(
    message: tooltip,
    child: TextButton.icon(onPressed: onPressed, icon: Icon(icon, size: 18, color: onPressed != null ? color : null), label: Text('$count')),
  );

  /// Inkbunny's favorite is a single 1-3 heart tier, not e621's plain
  /// favorite/vote pair -- three small heart `IconButton`s, filled from the
  /// left up to [BunnyPost.favoriteStars] (classic star-rating-row look),
  /// each one tappable independently rather than one combined widget, so
  /// each heart's own tooltip can say exactly which tier tapping it selects.
  Widget _inkbunnyFavoriteHearts(AppLocalizations l10n) {
    final post = _post;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final tier in [1, 2, 3])
          Tooltip(
            message: post.isFavorited && post.favoriteStars == tier ? l10n.postDetailFavoriteStarsRemoveTooltip : l10n.postDetailFavoriteStarsTooltip(tier),
            child: IconButton(
              iconSize: 20,
              visualDensity: VisualDensity.compact,
              icon: Icon(tier <= post.favoriteStars ? Icons.favorite : Icons.favorite_border, color: tier <= post.favoriteStars ? Colors.red : null),
              onPressed: () => _setInkbunnyFavoriteStars(l10n, tier),
            ),
          ),
        Text('${post.favCount}'),
      ],
    );
  }

  /// The thick author/rating/stats bar (M9.6.5) replacing the old bare
  /// favorite/vote `IconButton` row -- a tinted `Container` directly under
  /// the title acting as a bold visual separator, with the artist name on
  /// its own line and [RatingBadge] + the three stat actions + the download
  /// button all on the line below.
  Widget _infoBar(AppLocalizations l10n) {
    final post = _post;
    final hasArtist = post.artist != null && post.artist!.isNotEmpty;
    final isInkbunny = post.site == BunnySite.inkbunny;
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: hasArtist ? () => _openTagBrowse(post.artist!) : null,
            child: Text(hasArtist ? post.artist! : l10n.postDetailUnknownValue, style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              RatingBadge(site: post.site, rating: post.rating),
              const SizedBox(width: 8),
              if (isInkbunny)
                _inkbunnyFavoriteHearts(l10n)
              else ...[
                _statAction(
                  icon: Icons.arrow_upward,
                  count: post.scoreUp,
                  tooltip: l10n.postDetailUpvoteTooltip,
                  onPressed: () => _vote(l10n, 1),
                  color: post.userVote == 1 ? Colors.green : null,
                ),
                _statAction(
                  icon: Icons.arrow_downward,
                  count: post.scoreDown,
                  tooltip: l10n.postDetailDownvoteTooltip,
                  onPressed: () => _vote(l10n, -1),
                  color: post.userVote == -1 ? Colors.orange : null,
                ),
                _statAction(
                  icon: post.isFavorited ? Icons.favorite : Icons.favorite_border,
                  count: post.favCount,
                  tooltip: post.isFavorited ? l10n.postDetailFavoriteRemoveTooltip : l10n.postDetailFavoriteAddTooltip,
                  onPressed: () => _toggleFavorite(l10n),
                  color: post.isFavorited ? Colors.red : null,
                ),
              ],
              const Spacer(),
              _downloadButton(l10n),
            ],
          ),
        ],
      ),
    );
  }

  /// Includes video posts too (M35) -- used to filter to images only, which
  /// meant swiping past a video while browsing fullscreen silently skipped
  /// over it instead of showing/playing it.
  void _openFullScreenViewer() {
    final posts = widget.siblingPosts ?? [widget.post];
    final index = posts.indexWhere((p) => p.id == widget.post.id);
    if (index == -1) {
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullScreenPostViewerScreen(
          posts: posts,
          initialIndex: index,
          repository: widget.repository,
          displaySettingsStore: widget.displaySettingsStore,
          onPageChanged: widget.onFullScreenPostChanged,
        ),
      ),
    );
  }

  Widget _buildMedia(AppLocalizations l10n) {
    final post = _post;
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
      // Image's own loadingBuilder (standard ImageStream/ImageChunkEvent
      // machinery), not CachedNetworkImage's progressIndicatorBuilder --
      // the latter switches CachedNetworkImage's internal rendering onto a
      // different, flutter_cache_manager-streaming-backed path that never
      // settles under `flutter_test` (confirmed: it hung even the simplest
      // tests in this screen's own test suite, unrelated to gifs at all).
      // This uses the exact same CachedNetworkImageProvider plain
      // CachedNetworkImage already resolves through, which is already
      // proven compatible with this test suite's existing pumpAndSettle
      // calls.
      final content = isGifExt(ext)
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
      return GestureDetector(key: const Key('postDetailImageTapTarget'), onTap: _openFullScreenViewer, child: bounded(content));
    }
    if (isVideoExt(ext)) {
      return FutureBuilder<void>(
        future: _videoInitFuture,
        builder: (context, snapshot) {
          final chewieController = _chewieController;
          if (snapshot.connectionState != ConnectionState.done || chewieController == null) {
            return bounded(const Center(child: CircularProgressIndicator()));
          }
          return bounded(Chewie(controller: chewieController));
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
      MaterialPageRoute(
        builder: (context) => TagBrowseScreen(
          site: widget.post.site,
          query: query,
          repository: widget.repository,
          displaySettingsStore: widget.displaySettingsStore,
          downloadSettingsStore: widget.downloadSettingsStore,
          downloadQueueService: widget.downloadQueueService,
        ),
      ),
    );
  }

  void _openAddToSearches(String tagName) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => CreateSearchScreen(repository: widget.repository, initialSite: widget.post.site, initialQuery: tagName)),
    );
  }

  Future<void> _addToBlacklist(AppLocalizations l10n, String tagName) async {
    await widget.repository.addBlacklistTag(widget.post.site, tagName);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.tagMenuAddedToBlacklist(tagName))));
  }

  void _openTagWiki(String tagName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WikiPageScreen(
          title: tagName,
          repository: widget.repository,
          displaySettingsStore: widget.displaySettingsStore,
          downloadSettingsStore: widget.downloadSettingsStore,
          downloadQueueService: widget.downloadQueueService,
        ),
      ),
    );
  }

  Future<void> _copyTagToClipboard(AppLocalizations l10n, String tagName) async {
    await Clipboard.setData(ClipboardData(text: tagName));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.tagMenuCopied(tagName))));
  }

  /// Long-pressing a tag chip (M52) opens this instead of immediately
  /// searching -- the other four actions don't make sense as a tap on the
  /// chip itself, so they live behind a long-press menu rather than a
  /// second visible control per chip.
  Future<void> _showTagMenu(AppLocalizations l10n, String tagName) async {
    final action = await showModalBottomSheet<_TagMenuAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.search), title: Text(l10n.tagMenuSearchLabel), onTap: () => Navigator.pop(context, _TagMenuAction.search)),
            ListTile(leading: const Icon(Icons.bookmark_add_outlined), title: Text(l10n.tagMenuAddToSearchesLabel), onTap: () => Navigator.pop(context, _TagMenuAction.addToSearches)),
            ListTile(leading: const Icon(Icons.block), title: Text(l10n.tagMenuAddToBlacklistLabel), onTap: () => Navigator.pop(context, _TagMenuAction.addToBlacklist)),
            ListTile(leading: const Icon(Icons.menu_book_outlined), title: Text(l10n.tagMenuShowWikiLabel), onTap: () => Navigator.pop(context, _TagMenuAction.showWiki)),
            ListTile(leading: const Icon(Icons.copy), title: Text(l10n.tagMenuCopyLabel), onTap: () => Navigator.pop(context, _TagMenuAction.copy)),
          ],
        ),
      ),
    );
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case _TagMenuAction.search:
        _openTagBrowse(tagName);
      case _TagMenuAction.addToSearches:
        _openAddToSearches(tagName);
      case _TagMenuAction.addToBlacklist:
        await _addToBlacklist(l10n, tagName);
      case _TagMenuAction.showWiki:
        _openTagWiki(tagName);
      case _TagMenuAction.copy:
        await _copyTagToClipboard(l10n, tagName);
    }
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
      final ordered = <MapEntry<String?, List<BunnyPostTag>>>[
        for (final category in _tagCategoryOrder)
          if (grouped[category] != null) MapEntry(category, grouped[category]!),
        for (final entry in grouped.entries)
          if (!_tagCategoryOrder.contains(entry.key)) entry,
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          for (final entry in ordered) ...[
            Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(entry.key == null ? l10n.postDetailTagsLabel : _titleCase(entry.key!), style: Theme.of(context).textTheme.titleSmall)),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: entry.value
                    .map((tag) => GestureDetector(onLongPress: () => _showTagMenu(l10n, tag.name), child: ActionChip(label: Text(tag.name), onPressed: () => _openTagBrowse(tag.name))))
                    .toList(),
              ),
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

  Future<void> _openExternalPost(AppLocalizations l10n, int externalId) => openExternalPost(
    context: context,
    l10n: l10n,
    repository: widget.repository,
    site: widget.post.site,
    externalId: externalId,
    displaySettingsStore: widget.displaySettingsStore,
    downloadSettingsStore: widget.downloadSettingsStore,
    downloadQueueService: widget.downloadQueueService,
  );

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

  // Opens a pool directly via TagBrowseScreen's existing stateless preview
  // (M9.6.3) instead of forcing a saved-search dialog first -- TagBrowseScreen
  // already offers its own "add to searches" action for anyone who wants to
  // save it afterward. The pool's own name is fetched best-effort to pre-fill
  // that action's label; a failure here just falls back to the bare
  // "pool:<id>" label CreateSearchScreen would otherwise mirror from the
  // query, so it's swallowed rather than surfaced as an error.
  Future<void> _openPool(AppLocalizations l10n, int poolId) async {
    String? label;
    try {
      final info = await widget.repository.fetchPool(poolId);
      if (info.name != null && info.name!.isNotEmpty) {
        label = info.name;
      }
    } catch (_) {
      // Fall back to no pre-filled label.
    }

    if (!mounted) {
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TagBrowseScreen(
          site: BunnySite.e621,
          query: 'pool:$poolId',
          repository: widget.repository,
          displaySettingsStore: widget.displaySettingsStore,
          downloadSettingsStore: widget.downloadSettingsStore,
          downloadQueueService: widget.downloadQueueService,
          initialLabel: label,
        ),
      ),
    );
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

  Future<void> _postComment(AppLocalizations l10n) async {
    final body = _commentController.text.trim();
    if (body.isEmpty) {
      return;
    }
    setState(() => _postingComment = true);
    try {
      await widget.repository.queueComment(widget.post.id, body, anonymous: _commentAnonymous);
      // Drains immediately, same reasoning as the favorite/vote actions
      // above, so the comment actually reaches e621 right away.
      await widget.repository.processQueue();
      _commentController.clear();
      if (!mounted) {
        return;
      }
      setState(() {
        _commentsFuture = widget.repository.getPostComments(widget.post.id);
        _postingComment = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _postingComment = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.postDetailCommentPostFailed)));
    }
  }

  Widget _commentsSection(AppLocalizations l10n) {
    final future = _commentsFuture;
    if (future == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(l10n.postDetailCommentsSectionLabel, style: Theme.of(context).textTheme.titleSmall)),
        FutureBuilder<List<BunnyComment>>(
          future: future,
          builder: (context, snapshot) {
            final comments = snapshot.data ?? const [];
            if (comments.isEmpty) {
              return Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(l10n.postDetailNoCommentsYet));
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: comments
                  .map(
                    (comment) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(comment.creatorName ?? l10n.postDetailUnknownValue, style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text(comment.body ?? ''),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
        TextField(controller: _commentController, enabled: !_postingComment, minLines: 1, maxLines: 4, decoration: InputDecoration(labelText: l10n.postDetailCommentFieldLabel)),
        Row(
          children: [
            Checkbox(value: _commentAnonymous, onChanged: _postingComment ? null : (value) => setState(() => _commentAnonymous = value ?? false)),
            Text(l10n.postDetailCommentAnonymousLabel),
            const Spacer(),
            FilledButton(
              onPressed: _postingComment ? null : () => _postComment(l10n),
              child: _postingComment ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text(l10n.postDetailCommentSubmit),
            ),
          ],
        ),
      ],
    );
  }

  /// The post id/comment-count/dimensions/created-date rows left over in
  /// "post details" once rating/votes/favorites moved into [_infoBar]
  /// (M9.6.5) -- used by [_tagsDetailsSourcesRegion] on both sides of its
  /// wide/narrow split.
  Widget _postDetailsColumn(AppLocalizations l10n) {
    final post = _post;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(onTap: () => _copyPostId(l10n), child: _metadataRow(l10n.postDetailIdLabel, '${widget.post.externalId}')),
        _metadataRow(l10n.postDetailCommentsLabel, '${post.commentCount}'),
        _metadataRow(l10n.postDetailDimensionsLabel, '${post.width}x${post.height}'),
        _metadataRow(l10n.postDetailCreatedLabel, post.createdAtSite ?? l10n.postDetailUnknownValue),
      ],
    );
  }

  /// Tags + post details + sources (M9.6.5): on wide windows, tags sit in
  /// their own column on the left with post details and sources stacked on
  /// the right; on narrow windows the same three pieces just stack top to
  /// bottom in that order. Shares [isWideScreen]'s breakpoint with M9.6.6's
  /// app-bar compactness rather than inventing a second one.
  Widget _tagsDetailsSourcesRegion(AppLocalizations l10n) {
    final tags = _tagsSection(l10n);
    final details = _postDetailsColumn(l10n);
    final sources = _sourcesSection(l10n);
    if (isWideScreen(context)) {
      return Row(
        key: const Key('wideTagsDetailsSourcesRow'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: tags),
          const SizedBox(width: 24),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [details, sources])),
        ],
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [tags, details, sources]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final post = _post;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.postDetailScreenTitle), toolbarHeight: isWideScreen(context) ? compactToolbarHeight : null),
      body: ListView(
        children: [
          _buildMedia(l10n),
          if (post.title != null && post.title!.isNotEmpty)
            Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: Text(post.title!, style: Theme.of(context).textTheme.titleLarge)),
          const SizedBox(height: 8),
          _infoBar(l10n),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _poolsSection(l10n),
                _relationshipsSection(l10n),
                if (post.description != null && post.description!.isNotEmpty) ...[
                  const Divider(),
                  RichMarkupText(
                    text: post.description!,
                    onOpenAuthor: _openTagBrowse,
                    onOpenWiki: _openTagWiki,
                    onOpenThumbnail: (postId) => _openExternalPost(l10n, postId),
                  ),
                ],
                const Divider(),
                _tagsDetailsSourcesRegion(l10n),
                _commentsSection(l10n),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
