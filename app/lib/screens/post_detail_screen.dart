import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../services/download_manager.dart';
import '../settings/display_settings_store.dart';
import '../settings/download_settings_store.dart';
import '../settings/sync_settings_store.dart';
import '../util/image_headers.dart';
import '../util/media_type.dart';
import '../util/responsive.dart';
import '../widgets/rating_badge.dart';
import 'full_screen_post_viewer_screen.dart';
import 'tag_browse_screen.dart';

/// Tags are grouped by category (M8.5.3) and then sorted into this fixed
/// order (M9.6.5) rather than whatever order they happened to arrive in --
/// any category not in this list (including `null`, Inkbunny's single
/// uncategorized bucket) is grouped last instead of being dropped.
const _tagCategoryOrder = ['artist', 'character', 'copyright', 'species', 'general', 'meta'];

const _imageExtensions = {'jpg', 'jpeg', 'png', 'gif', 'webp'};

bool _isImage(BunnyPost post) => post.fileExt != null && _imageExtensions.contains(post.fileExt!.toLowerCase());

/// Rebuilds [post] with the given fields adjusted -- used to optimistically
/// reflect a favorite/vote action (M8.5.14) in the UI immediately, without
/// waiting for a resync. No `copyWith` exists on [BunnyPost] (nothing else
/// needed one), so this just lists every field once, same manual-
/// reconstruction approach `FakeBunnyRepository._markedSeen` already uses.
BunnyPost _applyOptimisticUpdate(BunnyPost post, {bool? isFavorited, int favCountDelta = 0, int scoreDelta = 0, int scoreUpDelta = 0, int scoreDownDelta = 0, int? userVote}) => BunnyPost(
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
);

/// Full read-only metadata + media viewer for a single post (M8.4, redesigned
/// in M8.5.8 to surface categorized tags, sources, and e621 pool/parent/
/// child navigation; M8.5.14 added favorite/vote actions). No comment
/// actions yet -- that's M9's scope. Marks the post seen once, on open, same
/// as tapping it used to in `PostGridScreen` before this screen existed.
class PostDetailScreen extends StatefulWidget {
  final BunnyPost post;
  final BunnyRepository repository;
  final DisplaySettingsStore displaySettingsStore;
  final SyncSettingsStore syncSettingsStore;
  final DownloadSettingsStore downloadSettingsStore;

  /// Pure logic, no required construction dependencies (unlike the settings
  /// stores above, which are threaded from `main.dart` for a single source of
  /// truth) -- defaults to a real instance, overridden in widget tests with a
  /// fake HTTP client via [DownloadManager.client].
  final DownloadManager downloadManager;

  /// The post list this post was opened from (e.g. a grid's currently loaded
  /// posts), used to seed [FullScreenPostViewerScreen]'s swipeable gallery
  /// when the media is tapped (M8.5.9) -- filtered down to image posts only,
  /// since videos keep using the in-place player here. `null` (the default,
  /// used when opening a post standalone, e.g. via a parent/child/pool chip)
  /// falls back to a single-post gallery of just [post].
  final List<BunnyPost>? siblingPosts;

  const PostDetailScreen({
    super.key,
    required this.post,
    required this.repository,
    required this.displaySettingsStore,
    required this.syncSettingsStore,
    required this.downloadSettingsStore,
    this.downloadManager = const DownloadManager(),
    this.siblingPosts,
  });

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

  /// Not `late final` like the futures above -- posting a new comment
  /// reassigns this to a fresh fetch so the new comment shows up without a
  /// full screen reload.
  Future<List<BunnyComment>>? _commentsFuture;
  final _commentController = TextEditingController();
  bool _commentAnonymous = false;
  bool _postingComment = false;

  /// Reassigned after a successful download so the button's filled/checkmark
  /// state (M9.4) updates without a full screen reload -- same "not late
  /// final" reasoning as [_commentsFuture].
  late Future<List<BunnyDownload>> _downloadsFuture;
  bool _downloading = false;

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
    widget.repository.markPostSeen(widget.post.id);

    _tagsFuture = widget.repository.getPostTagsByCategory(widget.post.id);
    _sourcesFuture = widget.repository.getPostSources(widget.post.id);
    _downloadsFuture = widget.repository.listDownloadsForPost(widget.post.id);
    if (widget.post.site == BunnySite.e621) {
      _relationshipsFuture = widget.repository.getPostRelationships(widget.post.id);
      _poolIdsFuture = widget.repository.getPostPoolIds(widget.post.id);
      _commentsFuture = widget.repository.getPostComments(widget.post.id);
    }

