import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/screens/post_detail_screen.dart';
import 'package:little_bunny/services/download_manager.dart';
import 'package:little_bunny/services/download_queue_service.dart';
import 'package:little_bunny/settings/display_settings_store.dart';
import 'package:little_bunny/settings/download_settings_store.dart';
import 'package:little_bunny/widgets/gif_player.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../fakes/fake_bunny_repository.dart';
import '../fakes/fake_path_provider.dart';
import '../fakes/fake_video_player_platform.dart';
import '../fakes/fake_wakelock_plus_platform.dart';
import '../fakes/test_app.dart';

/// Finds the still-image path's [Image] widget (now built with an explicit
/// [CachedNetworkImageProvider] + `loadingBuilder`, not `CachedNetworkImage`
/// itself -- see `_buildMedia`'s own doc comment for why) -- a plain
/// `find.byType(Image)` would also match any other `Image` elsewhere on the
/// page, so this checks the `image` property too.
Finder _findCachedNetworkImage() => find.byWidgetPredicate((widget) => widget is Image && widget.image is CachedNetworkImageProvider);

/// A fresh [DownloadQueueService] per call -- tests that don't care about
/// the download queue at all (most of this file -- only the "download
/// button" group below actually exercises it) just need a valid instance
/// to satisfy the constructor.
DownloadQueueService _downloadQueueService() => DownloadQueueService(downloadManager: const DownloadManager(), downloadSettingsStore: const DownloadSettingsStore());

/// Stubs [DownloadManager.isDownloaded] to always report a file already on
/// disk, rather than seeding a real file and letting the real `dart:io`
/// `File.exists()` call run -- a real check never resolves inside
/// `testWidgets`'s FakeAsync zone when kicked off from `initState` (unlike
/// `runAsync`-wrapped calls made later, directly from the test body), so
/// faking the manager's answer is simpler than fighting that zone.
class _AlreadyDownloadedManager extends DownloadManager {
  const _AlreadyDownloadedManager();

  @override
  Future<bool> isDownloaded(BunnyPost post, String destinationFolder) async => true;
}

BunnyPost _post({
  String? fileExt,
  String? fileUrl,
  bool noFileUrl = false,
  String? fileMd5,
  BunnySite site = BunnySite.e621,
  int id = 1,
  int externalId = 1,
  String title = 'A title',
  int commentCount = 3,
  int width = 640,
  int height = 480,
}) => BunnyPost(
  id: id,
  site: site,
  externalId: externalId,
  artist: 'someartist',
  title: title,
  description: 'A description',
  rating: 'safe',
  score: 42,
  scoreUp: 15,
  scoreDown: 4,
  favCount: 10,
  commentCount: commentCount,
  fileUrl: noFileUrl ? null : (fileUrl ?? 'https://example.invalid/file.$fileExt'),
  fileExt: fileExt,
  fileMd5: fileMd5,
  width: width,
  height: height,
  createdAtSite: '2026-01-01T00:00:00Z',
  cachedAt: '2026-01-01T00:00:00Z',
  isSeen: false,
  isFavorited: false,
);

