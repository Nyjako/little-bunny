import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../repository/bunny_models.dart';
import '../util/image_headers.dart';
import '../util/local_media_bytes.dart';
import '../util/media_type.dart';
import 'download_progress_indicator.dart';
import 'gif_player.dart';

/// A single post's media -- image/gif/video, picked by [BunnyPost.fileExt] --
/// with no viewer-specific wrapping (no PhotoView, no fullscreen chrome).
/// Extracted out of `FullScreenPostViewerScreen`'s own per-page builder
/// (M51) so `SlideshowScreen` can reuse the same image/gif/video branching
/// logic without that screen's pinch-zoom/swipe machinery, which a
/// timer-driven slideshow has no use for.
class PostMediaPage extends StatelessWidget {
  final BunnyPost post;

  /// When set (M51 v2 -- a slideshow playing back already-downloaded
  /// posts), reads [post]'s media straight off disk instead of fetching it
  /// over the network. [post.fileUrl] is otherwise unused in that case.
  final String? localFilePath;

  const PostMediaPage({super.key, required this.post, this.localFilePath});

  @override
  Widget build(BuildContext context) {
    final path = localFilePath;
    if (isVideoExt(post.fileExt) && (path != null || post.fileUrl != null)) {
      return _FullScreenVideoPage(post: post, localFilePath: path);
    }
    if (isGifExt(post.fileExt)) {
      return GifPlayer(imageUrl: post.fileUrl ?? '', localFilePath: path, httpHeaders: imageHeadersFor(post.site));
    }
    if (path != null) {
      // A `content://` SAF uri (Android) can't be opened as a plain `File`
      // -- see readLocalMediaBytes's own doc comment -- so it needs the
      // bytes-read-then-decode path below instead of Image.file's.
      return path.startsWith('content://') ? _LocalContentUriImage(path: path) : Image.file(File(path), fit: BoxFit.contain);
    }
    // Image's own loadingBuilder, not CachedNetworkImage's
    // progressIndicatorBuilder -- see PostDetailScreen's _buildMedia for why
    // (the latter never settles under `flutter_test`'s pumpAndSettle).
    return Image(
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
  }
}

/// Reads a `content://` SAF uri's bytes before handing them to [Image.memory]
/// -- [Image.file] (the plain-path branch above) can't open one directly.
class _LocalContentUriImage extends StatefulWidget {
  final String path;

  const _LocalContentUriImage({required this.path});

  @override
  State<_LocalContentUriImage> createState() => _LocalContentUriImageState();
}

class _LocalContentUriImageState extends State<_LocalContentUriImage> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await readLocalMediaBytes(widget.path);
      if (mounted) {
        setState(() => _bytes = bytes);
      }
    } catch (_) {
      // Best-effort, same tolerance as GifPlayer's own local-read failure.
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return bytes == null ? const Center(child: CircularProgressIndicator()) : Image.memory(bytes, fit: BoxFit.contain);
  }
}

/// Same player setup as `PostDetailScreen`'s own video branch (muted by
/// default, looping, post-metadata aspect ratio over the decoded video's
/// own, since that one can be wrong). A separate `StatefulWidget` so
/// [VideoPlayerController]/[ChewieController] init/dispose follows this
/// widget's own lifecycle (created when mounted, disposed when torn down --
/// in `FullScreenPostViewerScreen`'s gallery that's "scrolled far enough
/// away"; in `SlideshowScreen` that's "no longer the one post on screen").
class _FullScreenVideoPage extends StatefulWidget {
  final BunnyPost post;
  final String? localFilePath;

  const _FullScreenVideoPage({required this.post, this.localFilePath});

  @override
  State<_FullScreenVideoPage> createState() => _FullScreenVideoPageState();
}

class _FullScreenVideoPageState extends State<_FullScreenVideoPage> {
  late final VideoPlayerController _videoController;
  ChewieController? _chewieController;

  @override
  void initState() {
    super.initState();
    final path = widget.localFilePath;
    // A `content://` SAF uri (Android) needs VideoPlayerController's own
    // dedicated constructor -- .file's plain dart:io File can't open one
    // (see readLocalMediaBytes's doc comment for the same issue on the
    // image/gif side).
    final controller = path == null
        ? VideoPlayerController.networkUrl(Uri.parse(widget.post.fileUrl!), httpHeaders: imageHeadersFor(widget.post.site) ?? const {})
        : path.startsWith('content://')
        ? VideoPlayerController.contentUri(Uri.parse(path))
        : VideoPlayerController.file(File(path));
    controller.setVolume(0);
    _videoController = controller;
    final aspectRatio = (widget.post.width > 0 && widget.post.height > 0) ? widget.post.width / widget.post.height : 16 / 9;
    controller.initialize().then((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        // allowFullScreen: false (unlike PostDetailScreen's own video player)
        // -- already inside a caller-provided fullscreen surface, so
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
