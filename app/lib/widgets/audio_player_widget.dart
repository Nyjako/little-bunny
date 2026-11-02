import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

/// Self-contained play/pause + seek slider for a single audio file (M28
/// Phase 4, Inkbunny Music submissions) -- same "drop-in player" shape as
/// [GifPlayer]/`Chewie` elsewhere on this screen. [httpHeaders] exists for
/// the same reason `VideoPlayerController.networkUrl`'s own `httpHeaders`
/// does: Inkbunny's CDN 403s a bare request with no `User-Agent`/`Referer`
/// (see `imageHeadersFor`'s doc comment).
class AudioPlayerWidget extends StatefulWidget {
  final String url;
  final Map<String, String>? httpHeaders;

  const AudioPlayerWidget({super.key, required this.url, this.httpHeaders});

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  final _player = AudioPlayer();
  late final Future<Duration?> _loadFuture;

  @override
  void initState() {
    super.initState();
    _loadFuture = _player.setUrl(widget.url, headers: widget.httpHeaders);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _formatPosition(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Duration?>(
      future: _loadFuture,
      builder: (context, loadSnapshot) {
        if (loadSnapshot.connectionState != ConnectionState.done) {
          return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
        }
        return StreamBuilder<PlayerState>(
          stream: _player.playerStateStream,
          builder: (context, stateSnapshot) {
            final playing = stateSnapshot.data?.playing ?? false;
            return StreamBuilder<Duration>(
              stream: _player.positionStream,
              builder: (context, positionSnapshot) {
                final position = positionSnapshot.data ?? Duration.zero;
                final duration = _player.duration ?? Duration.zero;
                final durationMs = duration.inMilliseconds;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        key: const Key('audioPlayerPlayPauseButton'),
                        icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_fill),
                        iconSize: 36,
                        onPressed: playing ? _player.pause : _player.play,
                      ),
                      Expanded(
                        child: Slider(
                          value: durationMs > 0 ? position.inMilliseconds.clamp(0, durationMs).toDouble() : 0,
                          max: durationMs > 0 ? durationMs.toDouble() : 1,
                          onChanged: durationMs > 0 ? (value) => _player.seek(Duration(milliseconds: value.round())) : null,
                        ),
                      ),
                      Text('${_formatPosition(position)} / ${_formatPosition(duration)}'),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
