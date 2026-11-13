import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;

import '../l10n/app_localizations.dart';
import '../util/byte_format.dart';
import '../util/local_media_bytes.dart';
import 'download_progress_indicator.dart';

/// Above this size, a GIF isn't decoded/animated automatically (M76).
/// `ui.instantiateImageCodec` has no streaming or partial-decode API -- it
/// needs the *entire* compressed file resident in memory before a single
/// frame can be decoded, and both e621 (100MB) and Inkbunny (300MB planned)
/// allow uploads well past the point where that's a real OOM risk,
/// especially on Android. 25MB is generous for the overwhelming majority of
/// real gifs (typically a few MB) while staying well clear of that danger
/// zone. Checked cheaply up front -- a local file stat, or a network HEAD
/// request's `Content-Length` -- before ever fetching the actual bytes;
/// see [_GifPlayerState._checkSizeThenLoad].
const int gifAutoPlayMaxBytes = 25 * 1024 * 1024;

/// Plays an animated GIF frame-by-frame (decoding via [ui.Codec] directly,
/// not the standard `Image`/`CachedNetworkImage` widgets, which drive GIF
/// animation internally with no hook for the app to observe which frame is
/// currently showing) so it can overlay a "N/X" frame counter (M49) -- the
/// user's stated reason is it's otherwise hard to tell where the loop
/// repeats. Shares [DownloadProgressIndicator] with `CachedNetworkImage`'s
/// own `progressIndicatorBuilder` (M48) for the pre-decode loading state,
/// using the same [DefaultCacheManager] download+cache layer
/// `CachedNetworkImage` itself uses, so a GIF already viewed once is served
/// from the same on-disk cache either way.
class GifPlayer extends StatefulWidget {
  final String imageUrl;
  final Map<String, String>? httpHeaders;
  final BoxFit fit;

  /// When set (M51 v2 -- a slideshow playing back already-downloaded
  /// posts), reads the GIF straight off disk instead of fetching/caching
  /// [imageUrl] over the network -- same [ui.instantiateImageCodec] decode
  /// step either way, just a different byte source.
  final String? localFilePath;

  /// The post/file's own already-fetched thumbnail (M76) -- shown in place
  /// of the real gif when it's over [gifAutoPlayMaxBytes], since that's a
  /// cheap, server-pregenerated static image rather than something that
  /// requires decoding the large file itself just to preview it. Null
  /// (no thumbnail available) falls back to a plain placeholder icon.
  final String? previewUrl;

  /// Injectable, same reasoning as [DownloadManager]/[HttpBunnyRepository]'s
  /// own `client:` parameters -- lets a test substitute a cache manager that
  /// never touches the network, rather than always going through the real
  /// [DefaultCacheManager] singleton. Unused when [localFilePath] is set.
  final BaseCacheManager cacheManager;

  /// Injectable, same reasoning as [cacheManager] above -- used only for
  /// the network size-check HEAD request, not the actual download (which
  /// still goes through [cacheManager]).
  final http.Client? client;

  /// Overridable only for tests -- a real caller always gets
  /// [gifAutoPlayMaxBytes], but exercising the over-the-limit path in a
  /// test without actually allocating a multi-megabyte fixture needs a
  /// much smaller threshold to compare a small test gif against.
  final int autoPlayMaxBytes;

  GifPlayer({
    super.key,
    required this.imageUrl,
    this.httpHeaders,
    this.fit = BoxFit.contain,
    this.localFilePath,
    this.previewUrl,
    BaseCacheManager? cacheManager,
    this.client,
    this.autoPlayMaxBytes = gifAutoPlayMaxBytes,
  }) : cacheManager = cacheManager ?? DefaultCacheManager();

  @override
  State<GifPlayer> createState() => _GifPlayerState();
}

class _GifPlayerState extends State<GifPlayer> {
  StreamSubscription<FileResponse>? _downloadSubscription;
  ui.Codec? _codec;
  ui.Image? _currentFrame;
  int _frameNumber = 0;
  int _totalFrames = 0;
  double? _downloadProgress;

  /// Set once a size check finds this gif over [gifAutoPlayMaxBytes] --
  /// [build] shows the too-large fallback instead of loading anything
  /// until [_playAnyway] is tapped. Null means either "still checking" or
  /// "under the limit, loading normally."
  int? _tooLargeSizeBytes;

  @override
  void initState() {
    super.initState();
    unawaited(_checkSizeThenLoad());
  }

  /// A cheap size check -- a local file stat, or a network HEAD request's
  /// `Content-Length` -- before committing to a full download+decode.
  /// Unknown size (stat/HEAD failed, or no `Content-Length` header) fails
  /// open: proceeds with the normal load exactly as before this existed,
  /// since refusing to play a gif just because its size couldn't be
  /// determined would be its own regression.
  Future<void> _checkSizeThenLoad() async {
    int? size;
    try {
      final localPath = widget.localFilePath;
      size = localPath != null ? await localMediaLength(localPath) : await _networkContentLength();
    } catch (_) {
      size = null;
    }
    if (!mounted) {
      return;
    }
    if (size != null && size > widget.autoPlayMaxBytes) {
      setState(() => _tooLargeSizeBytes = size);
      return;
    }
    _load();
  }

