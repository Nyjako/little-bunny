import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/screens/post_grid_screen.dart';
import 'package:little_bunny/settings/display_settings_store.dart';
import 'package:little_bunny/settings/sync_settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_bunny_repository.dart';
import '../fakes/test_app.dart';

BunnyPost _post({required int id, required bool isSeen, BunnySite site = BunnySite.e621, String? previewUrl, String? sampleUrl, String? rating, int score = 0, int favCount = 0}) => BunnyPost(
  id: id,
  site: site,
  externalId: id,
  rating: rating,
  score: score,
  favCount: favCount,
  commentCount: 0,
  previewUrl: previewUrl,
  sampleUrl: sampleUrl,
  width: 100,
  height: 100,
  cachedAt: '2026-01-01T00:00:00Z',
  isSeen: isSeen,
  isFavorited: false,
);

void main() {
  final search = const BunnySearch(id: 1, site: BunnySite.e621, label: 'Foxes', query: 'fox', intervalHours: 24, createdAt: '2026-01-01T00:00:00Z');

  testWidgets('shows the empty state when there are no cached posts', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    await tester.pumpWidget(wrapWithLocalization(PostGridScreen(search: search, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore())));
    await tester.pumpAndSettle();

    expect(find.text('No posts cached yet. Tap refresh to sync.'), findsOneWidget);
  });

  testWidgets('renders a tile per cached post', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.postsBySearchId[1] = [_post(id: 1, isSeen: false), _post(id: 2, isSeen: true)];

    await tester.pumpWidget(wrapWithLocalization(PostGridScreen(search: search, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore())));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey(1)), findsOneWidget);
    expect(find.byKey(const ValueKey(2)), findsOneWidget);
  });

  testWidgets('toggling unseen-only filters out seen posts', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.postsBySearchId[1] = [_post(id: 1, isSeen: false), _post(id: 2, isSeen: true)];

    await tester.pumpWidget(wrapWithLocalization(PostGridScreen(search: search, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore())));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey(1)), findsOneWidget);
    expect(find.byKey(const ValueKey(2)), findsOneWidget);

    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey(1)), findsOneWidget);
    expect(find.byKey(const ValueKey(2)), findsNothing);
  });

  testWidgets('tapping a post opens PostDetailScreen, marking it seen and clearing its marker on return', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.postsBySearchId[1] = [_post(id: 1, isSeen: false)];

    await tester.pumpWidget(wrapWithLocalization(PostGridScreen(search: search, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore())));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey(1)));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Post'), findsOneWidget);
    expect(repository.postsBySearchId[1]!.single.isSeen, isTrue);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Foxes'), findsOneWidget);
  });

  testWidgets('tapping refresh calls syncDueSearches then reloads', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();

    await tester.pumpWidget(wrapWithLocalization(PostGridScreen(search: search, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore())));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();

    expect(repository.syncCallCount, 1);
  });

  testWidgets('sends CDN headers for an Inkbunny thumbnail but not an e621 one', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.postsBySearchId[1] = [
      _post(id: 1, isSeen: false, site: BunnySite.e621, previewUrl: 'https://static1.e621.net/preview.jpg'),
      _post(id: 2, isSeen: false, site: BunnySite.inkbunny, previewUrl: 'https://nl1.ib.metapix.net/thumbnails/large/thumb.jpg'),
    ];

    await tester.pumpWidget(wrapWithLocalization(PostGridScreen(search: search, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore())));
    await tester.pumpAndSettle();

    final e621Image = tester.widget<CachedNetworkImage>(find.descendant(of: find.byKey(const ValueKey(1)), matching: find.byType(CachedNetworkImage)));
    final inkbunnyImage = tester.widget<CachedNetworkImage>(find.descendant(of: find.byKey(const ValueKey(2)), matching: find.byType(CachedNetworkImage)));

    expect(e621Image.httpHeaders, isNull);
    expect(inkbunnyImage.httpHeaders, isNotNull);
    expect(inkbunnyImage.httpHeaders!['Referer'], 'https://inkbunny.net/');
  });

  testWidgets('mark all as seen clears every unseen marker', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.postsBySearchId[1] = [_post(id: 1, isSeen: false), _post(id: 2, isSeen: false)];

    await tester.pumpWidget(wrapWithLocalization(PostGridScreen(search: search, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore())));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<void>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark all as seen'));
    await tester.pumpAndSettle();

    expect(repository.postsBySearchId[1]!.every((post) => post.isSeen), isTrue);
  });

  testWidgets('honors a non-default grid column count from settings', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'grid_columns': 5});
    final repository = FakeBunnyRepository();
    repository.postsBySearchId[1] = [_post(id: 1, isSeen: false)];

    await tester.pumpWidget(wrapWithLocalization(PostGridScreen(search: search, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore())));
    await tester.pumpAndSettle();

    final gridView = tester.widget<GridView>(find.byType(GridView));
    final delegate = gridView.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 5);
  });

  testWidgets('medium preview quality prefers sampleUrl when present, falls back to previewUrl otherwise', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'preview_quality': 'medium'});
    final repository = FakeBunnyRepository();
    repository.postsBySearchId[1] = [
      _post(id: 1, isSeen: false, previewUrl: 'https://example.com/1_preview.jpg', sampleUrl: 'https://example.com/1_sample.jpg'),
      _post(id: 2, isSeen: false, previewUrl: 'https://example.com/2_preview.jpg'),
    ];

    await tester.pumpWidget(wrapWithLocalization(PostGridScreen(search: search, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore())));
    await tester.pumpAndSettle();

    final withSample = tester.widget<CachedNetworkImage>(find.descendant(of: find.byKey(const ValueKey(1)), matching: find.byType(CachedNetworkImage)));
    final withoutSample = tester.widget<CachedNetworkImage>(find.descendant(of: find.byKey(const ValueKey(2)), matching: find.byType(CachedNetworkImage)));

    expect(withSample.imageUrl, 'https://example.com/1_sample.jpg');
    expect(withoutSample.imageUrl, 'https://example.com/2_preview.jpg');
  });

  testWidgets('thumbnail preview quality always uses previewUrl, even when sampleUrl is present', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'preview_quality': 'thumbnail'});
    final repository = FakeBunnyRepository();
    repository.postsBySearchId[1] = [_post(id: 1, isSeen: false, previewUrl: 'https://example.com/1_preview.jpg', sampleUrl: 'https://example.com/1_sample.jpg')];

    await tester.pumpWidget(wrapWithLocalization(PostGridScreen(search: search, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore())));
    await tester.pumpAndSettle();

    final image = tester.widget<CachedNetworkImage>(find.descendant(of: find.byKey(const ValueKey(1)), matching: find.byType(CachedNetworkImage)));
    expect(image.imageUrl, 'https://example.com/1_preview.jpg');
  });

  testWidgets('shows a rating badge and score/fav-count overlay per tile', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.postsBySearchId[1] = [_post(id: 1, isSeen: false, rating: 'e', score: 12, favCount: 34)];

    await tester.pumpWidget(wrapWithLocalization(PostGridScreen(search: search, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore())));
    await tester.pumpAndSettle();

    final tile = find.byKey(const ValueKey(1));
    expect(find.descendant(of: tile, matching: find.text('E')), findsOneWidget);
    expect(find.descendant(of: tile, matching: find.text('12')), findsOneWidget);
    expect(find.descendant(of: tile, matching: find.text('34')), findsOneWidget);
  });

  testWidgets('long-pressing a tile enters selection mode and selects it', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.postsBySearchId[1] = [_post(id: 1, isSeen: false), _post(id: 2, isSeen: false)];

    await tester.pumpWidget(wrapWithLocalization(PostGridScreen(search: search, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore())));
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const ValueKey(1)));
    await tester.pumpAndSettle();

    expect(find.text('1 selected'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey(2)));
    await tester.pumpAndSettle();

    expect(find.text('2 selected'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNWidgets(2));

    await tester.tap(find.byKey(const ValueKey(2)));
    await tester.pumpAndSettle();

    expect(find.text('1 selected'), findsOneWidget);
  });

  testWidgets('exiting selection mode clears the selection and restores the normal app bar', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.postsBySearchId[1] = [_post(id: 1, isSeen: false)];

    await tester.pumpWidget(wrapWithLocalization(PostGridScreen(search: search, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore())));
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const ValueKey(1)));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('Foxes'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });

  testWidgets('mass-favorite queues every selected post once then processes the queue once', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.postsBySearchId[1] = [_post(id: 1, isSeen: false), _post(id: 2, isSeen: false), _post(id: 3, isSeen: false)];

    await tester.pumpWidget(wrapWithLocalization(PostGridScreen(search: search, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore())));
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const ValueKey(1)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey(2)));
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(of: find.byType(AppBar), matching: find.byIcon(Icons.favorite)));
    await tester.pumpAndSettle();

    expect(repository.favoriteAddCalls, unorderedEquals([1, 2]));
    expect(repository.processQueueCallCount, 1);
    expect(find.text('Foxes'), findsOneWidget);
  });

  testWidgets('mass-vote queues every selected post once with the given score', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.postsBySearchId[1] = [_post(id: 1, isSeen: false), _post(id: 2, isSeen: false)];

    await tester.pumpWidget(wrapWithLocalization(PostGridScreen(search: search, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore())));
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const ValueKey(1)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey(2)));
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(of: find.byType(AppBar), matching: find.byIcon(Icons.arrow_upward)));
    await tester.pumpAndSettle();

    expect(repository.voteCalls, unorderedEquals([(1, 1), (2, 1)]));
    expect(repository.processQueueCallCount, 1);
  });

  testWidgets('vote actions are absent in selection mode for an Inkbunny search', (WidgetTester tester) async {
    final inkbunnySearch = const BunnySearch(id: 2, site: BunnySite.inkbunny, label: 'Wolves', query: 'wolf', intervalHours: 24, createdAt: '2026-01-01T00:00:00Z');
    final repository = FakeBunnyRepository();
    repository.postsBySearchId[2] = [_post(id: 1, isSeen: false, site: BunnySite.inkbunny)];

    await tester.pumpWidget(wrapWithLocalization(PostGridScreen(search: inkbunnySearch, repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore())));
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const ValueKey(1)));
    await tester.pumpAndSettle();

    expect(find.descendant(of: find.byType(AppBar), matching: find.byIcon(Icons.favorite)), findsOneWidget);
    expect(find.descendant(of: find.byType(AppBar), matching: find.byIcon(Icons.arrow_upward)), findsNothing);
    expect(find.descendant(of: find.byType(AppBar), matching: find.byIcon(Icons.arrow_downward)), findsNothing);
  });
}