    final ext = widget.post.fileExt?.toLowerCase();
    final url = widget.post.fileUrl;
    if (isVideoExt(ext) && url != null) {
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
    _commentController.dispose();
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

  Future<void> _downloadFile(AppLocalizations l10n) async {
    setState(() => _downloading = true);
    final folder = await widget.downloadSettingsStore.loadDestinationFolder();
    if (folder == null) {
      if (!mounted) {
        return;
      }
      setState(() => _downloading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.postDetailDownloadFailed)));
      return;
    }
    final autoFavorite = await widget.downloadSettingsStore.loadAutoFavoriteOnDownload();
    final result = await widget.downloadManager.downloadPost(_post, widget.repository, folder, autoFavorite: autoFavorite);
    final downloaded = result.outcome == DownloadOutcome.verified || result.outcome == DownloadOutcome.checksumMismatch;
    if (autoFavorite && downloaded) {
      await widget.repository.processQueue();
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _downloading = false;
      if (downloaded) {
        _downloadsFuture = widget.repository.listDownloadsForPost(_post.id);
      }
    });
    final message = switch (result.outcome) {
      DownloadOutcome.verified => l10n.postDetailDownloadVerified,
      DownloadOutcome.checksumMismatch => l10n.postDetailDownloadMismatch,
      DownloadOutcome.noFileUrl || DownloadOutcome.failed => l10n.postDetailDownloadFailed,
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _downloadButton(AppLocalizations l10n) {
    final canDownload = _post.fileUrl != null;
    return FutureBuilder<List<BunnyDownload>>(
      future: _downloadsFuture,
      builder: (context, snapshot) {
        final alreadyDownloaded = (snapshot.data ?? const []).isNotEmpty;
        return IconButton(
          icon: _downloading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(alreadyDownloaded ? Icons.download_done : Icons.download),
          tooltip: l10n.postDetailDownloadTooltip,
          onPressed: canDownload && !_downloading ? () => _downloadFile(l10n) : null,
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

  /// The thick author/rating/stats bar (M9.6.5) replacing the old bare
  /// favorite/vote `IconButton` row -- a tinted `Container` directly under
  /// the title acting as a bold visual separator, with the artist name on
  /// its own line and [RatingBadge] + the three stat actions + the download
  /// button all on the line below.
  Widget _infoBar(AppLocalizations l10n) {
    final post = _post;
    final hasArtist = post.artist != null && post.artist!.isNotEmpty;
    // Inkbunny has no vote API at all (unlike favorites, which M2.2's
    // unofficial route covers for both sites) -- greyed out rather than
    // hidden or silently failing, same principle the roadmap already states
    // for comments.
    final votingEnabled = post.site != BunnySite.inkbunny;
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
              _statAction(
                icon: Icons.arrow_upward,
                count: post.scoreUp,
                tooltip: l10n.postDetailUpvoteTooltip,
                onPressed: votingEnabled ? () => _vote(l10n, 1) : null,
                color: post.userVote == 1 ? Colors.green : null,
              ),
              _statAction(
                icon: Icons.arrow_downward,
                count: post.scoreDown,
                tooltip: l10n.postDetailDownvoteTooltip,
                onPressed: votingEnabled ? () => _vote(l10n, -1) : null,
                color: post.userVote == -1 ? Colors.orange : null,
              ),
              _statAction(
                icon: post.isFavorited ? Icons.favorite : Icons.favorite_border,
                count: post.favCount,
                tooltip: post.isFavorited ? l10n.postDetailFavoriteRemoveTooltip : l10n.postDetailFavoriteAddTooltip,
                onPressed: () => _toggleFavorite(l10n),
                color: post.isFavorited ? Colors.red : null,
              ),
              const Spacer(),
              _downloadButton(l10n),
            ],
          ),
        ],
      ),
    );
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
    if (isVideoExt(ext)) {
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
      MaterialPageRoute(
        builder: (context) => TagBrowseScreen(
          site: widget.post.site,
          query: query,
          repository: widget.repository,
          displaySettingsStore: widget.displaySettingsStore,
          syncSettingsStore: widget.syncSettingsStore,
          downloadSettingsStore: widget.downloadSettingsStore,
        ),
      ),
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
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PostDetailScreen(
            post: post,
            repository: widget.repository,
            displaySettingsStore: widget.displaySettingsStore,
            syncSettingsStore: widget.syncSettingsStore,
            downloadSettingsStore: widget.downloadSettingsStore,
          ),
        ),
      );
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
          syncSettingsStore: widget.syncSettingsStore,
          downloadSettingsStore: widget.downloadSettingsStore,
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
                if (post.description != null && post.description!.isNotEmpty) ...[const Divider(), Text(post.description!)],
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