  Future<int?> _networkContentLength() async {
    final client = widget.client ?? http.Client();
    try {
      final response = await client.head(Uri.parse(widget.imageUrl), headers: widget.httpHeaders ?? const {});
      final header = response.headers['content-length'];
      return header == null ? null : int.tryParse(header);
    } finally {
      if (widget.client == null) {
        client.close();
      }
    }
  }

  /// The explicit, user-initiated override (M76) -- bypasses the size
  /// guard entirely and loads the real gif exactly as if it were under the
  /// limit, now that the user has seen the size and chosen to anyway.
  void _playAnyway() {
    setState(() => _tooLargeSizeBytes = null);
    _load();
  }

  void _load() {
    final localPath = widget.localFilePath;
    if (localPath != null) {
      _loadLocal(localPath);
      return;
    }
    _downloadSubscription = widget.cacheManager.getFileStream(widget.imageUrl, headers: widget.httpHeaders, withProgress: true).listen(
      (response) async {
        if (response is DownloadProgress) {
          if (mounted) {
            setState(() => _downloadProgress = response.progress);
          }
          return;
        }
        if (response is FileInfo) {
          final bytes = await response.file.readAsBytes();
          final codec = await ui.instantiateImageCodec(bytes);
          if (!mounted) {
            codec.dispose();
            return;
          }
          setState(() {
            _codec = codec;
            _totalFrames = codec.frameCount;
            _downloadProgress = null;
          });
          _playNextFrame();
        }
      },
      onError: (_) {
        // Best-effort -- a failed load just leaves the loading spinner
        // showing forever, same as CachedNetworkImage's own error state
        // isn't specially handled elsewhere on this screen.
      },
    );
  }

  Future<void> _loadLocal(String path) async {
    try {
      final bytes = await readLocalMediaBytes(path);
      final codec = await ui.instantiateImageCodec(bytes);
      if (!mounted) {
        codec.dispose();
        return;
      }
      setState(() {
        _codec = codec;
        _totalFrames = codec.frameCount;
        _downloadProgress = null;
      });
      _playNextFrame();
    } catch (_) {
      // Best-effort, same as the network branch's onError above.
    }
  }

  Future<void> _playNextFrame() async {
    final codec = _codec;
    if (codec == null || !mounted) {
      return;
    }
    final frame = await codec.getNextFrame();
    if (!mounted) {
      frame.image.dispose();
      return;
    }
    _frameNumber = _frameNumber % _totalFrames + 1;
    final previousFrame = _currentFrame;
    setState(() => _currentFrame = frame.image);
    previousFrame?.dispose();
    if (_totalFrames > 1) {
      Timer(frame.duration, _playNextFrame);
    }
  }

  @override
  void dispose() {
    _downloadSubscription?.cancel();
    _currentFrame?.dispose();
    _codec?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tooLargeSizeBytes = _tooLargeSizeBytes;
    if (tooLargeSizeBytes != null) {
      return _GifTooLargeFallback(previewUrl: widget.previewUrl, httpHeaders: widget.httpHeaders, sizeBytes: tooLargeSizeBytes, onPlayAnyway: _playAnyway);
    }
    final frame = _currentFrame;
    if (frame == null) {
      return DownloadProgressIndicator(progress: _downloadProgress);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        FittedBox(fit: widget.fit, child: SizedBox(width: frame.width.toDouble(), height: frame.height.toDouble(), child: RawImage(image: frame, fit: widget.fit))),
        if (_totalFrames > 1)
          Positioned(
            right: 8,
            bottom: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text('$_frameNumber/$_totalFrames', style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),
          ),
      ],
    );
  }
}

/// The over-[gifAutoPlayMaxBytes] fallback (M76): the post/file's own
/// already-fetched thumbnail (cheap, server-pregenerated, never the real
/// gif's bytes) if one was given, else a plain placeholder icon, with an
/// explicit "Play anyway" button naming the real size so the user decides
/// with full information instead of the app silently risking an OOM.
class _GifTooLargeFallback extends StatelessWidget {
  final String? previewUrl;
  final Map<String, String>? httpHeaders;
  final int sizeBytes;
  final VoidCallback onPlayAnyway;

  const _GifTooLargeFallback({required this.previewUrl, required this.httpHeaders, required this.sizeBytes, required this.onPlayAnyway});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final preview = previewUrl;
    return Stack(
      fit: StackFit.expand,
      children: [
        preview != null
            ? Image(image: CachedNetworkImageProvider(preview, headers: httpHeaders), fit: BoxFit.contain)
            : const ColoredBox(color: Colors.black12, child: Center(child: Icon(Icons.image_outlined, size: 48, color: Colors.white54))),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(l10n.gifPlayerTooLargeMessage(formatBytesCompact(sizeBytes)), style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(key: const Key('gifPlayAnywayButton'), onPressed: onPlayAnyway, icon: const Icon(Icons.play_arrow), label: Text(l10n.gifPlayerPlayAnywayButton)),
            ],
          ),
        ),
      ],
    );
  }
}
