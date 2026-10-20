import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/screens/full_screen_post_viewer_screen.dart';
import 'package:photo_view/photo_view_gallery.dart';
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

  testWidgets('opens at the given initial index', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final posts = [_post(1), _post(2), _post(3)];

    await tester.pumpWidget(wrapWithLocalization(FullScreenPostViewerScreen(posts: posts, initialIndex: 1, repository: repository)));
    await tester.pump();

    final gallery = tester.widget<PhotoViewGallery>(find.byType(PhotoViewGallery));
    expect(gallery.pageController!.initialPage, 1);
    expect(gallery.itemCount, 3);
  });

  testWidgets('marks the new page\'s post seen when swiping to it', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final posts = [_post(1), _post(2), _post(3)];
    repository.postsBySearchId[1] = posts;

    await tester.pumpWidget(wrapWithLocalization(FullScreenPostViewerScreen(posts: posts, initialIndex: 0, repository: repository)));
    await tester.pump();

    await tester.drag(find.byType(PhotoViewGallery), const Offset(-800, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(repository.postsBySearchId[1]![1].isSeen, isTrue);
    expect(repository.postsBySearchId[1]![0].isSeen, isFalse);
    expect(repository.postsBySearchId[1]![2].isSeen, isFalse);
  });

  testWidgets('a video post is not skipped -- swiping to it plays it in place (M35)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final posts = [_post(1), _post(2, fileExt: 'mp4'), _post(3)];
    repository.postsBySearchId[1] = posts;

    await tester.pumpWidget(wrapWithLocalization(FullScreenPostViewerScreen(posts: posts, initialIndex: 0, repository: repository)));
    await tester.pumpAndSettle();
    expect(find.byType(VideoPlayer), findsNothing);

    await tester.drag(find.byType(PhotoViewGallery), const Offset(-800, 0));
    await tester.pumpAndSettle();

    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(repository.postsBySearchId[1]![1].isSeen, isTrue);
  });

  testWidgets('right/left arrow keys move to the next/previous post and stay in fullscreen', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final posts = [_post(1), _post(2), _post(3)];
    repository.postsBySearchId[1] = posts;

    await tester.pumpWidget(wrapWithLocalization(FullScreenPostViewerScreen(posts: posts, initialIndex: 0, repository: repository)));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(repository.postsBySearchId[1]![1].isSeen, isTrue);
    expect(find.byType(FullScreenPostViewerScreen), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(repository.postsBySearchId[1]![0].isSeen, isTrue);
    expect(find.byType(FullScreenPostViewerScreen), findsOneWidget);
  });

  testWidgets('arrow keys do not move past the first/last post', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final posts = [_post(1), _post(2)];

    await tester.pumpWidget(wrapWithLocalization(FullScreenPostViewerScreen(posts: posts, initialIndex: 0, repository: repository)));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final gallery = tester.widget<PhotoViewGallery>(find.byType(PhotoViewGallery));
    expect(gallery.pageController!.page, 0);
  });

  testWidgets('calls onPageChanged with the new post on swipe, live (not just once on exit)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final posts = [_post(1), _post(2), _post(3)];
    final changed = <int>[];

    await tester.pumpWidget(
      wrapWithLocalization(FullScreenPostViewerScreen(posts: posts, initialIndex: 0, repository: repository, onPageChanged: (post) => changed.add(post.id))),
    );
    await tester.pump();

    await tester.drag(find.byType(PhotoViewGallery), const Offset(-800, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(changed, [2]);
    // Still inside fullscreen -- this fires on every swipe, not on exit.
    expect(find.byType(FullScreenPostViewerScreen), findsOneWidget);
  });

  testWidgets('a close button pops the viewer', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final posts = [_post(1)];

    await tester.pumpWidget(
      wrapWithLocalization(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => FullScreenPostViewerScreen(posts: posts, initialIndex: 0, repository: repository))),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(FullScreenPostViewerScreen), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.byType(FullScreenPostViewerScreen), findsNothing);
  });

  testWidgets('sizes each page from the post\'s own dimensions rather than the decoded image', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final posts = [_post(1)];

    await tester.pumpWidget(wrapWithLocalization(FullScreenPostViewerScreen(posts: posts, initialIndex: 0, repository: repository)));
    await tester.pump();

    final gallery = tester.widget<PhotoViewGallery>(find.byType(PhotoViewGallery));
    final context = tester.element(find.byType(PhotoViewGallery));
    final options = gallery.builder!(context, 0);
    expect(options.childSize, const Size(640, 480));
    expect(options.imageProvider, isNull); // customChild is used instead, see M9.6.1
  });
}
