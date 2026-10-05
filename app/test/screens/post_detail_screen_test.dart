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
import 'package:little_bunny/settings/display_settings_store.dart';
import 'package:little_bunny/settings/download_settings_store.dart';
import 'package:little_bunny/settings/sync_settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../fakes/fake_bunny_repository.dart';
import '../fakes/fake_video_player_platform.dart';
import '../fakes/test_app.dart';

BunnyPost _post({String? fileExt, String? fileUrl, bool noFileUrl = false, String? fileMd5, BunnySite site = BunnySite.e621, int id = 1, int externalId = 1, String title = 'A title'}) => BunnyPost(
  id: id,
  site: site,
  externalId: externalId,
  artist: 'someartist',
  title: title,
  description: 'A description',
  rating: 'safe',
  score: 42,
  favCount: 10,
  commentCount: 3,
  fileUrl: noFileUrl ? null : (fileUrl ?? 'https://example.invalid/file.$fileExt'),
  fileExt: fileExt,
  fileMd5: fileMd5,
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

  // The headless `flutter_tester` engine has no real clipboard, so
  // `Clipboard.setData`'s platform channel call would otherwise never
  // resolve inside a widget test's fake-async pump loop.
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  });

  testWidgets('marks the post seen once when opened', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.postsBySearchId[1] = [_post(fileExt: 'jpg')];

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: repository.postsBySearchId[1]!.single, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore(), downloadSettingsStore: const DownloadSettingsStore())));
    await tester.pumpAndSettle();

    expect(repository.postsBySearchId[1]!.single.isSeen, isTrue);
  });

  testWidgets('shows full metadata', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg');

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore(), downloadSettingsStore: const DownloadSettingsStore())));
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

      await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore(), downloadSettingsStore: const DownloadSettingsStore())));
      await tester.pumpAndSettle();

      expect(find.byType(CachedNetworkImage), findsOneWidget);
      expect(find.byType(VideoPlayer), findsNothing);
    });
  }

  for (final ext in ['webm', 'mp4']) {
    testWidgets('renders a VideoPlayer for a $ext post', (WidgetTester tester) async {
      final repository = FakeBunnyRepository();
      final post = _post(fileExt: ext);

      await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore(), downloadSettingsStore: const DownloadSettingsStore())));
      await tester.pumpAndSettle();

      expect(find.byType(VideoPlayer), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });
  }

  testWidgets('shows an unsupported-format placeholder for swf', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'swf');

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore(), downloadSettingsStore: const DownloadSettingsStore())));
    await tester.pumpAndSettle();

    expect(find.textContaining('swf'), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.byType(VideoPlayer), findsNothing);
  });

  Future<void> scrollToEnd(WidgetTester tester) async {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
    await tester.pumpAndSettle();
  }

  testWidgets('shows tag chips grouped by category', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg');
    repository.tagsByPostId[1] = const [
      BunnyPostTag(name: 'some_character', category: 'character'),
      BunnyPostTag(name: 'some_species', category: 'species'),
      BunnyPostTag(name: 'uncategorized_tag'),
    ];

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore(), downloadSettingsStore: const DownloadSettingsStore())));
    await tester.pumpAndSettle();
    await scrollToEnd(tester);

    expect(find.text('Character'), findsOneWidget);
    expect(find.text('Species'), findsOneWidget);
    expect(find.text('Tags'), findsOneWidget);
    expect(find.text('some_character'), findsOneWidget);
    expect(find.text('some_species'), findsOneWidget);
    expect(find.text('uncategorized_tag'), findsOneWidget);
  });

  testWidgets('hides the sources section when there are none', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg');

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore(), downloadSettingsStore: const DownloadSettingsStore())));
    await tester.pumpAndSettle();
    await scrollToEnd(tester);

    expect(find.text('Sources'), findsNothing);
  });

  testWidgets('shows a tappable sources list', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg');
    repository.sourcesByPostId[1] = ['https://example.invalid/a', 'https://example.invalid/b'];

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore(), downloadSettingsStore: const DownloadSettingsStore())));
    await tester.pumpAndSettle();
    await scrollToEnd(tester);

    expect(find.text('Sources'), findsOneWidget);
    expect(find.text('https://example.invalid/a'), findsOneWidget);
    expect(find.text('https://example.invalid/b'), findsOneWidget);
  });

  testWidgets('copies the post id to the clipboard and shows a confirmation', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg', externalId: 12345);

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore(), downloadSettingsStore: const DownloadSettingsStore())));
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

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore(), downloadSettingsStore: const DownloadSettingsStore())));
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

  testWidgets('hides the relationships and pools sections for Inkbunny posts', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg', site: BunnySite.inkbunny);
    // Registered under the local post id regardless of site, to prove the
    // screen never even queries these for Inkbunny (not just that it hides
    // an empty result).
    repository.relationshipsByPostId[1] = const BunnyPostRelationships(hasParent: true, parentExternalId: 1, hasActiveChildren: false, children: [2]);
    repository.poolIdsByPostId[1] = [9];
    repository.commentsByPostId[1] = const [BunnyComment(id: 1, creatorName: 'someone', body: 'hi')];

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore(), downloadSettingsStore: const DownloadSettingsStore())));
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

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore(), downloadSettingsStore: const DownloadSettingsStore())));
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

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore(), downloadSettingsStore: const DownloadSettingsStore())));
    await tester.pumpAndSettle();
    await scrollToEnd(tester);

    expect(find.text('No comments yet.'), findsOneWidget);
  });

  testWidgets('pool chip opens a live preview without forcing a saved search', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg');
    repository.poolIdsByPostId[1] = [9];

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore(), downloadSettingsStore: const DownloadSettingsStore())));
    await tester.pumpAndSettle();
    await scrollToEnd(tester);

    await tester.tap(find.text('#9'));
    await tester.pumpAndSettle();

    expect(find.text('pool:9'), findsOneWidget);
    expect(repository.previewSearchCalls, contains((BunnySite.e621, 'pool:9', 1)));
    expect(repository.searches, isEmpty);
  });

  testWidgets('pool chip pre-fills the save-as-search label with the pool\'s own name', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg');
    repository.poolIdsByPostId[1] = [9];
    repository.poolInfoById[9] = const BunnyPoolInfo(id: 9, name: 'My pool', postCount: 3);

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore(), downloadSettingsStore: const DownloadSettingsStore())));
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

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore(), downloadSettingsStore: const DownloadSettingsStore())));
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

  testWidgets('tapping upvote/downvote queues a vote and updates the displayed score', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg');

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore(), downloadSettingsStore: const DownloadSettingsStore())));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Upvote'));
    await tester.pumpAndSettle();

    expect(repository.voteCalls, [(1, 1)]);
    expect(repository.processQueueCallCount, 1);
    expect(find.text('43'), findsOneWidget); // score optimistically bumped from 42

    await tester.tap(find.byTooltip('Downvote'));
    await tester.pumpAndSettle();

    expect(repository.voteCalls, [(1, 1), (1, -1)]);
    expect(find.text('42'), findsOneWidget);
  });

  testWidgets('vote buttons are disabled for Inkbunny posts, favorite stays enabled', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg', site: BunnySite.inkbunny);

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore(), downloadSettingsStore: const DownloadSettingsStore())));
    await tester.pumpAndSettle();

    Finder iconButtonFor(String tooltip) => find.ancestor(of: find.byTooltip(tooltip), matching: find.byType(IconButton));

    expect(tester.widget<IconButton>(iconButtonFor('Upvote')).onPressed, isNull);
    expect(tester.widget<IconButton>(iconButtonFor('Downvote')).onPressed, isNull);
    expect(tester.widget<IconButton>(iconButtonFor('Add to favorites')).onPressed, isNotNull);
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

      await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore(), downloadSettingsStore: const DownloadSettingsStore())));
      await tester.pumpAndSettle();

      final downloadButton = find.ancestor(of: find.byTooltip('Download'), matching: find.byType(IconButton));
      expect(tester.widget<IconButton>(downloadButton).onPressed, isNull);
    });

    testWidgets('tapping download with a matching checksum shows the verified message', (WidgetTester tester) async {
      final repository = FakeBunnyRepository();
      final post = _post(fileExt: 'jpg');
      final bytes = [1, 2, 3];
      final downloadManager = DownloadManager(client: MockClient((_) async => http.Response.bytes(bytes, 200)));

      await tester.pumpWidget(
        wrapWithLocalization(
          PostDetailScreen(
            post: post,
            repository: repository,
            displaySettingsStore: const DisplaySettingsStore(),
            syncSettingsStore: const SyncSettingsStore(),
            downloadSettingsStore: const DownloadSettingsStore(),
            downloadManager: downloadManager,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.ancestor(of: find.byTooltip('Download'), matching: find.byType(IconButton)));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      });
      await tester.pump();

      expect(find.text('Downloaded and checksum verified'), findsOneWidget);
      expect(repository.recordDownloadCalls, hasLength(1));
      expect(find.byIcon(Icons.download_done), findsOneWidget);
    });

    testWidgets('tapping download with a mismatched checksum shows the mismatch message', (WidgetTester tester) async {
      final repository = FakeBunnyRepository();
      final post = _post(fileExt: 'jpg', fileMd5: 'not-the-real-checksum');
      final downloadManager = DownloadManager(client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));

      await tester.pumpWidget(
        wrapWithLocalization(
          PostDetailScreen(
            post: post,
            repository: repository,
            displaySettingsStore: const DisplaySettingsStore(),
            syncSettingsStore: const SyncSettingsStore(),
            downloadSettingsStore: const DownloadSettingsStore(),
            downloadManager: downloadManager,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.ancestor(of: find.byTooltip('Download'), matching: find.byType(IconButton)));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      });

      expect(find.text("Downloaded, but the checksum didn't match"), findsOneWidget);
    });

    testWidgets('tapping download on a failed HTTP response shows the failed message', (WidgetTester tester) async {
      final repository = FakeBunnyRepository();
      final post = _post(fileExt: 'jpg');
      final downloadManager = DownloadManager(client: MockClient((_) async => http.Response('', 500)));

      await tester.pumpWidget(
        wrapWithLocalization(
          PostDetailScreen(
            post: post,
            repository: repository,
            displaySettingsStore: const DisplaySettingsStore(),
            syncSettingsStore: const SyncSettingsStore(),
            downloadSettingsStore: const DownloadSettingsStore(),
            downloadManager: downloadManager,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.ancestor(of: find.byTooltip('Download'), matching: find.byType(IconButton)));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      });

      expect(find.text('Download failed'), findsOneWidget);
      expect(repository.recordDownloadCalls, isEmpty);
      expect(find.byIcon(Icons.download_done), findsNothing);
    });

    testWidgets('shows the already-downloaded icon when the post has prior download history', (WidgetTester tester) async {
      final repository = FakeBunnyRepository();
      final post = _post(fileExt: 'jpg');
      repository.downloadsByPostId[post.id] = [const BunnyDownload(id: 1, postId: 1, filePath: '/downloads/1.jpg', checksumVerified: true)];

      await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore(), downloadSettingsStore: const DownloadSettingsStore())));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.download_done), findsOneWidget);
    });
  });
}