void main() {
  final wakelockPlatform = FakeWakelockPlusPlatform();

  setUpAll(() {
    VideoPlayerPlatform.instance = FakeVideoPlayerPlatform();
    wakelockPlusPlatformInstance = wakelockPlatform;
  });

  // The headless `flutter_tester` engine has no real clipboard, so
  // `Clipboard.setData`'s platform channel call would otherwise never
  // resolve inside a widget test's fake-async pump loop.
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
    // Without this, `DownloadManager.downloadPost`'s atomic-write step
    // (`getTemporaryDirectory()`, M43) has no platform binding to answer its
    // method channel call under the bare `flutter_tester` VM, so every real
    // download in this file silently resolves to `DownloadOutcome.failed`.
    PathProviderPlatform.instance = FakePathProviderPlatform();
  });

  Future<void> scrollToEnd(WidgetTester tester) async {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
    await tester.pumpAndSettle();
  }

  testWidgets('marks the post seen once when opened', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.postsBySearchId[1] = [_post(fileExt: 'jpg')];

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: repository.postsBySearchId[1]!.single, repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService())));
    await tester.pumpAndSettle();

    expect(repository.postsBySearchId[1]!.single.isSeen, isTrue);
  });

  /// A post viewed via a pool/tag browse (TagBrowseScreen) rather than a
  /// saved search's own grid resolves to the same global per-post is_seen
  /// flag either way, but markPostSeen is fire-and-forget here -- a
  /// transient failure on that one call previously left the post unseen
  /// forever with no retry and no visible error (M26's investigation into
  /// "posts viewed through a pool stay marked unread").
  testWidgets('retries once if markPostSeen fails transiently, and still marks the post seen', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.postsBySearchId[1] = [_post(fileExt: 'jpg')];
    repository.markPostSeenTransientFailures.add(1);

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: repository.postsBySearchId[1]!.single, repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService())));
    await tester.pumpAndSettle();

    expect(repository.markPostSeenCalls, [1, 1]); // first call failed, retried once
    expect(repository.postsBySearchId[1]!.single.isSeen, isTrue);
  });

  testWidgets('swiping moves to the next post in siblingPosts and marks only that one seen', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final posts = [_post(id: 1, externalId: 1, title: 'First'), _post(id: 2, externalId: 2, title: 'Second'), _post(id: 3, externalId: 3, title: 'Third')];
    repository.postsBySearchId[1] = posts;

    await tester.pumpWidget(
      wrapWithLocalization(PostDetailScreen(post: posts[0], repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService(), siblingPosts: posts)),
    );
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget);
    expect(posts[0].isSeen, isTrue);
    expect(posts[1].isSeen, isFalse);

    await tester.drag(find.byType(PageView), const Offset(-800, 0));
    await tester.pumpAndSettle();

    expect(find.text('Second'), findsOneWidget);
    expect(repository.postsBySearchId[1]![1].isSeen, isTrue);
    expect(repository.postsBySearchId[1]![2].isSeen, isFalse);
  });

  testWidgets('swiping inside the fullscreen viewer then closing it shows the post swiped to, not the one it was opened from', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final posts = [
      _post(id: 1, externalId: 1, title: 'First', fileExt: 'jpg'),
      _post(id: 2, externalId: 2, title: 'Second', fileExt: 'jpg'),
      _post(id: 3, externalId: 3, title: 'Third', fileExt: 'jpg'),
    ];
    repository.postsBySearchId[1] = posts;

    await tester.pumpWidget(
      wrapWithLocalization(PostDetailScreen(post: posts[0], repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService(), siblingPosts: posts)),
    );
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget);

    // tester.tap's hit-testing is unreliable here -- the tap target sits
    // under nested scrollables/gesture arenas (the outer PageView plus the
    // page's own scroll view), so it's invoked directly instead.
    tester.widget<GestureDetector>(find.byKey(const Key('postDetailImageTapTarget'))).onTap!();
    await tester.pumpAndSettle();
    expect(find.byType(PhotoViewGallery), findsOneWidget);

    await tester.drag(find.byType(PhotoViewGallery), const Offset(-800, 0));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.byType(PhotoViewGallery), findsNothing);
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('First'), findsNothing);
  });

  testWidgets('opening fullscreen includes video posts too, not just images (M35)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final posts = [
      _post(id: 1, externalId: 1, title: 'First', fileExt: 'jpg'),
      _post(id: 2, externalId: 2, title: 'A video', fileExt: 'mp4'),
      _post(id: 3, externalId: 3, title: 'Third', fileExt: 'jpg'),
    ];
    repository.postsBySearchId[1] = posts;

    await tester.pumpWidget(
      wrapWithLocalization(PostDetailScreen(post: posts[0], repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService(), siblingPosts: posts)),
    );
    await tester.pumpAndSettle();

    tester.widget<GestureDetector>(find.byKey(const Key('postDetailImageTapTarget'))).onTap!();
    await tester.pumpAndSettle();
    expect(find.byType(PhotoViewGallery), findsOneWidget);

    // Previously the video post was filtered out entirely, so swiping once
    // from the first image landed straight on the third post instead.
    await tester.drag(find.byType(PhotoViewGallery), const Offset(-800, 0));
    await tester.pumpAndSettle();

    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(repository.postsBySearchId[1]![1].isSeen, isTrue);
  });

  testWidgets('right/left arrow keys move between posts in siblingPosts', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final posts = [_post(id: 1, externalId: 1, title: 'First'), _post(id: 2, externalId: 2, title: 'Second')];
    repository.postsBySearchId[1] = posts;

    await tester.pumpWidget(
      wrapWithLocalization(PostDetailScreen(post: posts[0], repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService(), siblingPosts: posts)),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget);
  });

  testWidgets('with no siblingPosts, falls back to a single-page view of just the opened post', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg');
    repository.postsBySearchId[1] = [post];

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService())));
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsOneWidget);
    expect(repository.postsBySearchId[1]!.single.isSeen, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsOneWidget);
  });

  testWidgets('enables the wakelock while open and disables it on leaving (M47)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg');
    repository.postsBySearchId[1] = [post];
    wakelockPlatform.enabledValue = false;

    await tester.pumpWidget(
      wrapWithLocalization(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService())),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(wakelockPlatform.enabledValue, isTrue);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(wakelockPlatform.enabledValue, isFalse);
  });

  testWidgets('app bar shrinks on wide windows (M9.6.6)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg');
    final screen = PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService());

    // 600 rather than a typical 400-ish phone width -- at 400 the comments
    // section's anonymous-checkbox row (pre-existing, unrelated to this
    // sub-milestone) overflows regardless of app bar height, which isn't
    // what this test is checking.
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrapWithLocalization(screen));
    await tester.pumpAndSettle();
    final narrowHeight = tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight ?? kToolbarHeight;

    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpWidget(wrapWithLocalization(screen));
    await tester.pumpAndSettle();
    final wideHeight = tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight ?? kToolbarHeight;

    expect(wideHeight, lessThan(narrowHeight));
  });

  testWidgets('shows full metadata', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg');

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService())));
    await tester.pumpAndSettle();

    expect(find.text('A title'), findsOneWidget);
    expect(find.text('someartist'), findsOneWidget);
    expect(find.text('A description'), findsOneWidget);
    expect(find.text('safe'), findsOneWidget); // rendered via RatingBadge (M9.6.5)
    expect(find.text('15'), findsOneWidget); // scoreUp, shown next to the upvote icon
    expect(find.text('4'), findsOneWidget); // scoreDown, shown next to the downvote icon
    expect(find.text('10'), findsOneWidget); // favCount, shown next to the favorite icon

    await scrollToEnd(tester);
    expect(find.text('3'), findsOneWidget); // commentCount, in the post-details column
    expect(find.text('640x480'), findsOneWidget);
  });

  // A sync pass only ever stores what Inkbunny's own search/listing endpoint
  // returns, which omits tags, full file dimensions, and comment count
  // entirely (only present on a full per-submission fetch) -- opening a post
  // first synced that way previously showed no image, 0x0 dimensions, 0
  // comments, and no tags at all, despite the thumbnail working fine in the
  // grid. The page now does a live fetchPost+getPost refresh on open before
  // showing tags/dimensions/comment-count/media, fixing this for Inkbunny and
  // keeping e621's own counts current at the same time (M27).
  testWidgets('refreshes a thin/stale cached post (M27) -- fills in dimensions, comment count, tags, and media', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final stalePost = _post(site: BunnySite.inkbunny, noFileUrl: true, commentCount: 0, width: 0, height: 0);
    final freshPost = _post(site: BunnySite.inkbunny, fileExt: 'jpg', commentCount: 7, width: 1200, height: 900);
    repository.postsBySearchId[1] = [stalePost];
    repository.fetchPostResults['inkbunny:1'] = 1;
    repository.postsById[1] = freshPost;
    repository.tagsByPostId[1] = const [BunnyPostTag(name: 'freshly_loaded_tag', category: 'general')];

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: stalePost, repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService())));
    await tester.pumpAndSettle();

    expect(_findCachedNetworkImage(), findsOneWidget);
    await scrollToEnd(tester);
    expect(find.text('7'), findsOneWidget); // refreshed commentCount
    expect(find.text('1200x900'), findsOneWidget); // refreshed dimensions
    expect(find.text('freshly_loaded_tag'), findsOneWidget);
  });

  for (final ext in ['jpg', 'png', 'webp']) {
    testWidgets('renders a CachedNetworkImage for a $ext post', (WidgetTester tester) async {
      final repository = FakeBunnyRepository();
      final post = _post(fileExt: ext);

      await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService())));
      await tester.pumpAndSettle();

      expect(_findCachedNetworkImage(), findsOneWidget);
      expect(find.byType(VideoPlayer), findsNothing);
    });
  }

  // Only checks which widget is used, not that it finishes loading --
  // GifPlayer drives a perpetual Timer-based animation loop once playing,
  // which (like any repeating animation) pumpAndSettle can never settle
  // past, so a single bounded pump() is used instead, same as this file's
  // other image/video tests never wait for a real network fetch to resolve
  // either.
  testWidgets('renders a GifPlayer (not a plain CachedNetworkImage) for a gif post (M49)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'gif');

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService())));
    await tester.pump();

    expect(find.byType(GifPlayer), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.byType(VideoPlayer), findsNothing);
  });

  for (final ext in ['webm', 'mp4']) {
    testWidgets('renders a VideoPlayer for a $ext post', (WidgetTester tester) async {
      final repository = FakeBunnyRepository();
      final post = _post(fileExt: ext);

      await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService())));
      await tester.pumpAndSettle();

      expect(find.byType(VideoPlayer), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });
  }

  testWidgets('shows an unsupported-format placeholder for swf', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'swf');

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService())));
    await tester.pumpAndSettle();

    expect(find.textContaining('swf'), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.byType(VideoPlayer), findsNothing);
  });

  testWidgets('shows tag chips grouped by category', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg');
    repository.tagsByPostId[1] = const [
      BunnyPostTag(name: 'some_character', category: 'character'),
      BunnyPostTag(name: 'some_species', category: 'species'),
      BunnyPostTag(name: 'uncategorized_tag'),
    ];

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService())));
    await tester.pumpAndSettle();
    await scrollToEnd(tester);

    expect(find.text('Character'), findsOneWidget);
    expect(find.text('Species'), findsOneWidget);
    expect(find.text('Tags'), findsOneWidget);
    expect(find.text('some_character'), findsOneWidget);
    expect(find.text('some_species'), findsOneWidget);
    expect(find.text('uncategorized_tag'), findsOneWidget);
  });

  testWidgets('sorts tag category headers into the fixed order, unrecognized last (M9.6.5)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg');
    // Deliberately out of order (species before artist, meta before
    // character, uncategorized first) to prove the screen re-sorts rather
    // than just rendering whatever order the tags arrived in.
    repository.tagsByPostId[1] = const [
      BunnyPostTag(name: 'uncategorized_tag'),
      BunnyPostTag(name: 'some_meta', category: 'meta'),
      BunnyPostTag(name: 'some_species', category: 'species'),
      BunnyPostTag(name: 'some_character', category: 'character'),
      BunnyPostTag(name: 'someartist_tag', category: 'artist'),
    ];

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService())));
    await tester.pumpAndSettle();
    await scrollToEnd(tester);

    final headerOrder = ['Artist', 'Character', 'Species', 'Meta', 'Tags'];
    final offsets = headerOrder.map((header) => tester.getTopLeft(find.text(header)).dy).toList();
    expect(offsets, orderedEquals(List.of(offsets)..sort()));
  });

  testWidgets('the thick info bar shows the artist, rating badge, and stat counts (M9.6.5)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg');

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService())));
    await tester.pumpAndSettle();

    // The artist line sits above the rating/stats line, both inside the bar.
    final artistY = tester.getTopLeft(find.text('someartist')).dy;
    final ratingY = tester.getTopLeft(find.text('safe')).dy;
    expect(ratingY, greaterThan(artistY));

    expect(find.text('15'), findsOneWidget); // scoreUp
    expect(find.text('4'), findsOneWidget); // scoreDown
    expect(find.text('10'), findsOneWidget); // favCount
    expect(find.byTooltip('Download'), findsOneWidget);

    // Tapping the artist name navigates to its tag-browse page, same as the
    // click-through behavior this bar replaced.
    await tester.tap(find.text('someartist'));
    await tester.pumpAndSettle();
    expect(find.text('No posts found for this search.'), findsOneWidget);
  });

  testWidgets('tags/details/sources lay out side by side on wide windows, stacked on narrow (M9.6.5)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg');
    final screen = PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService());

    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrapWithLocalization(screen));
    await tester.pumpAndSettle();
    await scrollToEnd(tester);
    expect(find.byKey(const Key('wideTagsDetailsSourcesRow')), findsNothing);

    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpWidget(wrapWithLocalization(screen));
    await tester.pumpAndSettle();
    await scrollToEnd(tester);
    expect(find.byKey(const Key('wideTagsDetailsSourcesRow')), findsOneWidget);
  });

  testWidgets('hides the sources section when there are none', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg');

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService())));
    await tester.pumpAndSettle();
    await scrollToEnd(tester);

    expect(find.text('Sources'), findsNothing);
  });

  testWidgets('shows a tappable sources list', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg');
    repository.sourcesByPostId[1] = ['https://example.invalid/a', 'https://example.invalid/b'];

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService())));
    await tester.pumpAndSettle();
    await scrollToEnd(tester);

    expect(find.text('Sources'), findsOneWidget);
    expect(find.text('https://example.invalid/a'), findsOneWidget);
    expect(find.text('https://example.invalid/b'), findsOneWidget);
  });

  testWidgets('copies the post id to the clipboard and shows a confirmation', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg', externalId: 12345);

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService())));
    await tester.pumpAndSettle();
    await scrollToEnd(tester);

    await tester.tap(find.text('12345'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Post ID copied to clipboard'), findsOneWidget);
  });

  testWidgets('shows parent/children chips and navigates to the parent', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg');
    repository.relationshipsByPostId[1] = const BunnyPostRelationships(hasParent: true, parentExternalId: 55, hasActiveChildren: false, children: [77, 88]);
    repository.fetchPostResults['e621:55'] = 2;
    repository.postsById[2] = _post(id: 2, externalId: 55, title: 'Parent post');

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService())));
    await tester.pumpAndSettle();
    await scrollToEnd(tester);

    expect(find.text('Parent'), findsOneWidget);
    expect(find.text('Children'), findsOneWidget);
    expect(find.text('#55'), findsOneWidget);
    expect(find.text('#77'), findsOneWidget);
    expect(find.text('#88'), findsOneWidget);

    await tester.tap(find.text('#55'));
    await tester.pumpAndSettle();

    expect(find.text('Parent post'), findsOneWidget);
  });

  testWidgets('opening a blacklisted parent shows a confirmation, cancelling stays put (M13.3)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg');
    repository.relationshipsByPostId[1] = const BunnyPostRelationships(hasParent: true, parentExternalId: 55, hasActiveChildren: false, children: []);
    repository.fetchPostResults['e621:55'] = 2;
    repository.postsById[2] = _post(id: 2, externalId: 55, title: 'Parent post');
    repository.tagsByPostId[2] = const [BunnyPostTag(name: 'young', category: 'general')];
    repository.blacklistBySite[BunnySite.e621] = {'young'};

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService())));
    await tester.pumpAndSettle();
    await scrollToEnd(tester);

    await tester.tap(find.text('#55'));
    await tester.pumpAndSettle();

    expect(find.text('Blacklisted tag'), findsOneWidget);
    expect(find.text('This post has a blacklisted tag: young'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Parent post'), findsNothing);
  });

  testWidgets('"View anyway" on a blacklisted parent navigates through (M13.3)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg');
    repository.relationshipsByPostId[1] = const BunnyPostRelationships(hasParent: true, parentExternalId: 55, hasActiveChildren: false, children: []);
    repository.fetchPostResults['e621:55'] = 2;
    repository.postsById[2] = _post(id: 2, externalId: 55, title: 'Parent post');
    repository.tagsByPostId[2] = const [BunnyPostTag(name: 'young', category: 'general')];
    repository.blacklistBySite[BunnySite.e621] = {'young'};

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService())));
    await tester.pumpAndSettle();
    await scrollToEnd(tester);

    await tester.tap(find.text('#55'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('View anyway'));
    await tester.pumpAndSettle();

    expect(find.text('Parent post'), findsOneWidget);
  });

  testWidgets('hides the relationships and pools sections for Inkbunny posts', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg', site: BunnySite.inkbunny);
    // Registered under the local post id regardless of site, to prove the
    // screen never even queries these for Inkbunny (not just that it hides
    // an empty result).
    repository.relationshipsByPostId[1] = const BunnyPostRelationships(hasParent: true, parentExternalId: 1, hasActiveChildren: false, children: [2]);
    repository.poolIdsByPostId[1] = [9];
    repository.commentsByPostId[1] = const [BunnyComment(id: 1, creatorName: 'someone', body: 'hi')];

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService())));
    await tester.pumpAndSettle();
    await scrollToEnd(tester);

    expect(find.text('Parent'), findsNothing);
    expect(find.text('Children'), findsNothing);
    expect(find.text('Pools'), findsNothing);
    expect(find.text('Discussion'), findsNothing);
    expect(find.text('hi'), findsNothing);
  });

  testWidgets('shows existing comments and posting a new one refreshes the list', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg');
    repository.commentsByPostId[1] = const [BunnyComment(id: 1, creatorName: 'someone', body: 'Nice pic!')];

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService())));
    await tester.pumpAndSettle();
    await scrollToEnd(tester);

    expect(find.text('Discussion'), findsOneWidget);
    expect(find.text('someone'), findsOneWidget);
    expect(find.text('Nice pic!'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Add a comment'), 'A new comment');
    await tester.tap(find.widgetWithText(FilledButton, 'Post'));
    await tester.pumpAndSettle();

    expect(repository.queueCommentCalls, [(1, 'A new comment', false)]);
    expect(repository.processQueueCallCount, 1);
    // The fake's queueComment doesn't actually append to commentsByPostId,
    // so the re-fetch after posting still returns the original one comment
    // -- this assertion is really about getPostComments being called again
    // (a second call would throw if the map had been cleared/removed).
    expect(find.text('Nice pic!'), findsOneWidget);
  });

  testWidgets('shows the empty state when a post has no comments yet', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg');

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService())));
    await tester.pumpAndSettle();
    await scrollToEnd(tester);

    expect(find.text('No comments yet.'), findsOneWidget);
  });

  testWidgets('pool chip opens a live preview without forcing a saved search', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg');
    repository.poolIdsByPostId[1] = [9];

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService())));
    await tester.pumpAndSettle();
    await scrollToEnd(tester);

    await tester.tap(find.text('#9'));
    await tester.pumpAndSettle();

    expect(find.text('pool:9'), findsOneWidget);
    // "order:id" (M22) -- pools display oldest-to-newest, not e621's default.
    expect(repository.previewSearchCalls, contains((BunnySite.e621, 'pool:9 order:id', 1)));
    expect(repository.searches, isEmpty);
  });

  testWidgets('pool chip pre-fills the save-as-search label with the pool\'s own name', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg');
    repository.poolIdsByPostId[1] = [9];
    repository.poolInfoById[9] = const BunnyPoolInfo(id: 9, name: 'My pool', postCount: 3);

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService())));
    await tester.pumpAndSettle();
    await scrollToEnd(tester);

    await tester.tap(find.text('#9'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Save as a search'));
    await tester.pumpAndSettle();

    final labelField = tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Label'));
    expect(labelField.controller!.text, 'My pool');
  });

  testWidgets('tapping favorite queues the action, drains the queue, and flips the icon', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg');

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService())));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Add to favorites'), findsOneWidget);

    await tester.tap(find.byTooltip('Add to favorites'));
    await tester.pumpAndSettle();

    expect(repository.favoriteAddCalls, [1]);
    expect(repository.processQueueCallCount, 1);
    expect(find.byTooltip('Remove from favorites'), findsOneWidget);
    expect(find.text('11'), findsOneWidget); // favCount optimistically bumped from 10

    await tester.tap(find.byTooltip('Remove from favorites'));
    await tester.pumpAndSettle();

    expect(repository.favoriteRemoveCalls, [1]);
    expect(repository.processQueueCallCount, 2);
    expect(find.byTooltip('Add to favorites'), findsOneWidget);
  });

  testWidgets('tapping upvote/downvote queues a vote and updates the displayed counts', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg');

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService())));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Upvote'));
    await tester.pumpAndSettle();

    expect(repository.voteCalls, [(1, 1)]);
    expect(repository.processQueueCallCount, 1);
    expect(find.text('16'), findsOneWidget); // scoreUp optimistically bumped from 15

    await tester.tap(find.byTooltip('Downvote'));
    await tester.pumpAndSettle();

    expect(repository.voteCalls, [(1, 1), (1, -1)]);
    expect(find.text('5'), findsOneWidget); // scoreDown optimistically bumped from 4
  });

  testWidgets('a failed favorite action shows an error instead of flipping the icon (M9.6.9)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.processQueueResult = const BunnyQueueStats(actionsProcessed: 1, actionsSucceeded: 0, actionsFailed: 1);
    final post = _post(fileExt: 'jpg');

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService())));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add to favorites'));
    await tester.pumpAndSettle();

    // Queued and drained, but the drain itself failed -- the UI must not
    // pretend it succeeded (the bug reported after M9.6's redesign: a
    // favorite looked applied until the post was reopened, because nothing
    // was actually persisted on a failed send).
    expect(repository.favoriteAddCalls, [1]);
    expect(find.byTooltip('Add to favorites'), findsOneWidget);
    expect(find.byTooltip('Remove from favorites'), findsNothing);
    expect(find.text('10'), findsOneWidget); // favCount unchanged
    expect(find.text("Couldn't send that action -- it wasn't saved"), findsOneWidget);
  });

  testWidgets('a failed vote action shows an error instead of bumping the count (M9.6.9)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.processQueueResult = const BunnyQueueStats(actionsProcessed: 1, actionsSucceeded: 0, actionsFailed: 1);
    final post = _post(fileExt: 'jpg');

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService())));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Upvote'));
    await tester.pumpAndSettle();

    expect(repository.voteCalls, [(1, 1)]);
    expect(find.text('15'), findsOneWidget); // scoreUp unchanged
    expect(find.text("Couldn't send that action -- it wasn't saved"), findsOneWidget);
  });

  testWidgets('a successful upvote highlights the arrow, surviving a simulated reopen (M9.7.1)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg');

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService())));
    await tester.pumpAndSettle();

    Icon upvoteIcon() => tester.widget<Icon>(find.descendant(of: find.byTooltip('Upvote'), matching: find.byIcon(Icons.arrow_upward)));
    expect(upvoteIcon().color, isNull);

    await tester.tap(find.byTooltip('Upvote'));
    await tester.pumpAndSettle();

    expect(upvoteIcon().color, Colors.green);

    // Reopening the post -- a fresh BunnyPost carrying the persisted
    // userVote, the way a real repository read would return it after the
    // M9.7.1 votes-mirror fix -- keeps the highlight. Before that fix there
    // was nothing to carry: userVote didn't exist, so a reopened post could
    // never show this at all.
    final reopenedPost = BunnyPost(
      id: post.id,
      site: post.site,
      externalId: post.externalId,
      score: post.score,
      favCount: post.favCount,
      commentCount: post.commentCount,
      width: post.width,
      height: post.height,
      cachedAt: post.cachedAt,
      isSeen: post.isSeen,
      isFavorited: post.isFavorited,
      userVote: 1,
    );
    await tester.pumpWidget(
      wrapWithLocalization(
        PostDetailScreen(post: reopenedPost, repository: FakeBunnyRepository(), displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService()),
      ),
    );
    await tester.pumpAndSettle();

    expect(upvoteIcon().color, Colors.green);
  });

  testWidgets('Inkbunny posts show 3 favorite hearts instead of vote buttons (M27)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg', site: BunnySite.inkbunny);

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService())));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Upvote'), findsNothing);
    expect(find.byTooltip('Downvote'), findsNothing);
    expect(find.byTooltip('Favorite (1/3 hearts)'), findsOneWidget);
    expect(find.byTooltip('Favorite (2/3 hearts)'), findsOneWidget);
    expect(find.byTooltip('Favorite (3/3 hearts)'), findsOneWidget);
  });

  testWidgets('tapping an Inkbunny heart queues a favorite at that tier and fills the hearts up to it (M27)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg', site: BunnySite.inkbunny);

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService())));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Favorite (2/3 hearts)'));
    await tester.pumpAndSettle();

    expect(repository.favoriteAddCalls, [1]);
    expect(repository.favoriteAddStarsCalls, [2]);
    expect(repository.processQueueCallCount, 1);
    expect(find.text('11'), findsOneWidget); // favCount optimistically bumped from 10

    // Tapping the already-selected top tier again removes the favorite
    // entirely -- Inkbunny's hearts are a single tier, not a cumulative
    // rating, so re-tapping the same heart is the "unfavorite" gesture.
    expect(find.byTooltip('Remove favorite'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove favorite'));
    await tester.pumpAndSettle();

    expect(repository.favoriteRemoveCalls, [1]);
    expect(find.text('10'), findsOneWidget); // favCount back to its original value
    expect(find.byTooltip('Favorite (2/3 hearts)'), findsOneWidget);
  });

  group('download button (M9.4)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('post_detail_download_test');
      SharedPreferences.setMockInitialValues({'download_destination_folder': tempDir.path});
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    testWidgets('download button is disabled when the post has no fileUrl', (WidgetTester tester) async {
      final repository = FakeBunnyRepository();
      final post = _post(noFileUrl: true);

      await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService())));
      await tester.pumpAndSettle();

      final downloadButton = find.ancestor(of: find.byTooltip('Download'), matching: find.byType(IconButton));
      expect(tester.widget<IconButton>(downloadButton).onPressed, isNull);
    });

    testWidgets('tapping download enqueues the post and shows immediate queued feedback (M43)', (WidgetTester tester) async {
      final repository = FakeBunnyRepository();
      final post = _post(fileExt: 'jpg');
      final downloadQueueService = DownloadQueueService(downloadManager: DownloadManager(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200))), downloadSettingsStore: const DownloadSettingsStore());

      await tester.pumpWidget(
        wrapWithLocalization(
          PostDetailScreen(
            post: post,
            repository: repository,
            displaySettingsStore: const DisplaySettingsStore(),
            downloadSettingsStore: const DownloadSettingsStore(),
            downloadQueueService: downloadQueueService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.ancestor(of: find.byTooltip('Download'), matching: find.byType(IconButton)));
      await tester.pump();

      expect(find.text('Queued for download'), findsOneWidget);
      expect(downloadQueueService.totalCount, 1);
    });

    testWidgets('queues and drains a favorite after a successful download when auto-favorite-on-download is on (M10.1)', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({'download_destination_folder': tempDir.path, 'auto_favorite_on_download': true});
      final repository = FakeBunnyRepository();
      final post = _post(fileExt: 'jpg');
      final downloadQueueService = DownloadQueueService(downloadManager: DownloadManager(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200))), downloadSettingsStore: const DownloadSettingsStore());

      await tester.pumpWidget(
        wrapWithLocalization(
          PostDetailScreen(
            post: post,
            repository: repository,
            displaySettingsStore: const DisplaySettingsStore(),
            downloadSettingsStore: const DownloadSettingsStore(),
            downloadQueueService: downloadQueueService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // tester.tap()'s gesture-arena resolution needs a pump() to actually
      // invoke onPressed, but pump() relies on the fake-async zone's own
      // clock -- mixing it with runAsync (needed so the real download work
      // this kicks off can actually resolve) is unreliable. Invoking
      // onPressed directly sidesteps gesture recognition entirely, so the
      // whole resulting async chain binds cleanly to runAsync's real zone
      // from the start.
      final downloadButton = tester.widget<IconButton>(find.ancestor(of: find.byTooltip('Download'), matching: find.byType(IconButton)));
      await tester.runAsync(() async {
        downloadButton.onPressed!();
        while (downloadQueueService.isActive) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      });

      expect(repository.favoriteAddCalls, [post.id]);
      expect(repository.processQueueCallCount, 1);
    });

    testWidgets('does not queue a favorite when auto-favorite-on-download is off (the default)', (WidgetTester tester) async {
      final repository = FakeBunnyRepository();
      final post = _post(fileExt: 'jpg');
      final downloadQueueService = DownloadQueueService(downloadManager: DownloadManager(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200))), downloadSettingsStore: const DownloadSettingsStore());

      await tester.pumpWidget(
        wrapWithLocalization(
          PostDetailScreen(
            post: post,
            repository: repository,
            displaySettingsStore: const DisplaySettingsStore(),
            downloadSettingsStore: const DownloadSettingsStore(),
            downloadQueueService: downloadQueueService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // tester.tap()'s gesture-arena resolution needs a pump() to actually
      // invoke onPressed, but pump() relies on the fake-async zone's own
      // clock -- mixing it with runAsync (needed so the real download work
      // this kicks off can actually resolve) is unreliable. Invoking
      // onPressed directly sidesteps gesture recognition entirely, so the
      // whole resulting async chain binds cleanly to runAsync's real zone
      // from the start.
      final downloadButton = tester.widget<IconButton>(find.ancestor(of: find.byTooltip('Download'), matching: find.byType(IconButton)));
      await tester.runAsync(() async {
        downloadButton.onPressed!();
        while (downloadQueueService.isActive) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      });

      expect(repository.favoriteAddCalls, isEmpty);
      expect(repository.processQueueCallCount, 0);
    });

    testWidgets('queues and drains an upvote after a successful download when auto-upvote-on-download is on (M14.2)', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({'download_destination_folder': tempDir.path, 'auto_upvote_on_download': true});
      final repository = FakeBunnyRepository();
      final post = _post(fileExt: 'jpg');
      final downloadQueueService = DownloadQueueService(downloadManager: DownloadManager(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200))), downloadSettingsStore: const DownloadSettingsStore());

      await tester.pumpWidget(
        wrapWithLocalization(
          PostDetailScreen(
            post: post,
            repository: repository,
            displaySettingsStore: const DisplaySettingsStore(),
            downloadSettingsStore: const DownloadSettingsStore(),
            downloadQueueService: downloadQueueService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // tester.tap()'s gesture-arena resolution needs a pump() to actually
      // invoke onPressed, but pump() relies on the fake-async zone's own
      // clock -- mixing it with runAsync (needed so the real download work
      // this kicks off can actually resolve) is unreliable. Invoking
      // onPressed directly sidesteps gesture recognition entirely, so the
      // whole resulting async chain binds cleanly to runAsync's real zone
      // from the start.
      final downloadButton = tester.widget<IconButton>(find.ancestor(of: find.byTooltip('Download'), matching: find.byType(IconButton)));
      await tester.runAsync(() async {
        downloadButton.onPressed!();
        while (downloadQueueService.isActive) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      });

      expect(repository.voteCalls, [(post.id, 1)]);
      expect(repository.processQueueCallCount, 1);
    });

    testWidgets('does not queue an upvote when auto-upvote-on-download is off (the default)', (WidgetTester tester) async {
      final repository = FakeBunnyRepository();
      final post = _post(fileExt: 'jpg');
      final downloadQueueService = DownloadQueueService(downloadManager: DownloadManager(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200))), downloadSettingsStore: const DownloadSettingsStore());

      await tester.pumpWidget(
        wrapWithLocalization(
          PostDetailScreen(
            post: post,
            repository: repository,
            displaySettingsStore: const DisplaySettingsStore(),
            downloadSettingsStore: const DownloadSettingsStore(),
            downloadQueueService: downloadQueueService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // tester.tap()'s gesture-arena resolution needs a pump() to actually
      // invoke onPressed, but pump() relies on the fake-async zone's own
      // clock -- mixing it with runAsync (needed so the real download work
      // this kicks off can actually resolve) is unreliable. Invoking
      // onPressed directly sidesteps gesture recognition entirely, so the
      // whole resulting async chain binds cleanly to runAsync's real zone
      // from the start.
      final downloadButton = tester.widget<IconButton>(find.ancestor(of: find.byTooltip('Download'), matching: find.byType(IconButton)));
      await tester.runAsync(() async {
        downloadButton.onPressed!();
        while (downloadQueueService.isActive) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      });

      expect(repository.voteCalls, isEmpty);
      expect(repository.processQueueCallCount, 0);
    });

    testWidgets('shows the already-downloaded icon when a file already sits at the deterministic local path (M42)', (WidgetTester tester) async {
      final repository = FakeBunnyRepository();
      final post = _post(fileExt: 'jpg');

      await tester.pumpWidget(
        wrapWithLocalization(
          PostDetailScreen(
            post: post,
            repository: repository,
            displaySettingsStore: const DisplaySettingsStore(),
            downloadSettingsStore: const DownloadSettingsStore(), downloadQueueService: _downloadQueueService(),
            downloadManager: const _AlreadyDownloadedManager(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.download_done), findsOneWidget);
    });
  });
}
