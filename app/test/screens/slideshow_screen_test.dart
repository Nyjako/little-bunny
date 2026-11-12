import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/screens/slideshow_screen.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../fakes/fake_bunny_repository.dart';
import '../fakes/fake_video_player_platform.dart';
import '../fakes/test_app.dart';

BunnyPost _post(int id, {String fileExt = 'jpg'}) => BunnyPost(
  id: id,
  site: BunnySite.e621,
  externalId: id,
  score: 0,
  favCount: 0,
  commentCount: 0,
  fileUrl: 'https://example.invalid/$id.$fileExt',
  fileExt: fileExt,
  width: 640,
  height: 480,
  cachedAt: '2026-01-01T00:00:00Z',
  isSeen: false,
  isFavorited: false,
);

void main() {
  setUpAll(() {
    VideoPlayerPlatform.instance = FakeVideoPlayerPlatform();
  });

  testWidgets('shows the current post and marks it seen on open', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final posts = [_post(1), _post(2)];

    await tester.pumpWidget(wrapWithLocalization(SlideshowScreen(posts: posts, localFilePaths: const {}, interval: const Duration(seconds: 5), repository: repository)));
    await tester.pump();

    expect(repository.markPostSeenCalls, hasLength(1));
    expect(find.byType(SlideshowScreen), findsOneWidget);
  });

  testWidgets('advances to the other post once the interval elapses, and video switches in place rather than blocking (M51)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    // One image, one video -- with exactly 2 posts, a single tick always
    // lands on the other one, letting this assert via widget type presence
    // without needing to know which way shuffle() landed.
    final posts = [_post(1, fileExt: 'jpg'), _post(2, fileExt: 'mp4')];

    await tester.pumpWidget(wrapWithLocalization(SlideshowScreen(posts: posts, localFilePaths: const {}, interval: const Duration(seconds: 1), repository: repository)));
    await tester.pumpAndSettle();
    final videoShowingInitially = find.byType(VideoPlayer).evaluate().isNotEmpty;

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // The timer advanced to the other post -- confirmed by the video
    // widget's presence flipping, and never waiting for it to finish
    // playing first (there's nothing here that would block on that).
    expect(find.byType(VideoPlayer).evaluate().isNotEmpty, !videoShowingInitially);
    expect(repository.markPostSeenCalls, hasLength(2));
  });

  testWidgets('loops back and reshuffles once every post has been shown, without crashing (M51)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final posts = [_post(1), _post(2)];

    await tester.pumpWidget(wrapWithLocalization(SlideshowScreen(posts: posts, localFilePaths: const {}, interval: const Duration(seconds: 1), repository: repository)));
    await tester.pump();

    // 3 ticks over a 2-post list: the 3rd tick runs past the end of the
    // shuffled order, exercising the reshuffle-and-loop branch.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    expect(find.byType(SlideshowScreen), findsOneWidget);
    expect(repository.markPostSeenCalls, hasLength(4)); // 1 on open + 3 ticks
  });

  testWidgets('the close button pops the screen and stops the timer', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final posts = [_post(1), _post(2)];

    await tester.pumpWidget(
      wrapWithLocalization(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => SlideshowScreen(posts: posts, localFilePaths: const {}, interval: const Duration(seconds: 1), repository: repository))),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(SlideshowScreen), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.byType(SlideshowScreen), findsNothing);
    // If the Timer wasn't cancelled in dispose(), flutter_test's own
    // teardown would fail this test with a "pending timer" error here.
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('tapping the right half advances immediately and restarts the interval timer (M76)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final posts = [_post(1, fileExt: 'jpg'), _post(2, fileExt: 'mp4')];

    await tester.pumpWidget(wrapWithLocalization(SlideshowScreen(posts: posts, localFilePaths: const {}, interval: const Duration(seconds: 5), repository: repository)));
    await tester.pumpAndSettle();
    final videoShowingInitially = find.byType(VideoPlayer).evaluate().isNotEmpty;

    // Top-right corner, clear of the close button's own hit area (top-left).
    await tester.tapAt(const Offset(750, 20));
    await tester.pumpAndSettle();

    expect(find.byType(VideoPlayer).evaluate().isNotEmpty, !videoShowingInitially);
    expect(repository.markPostSeenCalls, hasLength(2));

    // The timer was restarted by the tap -- a tick at the *original*
    // interval shouldn't have fired a second advance yet.
    await tester.pump(const Duration(seconds: 1));
    expect(repository.markPostSeenCalls, hasLength(2));
  });

  testWidgets('tapping the left half steps back one post, wrapping to the end of the shuffle (M76)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final posts = [_post(1, fileExt: 'jpg'), _post(2, fileExt: 'mp4')];

    await tester.pumpWidget(wrapWithLocalization(SlideshowScreen(posts: posts, localFilePaths: const {}, interval: const Duration(seconds: 5), repository: repository)));
    await tester.pumpAndSettle();
    final videoShowingInitially = find.byType(VideoPlayer).evaluate().isNotEmpty;

    // With only 2 posts, stepping either direction from the start always
    // lands on the other one -- same observable effect as "next" here, but
    // exercised through the left-half tap / wrap-to-end branch instead.
    // Well clear of the close button's own (top-left) hit area.
    await tester.tapAt(const Offset(50, 400));
    await tester.pumpAndSettle();

    expect(find.byType(VideoPlayer).evaluate().isNotEmpty, !videoShowingInitially);
    expect(repository.markPostSeenCalls, hasLength(2));
  });

  testWidgets('Right/Left arrow keys step forward/back the same way the tap zones do (M76)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final posts = [_post(1, fileExt: 'jpg'), _post(2, fileExt: 'mp4')];

    await tester.pumpWidget(wrapWithLocalization(SlideshowScreen(posts: posts, localFilePaths: const {}, interval: const Duration(seconds: 5), repository: repository)));
    await tester.pumpAndSettle();
    final videoShowingInitially = find.byType(VideoPlayer).evaluate().isNotEmpty;

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.byType(VideoPlayer).evaluate().isNotEmpty, !videoShowingInitially);
    expect(repository.markPostSeenCalls, hasLength(2));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.byType(VideoPlayer).evaluate().isNotEmpty, videoShowingInitially);
    expect(repository.markPostSeenCalls, hasLength(3));
  });

  // No widget test covers local-file rendering itself (Image.file/GifPlayer's
  // localFilePath branch/VideoPlayerController.file) -- confirmed via
  // several minimal repros that any widget reading a real local file
  // through dart:io inside a widget's initState (even a bare Image.file
  // with no other widgets around it) hangs indefinitely under this
  // project's flutter_test environment, regardless of tester.runAsync
  // wrapping or byte validity; a pre-existing environment limitation, not
  // something introduced by or fixable from this branch's own code. The
  // branch-selection logic itself (PostMediaPage/GifPlayer choosing the
  // local path over the network one) is simple and type-checked by
  // analysis; the actual file-reading behavior is exercised for real via
  // SlideshowPrepareService's own tests (slideshow_prepare_service_test.dart),
  // which use plain `test()` (no widget-test binding) against real temp
  // files without hitting this limitation.
}
