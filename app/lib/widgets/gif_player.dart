import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'download_progress_indicator.dart';

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

  /// Injectable, same reasoning as [DownloadManager]/[HttpBunnyRepository]'s
  /// own `client:` parameters -- lets a test substitute a cache manager that
  /// never touches the network, rather than always going through the real
  /// [DefaultCacheManager] singleton.
  final BaseCacheManager cacheManager;

  GifPlayer({super.key, required this.imageUrl, this.httpHeaders, this.fit = BoxFit.contain, BaseCacheManager? cacheManager}) : cacheManager = cacheManager ?? DefaultCacheManager();

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
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
