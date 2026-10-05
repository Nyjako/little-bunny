import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/screens/post_detail_screen.dart';
import 'package:little_bunny/settings/display_settings_store.dart';
import 'package:little_bunny/settings/sync_settings_store.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../fakes/fake_bunny_repository.dart';
import '../fakes/fake_video_player_platform.dart';
import '../fakes/test_app.dart';

BunnyPost _post({String? fileExt, String? fileUrl, BunnySite site = BunnySite.e621, int id = 1, int externalId = 1, String title = 'A title'}) => BunnyPost(
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

  // The headless `flutter_tester` engine has no real clipboard, so
  // `Clipboard.setData`'s platform channel call would otherwise never
  // resolve inside a widget test's fake-async pump loop.
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  });

  testWidgets('marks the post seen once when opened', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.postsBySearchId[1] = [_post(fileExt: 'jpg')];

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: repository.postsBySearchId[1]!.single, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore())));
    await tester.pumpAndSettle();

    expect(repository.postsBySearchId[1]!.single.isSeen, isTrue);
  });

  testWidgets('shows full metadata', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg');

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore())));
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

      await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore())));
      await tester.pumpAndSettle();

      expect(find.byType(CachedNetworkImage), findsOneWidget);
      expect(find.byType(VideoPlayer), findsNothing);
    });
  }

  for (final ext in ['webm', 'mp4']) {
    testWidgets('renders a VideoPlayer for a $ext post', (WidgetTester tester) async {
      final repository = FakeBunnyRepository();
      final post = _post(fileExt: ext);

      await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore())));
      await tester.pumpAndSettle();

      expect(find.byType(VideoPlayer), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });
  }

  testWidgets('shows an unsupported-format placeholder for swf', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'swf');

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore())));
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

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore())));
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

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore())));
    await tester.pumpAndSettle();
    await scrollToEnd(tester);

    expect(find.text('Sources'), findsNothing);
  });

  testWidgets('shows a tappable sources list', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg');
    repository.sourcesByPostId[1] = ['https://example.invalid/a', 'https://example.invalid/b'];

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore())));
    await tester.pumpAndSettle();
    await scrollToEnd(tester);

    expect(find.text('Sources'), findsOneWidget);
    expect(find.text('https://example.invalid/a'), findsOneWidget);
    expect(find.text('https://example.invalid/b'), findsOneWidget);
  });

  testWidgets('copies the post id to the clipboard and shows a confirmation', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg', externalId: 12345);

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore())));
    await tester.pumpAndSettle();

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

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore())));
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

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore())));
    await tester.pumpAndSettle();
    await scrollToEnd(tester);

    expect(find.text('Parent'), findsNothing);
    expect(find.text('Children'), findsNothing);
    expect(find.text('Pools'), findsNothing);
  });

  testWidgets('pool chip navigates to an existing pool search', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg');
    repository.poolIdsByPostId[1] = [9];
    repository.searches.add(const BunnySearch(id: 5, site: BunnySite.e621, label: 'My pool', query: 'pool:9', intervalHours: 24, createdAt: '2026-01-01T00:00:00Z'));

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore())));
    await tester.pumpAndSettle();
    await scrollToEnd(tester);

    await tester.tap(find.text('#9'));
    await tester.pumpAndSettle();

    expect(find.text('My pool'), findsOneWidget);
  });

  testWidgets('pool chip offers to create a search when none exists', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final post = _post(fileExt: 'jpg');
    repository.poolIdsByPostId[1] = [9];

    await tester.pumpWidget(wrapWithLocalization(PostDetailScreen(post: post, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore())));
    await tester.pumpAndSettle();
    await scrollToEnd(tester);

    await tester.tap(find.text('#9'));
    await tester.pumpAndSettle();

    expect(find.text('This post belongs to pool 9, but there\'s no saved search for it yet. Create one?'), findsOneWidget);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(repository.searches, hasLength(1));
    expect(repository.searches.single.query, 'pool:9');
    expect(find.text('pool:9'), findsOneWidget);
  });
}
