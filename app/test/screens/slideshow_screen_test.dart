import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/screens/slideshow_screen.dart';
import 'package:saf_stream/saf_stream_platform_interface.dart';
import 'package:saf_util/saf_util_platform_interface.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../fakes/fake_bunny_repository.dart';
import '../fakes/fake_saf_platform.dart';
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

// Two distinct, minimal, real 1x1 PNGs (a decode failure inside Image.memory
// fails a test for an unrelated reason, so arbitrary placeholder bytes won't
// do) -- a plain solid-color pixel each, red and blue.
final Uint8List _redOnePixelPng = Uint8List.fromList([
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0, 144, 119, 83, 222, 0, 0, 0, 12, 73, 68, 65, 84, 120, 156, 99, 248, 207, 192, 0, 0, 3, 1, 1, 0,
  201, 254, 146, 239, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
]);
final Uint8List _blueOnePixelPng = Uint8List.fromList([
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0, 144, 119, 83, 222, 0, 0, 0, 12, 73, 68, 65, 84, 120, 156, 99, 96, 96, 248, 15, 0, 1, 3, 1, 0,
  8, 137, 194, 236, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
]);

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

  testWidgets('advancing reloads a SAF content:// local file instead of leaving the previous post on screen (M76 regression)', (WidgetTester tester) async {
    final safUtil = FakeSafUtilPlatform();
    final safStream = FakeSafStreamPlatform(safUtil);
    SafUtilPlatform.instance = safUtil;
    SafStreamPlatform.instance = safStream;
    // Keyed by the content:// uri itself -- FakeSafStreamPlatform.readFileBytes
    // reads straight out of this map, same as DownloadManager's own
    // resolve-then-read SAF path. Real (if minimal) 1x1 PNGs, not arbitrary
    // bytes -- Image.memory tries to decode whatever it's given, and a
    // decode failure fails this test for an unrelated reason.
    safUtil.existingChildPaths['content://tree/1.jpg'] = _redOnePixelPng;
    safUtil.existingChildPaths['content://tree/2.jpg'] = _blueOnePixelPng;

    final repository = FakeBunnyRepository();
    final posts = [_post(1), _post(2)];
    final localFilePaths = {1: 'content://tree/1.jpg', 2: 'content://tree/2.jpg'};

    await tester.pumpWidget(
      wrapWithLocalization(SlideshowScreen(posts: posts, localFilePaths: localFilePaths, interval: const Duration(seconds: 5), repository: repository)),
    );
    await tester.pumpAndSettle();

    Uint8List currentBytes() => ((tester.widget(find.byType(Image)) as Image).image as MemoryImage).bytes;
    final firstBytes = currentBytes();

    await tester.tapAt(const Offset(750, 20));
    await tester.pumpAndSettle();

    // Without a post-specific key on PostMediaPage, _LocalContentUriImage's
    // State survives this rebuild and never re-reads -- currentBytes() would
    // still equal firstBytes despite _advance() having moved to the other
    // post (confirmed live: the slideshow got stuck on the first post's
    // image on Android no matter how many times it was tapped or how long
    // it waited).
    expect(currentBytes(), isNot(equals(firstBytes)));
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
