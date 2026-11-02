import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:little_bunny/widgets/audio_player_widget.dart';

import '../fakes/fake_just_audio_platform.dart';

void main() {
  late FakeJustAudioPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeJustAudioPlatform();
    JustAudioPlatform.instance = fakePlatform;
  });

  // Position updates are driven by a repeating `Timer` while playing (same
  // `just_audio` internals, unrelated to this widget) -- like GifPlayer's own
  // animation loop, `pumpAndSettle` can never settle past it, so a single
  // bounded `pump()` is used instead.
  testWidgets('loads with the given url and headers', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: AudioPlayerWidget(url: 'https://example.invalid/track.mp3', httpHeaders: const {'User-Agent': 'test-agent'}))),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    final player = fakePlatform.players.single;
    // When headers are set, just_audio proxies through a local cleartext
    // HTTP server (see `AudioPlayer.setUrl`'s own doc comment) and forwards
    // the real headers there instead of sending the original URI straight
    // to the platform -- only the path survives unchanged.
    expect(player.lastLoadedUri, endsWith('/track.mp3'));
    expect(player.lastLoadedHeaders, const {'User-Agent': 'test-agent'});
  });

  testWidgets('tapping the play/pause button toggles playing', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: AudioPlayerWidget(url: 'https://example.invalid/track.mp3'))));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);

    // `play()`/`pause()` go through `AudioSession.instance` and other real
    // async plugin plumbing that only resolves correctly in a real zone --
    // same reason the initial load above needs `runAsync`, not just
    // `tester.tap()` + `pump()` directly.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('audioPlayerPlayPauseButton')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    expect(find.byIcon(Icons.pause_circle_filled), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('audioPlayerPlayPauseButton')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);
  });
}
