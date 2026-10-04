import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/screens/post_grid_screen.dart';

import '../fakes/fake_bunny_repository.dart';
import '../fakes/test_app.dart';

BunnyPost _post({required int id, required bool isSeen, BunnySite site = BunnySite.e621, String? previewUrl}) => BunnyPost(
  id: id,
  site: site,
  externalId: id,
  score: 0,
  favCount: 0,
  commentCount: 0,
  previewUrl: previewUrl,
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
    await tester.pumpWidget(wrapWithLocalization(PostGridScreen(search: search, repository: repository)));
    await tester.pumpAndSettle();

    expect(find.text('No posts cached yet. Tap refresh to sync.'), findsOneWidget);
  });

  testWidgets('renders a tile per cached post', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.postsBySearchId[1] = [_post(id: 1, isSeen: false), _post(id: 2, isSeen: true)];

    await tester.pumpWidget(wrapWithLocalization(PostGridScreen(search: search, repository: repository)));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey(1)), findsOneWidget);
    expect(find.byKey(const ValueKey(2)), findsOneWidget);
  });

  testWidgets('toggling unseen-only filters out seen posts', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.postsBySearchId[1] = [_post(id: 1, isSeen: false), _post(id: 2, isSeen: true)];

    await tester.pumpWidget(wrapWithLocalization(PostGridScreen(search: search, repository: repository)));
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

    await tester.pumpWidget(wrapWithLocalization(PostGridScreen(search: search, repository: repository)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey(1)));
    await tester.pumpAndSettle();

    expect(find.text('Post'), findsOneWidget);
    expect(repository.postsBySearchId[1]!.single.isSeen, isTrue);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Foxes'), findsOneWidget);
  });

  testWidgets('tapping refresh calls syncDueSearches then reloads', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();

    await tester.pumpWidget(wrapWithLocalization(PostGridScreen(search: search, repository: repository)));
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

    await tester.pumpWidget(wrapWithLocalization(PostGridScreen(search: search, repository: repository)));
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

    await tester.pumpWidget(wrapWithLocalization(PostGridScreen(search: search, repository: repository)));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<void>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark all as seen'));
    await tester.pumpAndSettle();

    expect(repository.postsBySearchId[1]!.every((post) => post.isSeen), isTrue);
  });
}
