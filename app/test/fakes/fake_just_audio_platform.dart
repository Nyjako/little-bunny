import 'dart:async';

import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

/// A [JustAudioPlatform] that never touches a real decoder or network --
/// `flutter test` has no real platform channel implementation for
/// `just_audio`, same reasoning as `FakeVideoPlayerPlatform` for
/// `video_player`. Immediately reports a fixed duration on load and tracks
/// play/pause locally -- real decoding/network playback is out of scope for
/// a widget test.
class FakeJustAudioPlatform extends JustAudioPlatform {
  final List<FakeAudioPlayerPlatform> players = [];

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    final player = FakeAudioPlayerPlatform(request.id);
    players.add(player);
    return player;
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(DisposePlayerRequest request) async {
    players.removeWhere((p) => p.id == request.id);
    return DisposePlayerResponse();
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(DisposeAllPlayersRequest request) async {
    for (final player in players) {
      await player._eventController.close();
    }
    players.clear();
    return DisposeAllPlayersResponse();
  }
}

class FakeAudioPlayerPlatform extends AudioPlayerPlatform {
  FakeAudioPlayerPlatform(super.id);

  final _eventController = StreamController<PlaybackEventMessage>.broadcast();
  final Duration _duration = const Duration(minutes: 3);
  Duration _position = Duration.zero;

  /// Captures what the widget under test actually requested to load, so a
  /// test can assert headers/URL were passed through correctly -- there's
  /// no other observable side channel for this on a fake platform.
  String? lastLoadedUri;
  Map<String, String>? lastLoadedHeaders;

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _eventController.stream;

  void _emit() {
    _eventController.add(
      PlaybackEventMessage(
        processingState: ProcessingStateMessage.ready,
        updateTime: DateTime.now(),
        updatePosition: _position,
        bufferedPosition: _duration,
        duration: _duration,
        icyMetadata: null,
        currentIndex: 0,
        androidAudioSessionId: null,
      ),
    );
  }

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    _position = request.initialPosition ?? Duration.zero;
    // `AudioPlayer.setUrl`'s single source still arrives wrapped in the
    // same `ConcatenatingAudioSourceMessage` playlist container every
    // `AudioPlayer` always uses internally -- unwrap its first child to get
    // at the actual URI/headers.
    var source = request.audioSourceMessage;
    if (source is ConcatenatingAudioSourceMessage && source.children.isNotEmpty) {
      source = source.children.first;
    }
    if (source is UriAudioSourceMessage) {
      lastLoadedUri = source.uri;
      lastLoadedHeaders = source.headers;
    }
    _emit();
    return LoadResponse(duration: _duration);
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    _emit();
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    _emit();
    return PauseResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async => SetVolumeResponse();

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async => SetSpeedResponse();

  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async => SetPitchResponse();

  @override
  Future<SetSkipSilenceResponse> setSkipSilence(SetSkipSilenceRequest request) async => SetSkipSilenceResponse();

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async => SetLoopModeResponse();

  @override
  Future<SetShuffleModeResponse> setShuffleMode(SetShuffleModeRequest request) async => SetShuffleModeResponse();

  @override
  Future<SetShuffleOrderResponse> setShuffleOrder(SetShuffleOrderRequest request) async => SetShuffleOrderResponse();

  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(SetAndroidAudioAttributesRequest request) async => SetAndroidAudioAttributesResponse();

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    _position = request.position ?? Duration.zero;
    _emit();
    return SeekResponse();
  }

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    await _eventController.close();
    return DisposeResponse();
  }
}
