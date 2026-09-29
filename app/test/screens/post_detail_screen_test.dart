import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/screens/post_detail_screen.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../fakes/fake_bunny_repository.dart';
import '../fakes/fake_video_player_platform.dart';
import '../fakes/test_app.dart';

BunnyPost _post({String? fileExt, String? fileUrl}) => BunnyPost(
  id: 1,
  site: BunnySite.e621,
  externalId: 1,
  artist: 'someartist',
  title: 'A title',
  description: 'A description',
  rating: 'safe',
  score: 42,
  favCount: 10,
  commentCount: 3,
  fileUrl: fileUrl ?? 'https://example.invalid/file.$fileExt',
  fileExt: fileExt,
  width: 640,
  height: 480,
  createdAtSite: '2026-01-01T00:00:00Z',
  cachedAt: '2026-01-01T00:00:00Z',
  isSeen: false,
  isFavorited: false,
);

void main() {
  setUpAll(() {
    VideoPlayerPlatform.instance = FakeVideoPlayerPlatform();
  });

  testWidgets('marks the post seen once when opened', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.postsBySearchId[1] = [_post(fileExt: 'jpg')];

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: repository.postsBySearchId[1]!.single, repository: repository)));
    await tester.pumpAndSettle();

    expect(repository.postsBySearchId[1]!.single.isSeen, isTrue);
  });

  testWidgets('shows full metadata', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg');

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository)));
    await tester.pumpAndSettle();

    expect(find.text('A title'), findsOneWidget);
    expect(find.text('someartist'), findsOneWidget);
    expect(find.text('A description'), findsOneWidget);
    expect(find.text('safe'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('640x480'), findsOneWidget);
  });

  for (final ext in ['jpg', 'png', 'gif', 'webp']) {
    testWidgets('renders a CachedNetworkImage for a $ext post', (WidgetTester tester) async {
      final repository = FakeBunnyRepository();
      final post = _post(fileExt: ext);

      await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository)));
      await tester.pumpAndSettle();

      expect(find.byType(CachedNetworkImage), findsOneWidget);
      expect(find.byType(VideoPlayer), findsNothing);
    });
  }

  for (final ext in ['webm', 'mp4']) {
    testWidgets('renders a VideoPlayer for a $ext post', (WidgetTester tester) async {
      final repository = FakeBunnyRepository();
      final post = _post(fileExt: ext);

      await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository)));
      await tester.pumpAndSettle();

      expect(find.byType(VideoPlayer), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });
  }

  testWidgets('shows an unsupported-format placeholder for swf', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'swf');

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository)));
    await tester.pumpAndSettle();

    expect(find.textContaining('swf'), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.byType(VideoPlayer), findsNothing);
  });
}
