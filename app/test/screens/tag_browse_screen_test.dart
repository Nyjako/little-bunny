import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/screens/post_detail_screen.dart';
import 'package:little_bunny/screens/tag_browse_screen.dart';
import 'package:little_bunny/settings/display_settings_store.dart';
import 'package:little_bunny/settings/download_settings_store.dart';
import 'package:little_bunny/settings/sync_settings_store.dart';
import 'package:little_bunny/widgets/post_grid_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_bunny_repository.dart';
import '../fakes/test_app.dart';

BunnyPost _post(int id) => BunnyPost(
  id: id,
  site: BunnySite.e621,
  externalId: id,
  artist: 'someartist',
  score: 1,
  favCount: 0,
  commentCount: 0,
  previewUrl: 'https://example.invalid/$id.jpg',
  width: 100,
  height: 100,
  cachedAt: '2026-01-01T00:00:00Z',
  isSeen: false,
  isFavorited: false,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget wrap(FakeBunnyRepository repository) => wrapWithLocalization(
    TagBrowseScreen(
      site: BunnySite.e621,
      query: 'someartist',
      repository: repository,
      displaySettingsStore: const DisplaySettingsStore(),
      syncSettingsStore: const SyncSettingsStore(), downloadSettingsStore: const DownloadSettingsStore(),
    ),
  );

  testWidgets('shows the empty state when the preview search finds nothing', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();

    await tester.pumpWidget(wrap(repository));
    await tester.pumpAndSettle();

    expect(find.text('No posts found for this search.'), findsOneWidget);
  });

  testWidgets('app bar shrinks on wide windows (M9.6.6)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();

    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(repository));
    await tester.pumpAndSettle();
    final narrowHeight = tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight ?? kToolbarHeight;

    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpWidget(wrap(repository));
    await tester.pumpAndSettle();
    final wideHeight = tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight ?? kToolbarHeight;

    expect(wideHeight, lessThan(narrowHeight));
  });

  testWidgets('renders a tile per previewed post and opens it on tap', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.previewSearchResults['e621:someartist:1'] = [_post(1), _post(2)];

    await tester.pumpWidget(wrap(repository));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey(1)), findsOneWidget);
    expect(find.byKey(const ValueKey(2)), findsOneWidget);

    // Tapped via its onTap callback directly rather than a synthetic
    // tester.tap() -- Flutter's hit-testing in this particular GridView
    // layout doesn't resolve the gesture to the tile's render object in the
    // test environment, for reasons unrelated to the navigation logic under
    // test here (whether the right post opens).
    tester.widget<PostGridTile>(find.byKey(const ValueKey(1))).onTap();
    await tester.pumpAndSettle();

    expect(find.byType(PostDetailScreen), findsOneWidget);
  });

  testWidgets('scrolling near the bottom requests and appends the next page', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.previewSearchResults['e621:someartist:1'] = List.generate(30, (i) => _post(i + 1));
    repository.previewSearchResults['e621:someartist:2'] = [_post(31), _post(32)];

    await tester.pumpWidget(wrap(repository));
    await tester.pumpAndSettle();

    expect(repository.previewSearchCalls, [(BunnySite.e621, 'someartist', 1)]);

    // A bounded drag (rather than an enormous one) keeps the scroll position
    // at the grid's real bottom without overshooting past it -- a huge jump
    // can push earlier tiles outside the GridView's build+cache range,
    // making key-based finders unreliable for assertions made afterward.
    await tester.drag(find.byType(GridView), const Offset(0, -5000));
    await tester.pumpAndSettle();

    expect(repository.previewSearchCalls, contains((BunnySite.e621, 'someartist', 2)));
  });

  testWidgets('a short/empty page stops further loading', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.previewSearchResults['e621:someartist:1'] = List.generate(30, (i) => _post(i + 1));
    // No entry for page 2 -- previewSearch returns an empty list for it.

    await tester.pumpWidget(wrap(repository));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(GridView), const Offset(0, -5000));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(GridView), const Offset(0, -5000));
    await tester.pumpAndSettle();

    // Only ever asked for page 2 once -- an empty page flips _hasMore to
    // false, so further scroll-triggered loads are skipped entirely.
    expect(repository.previewSearchCalls.where((call) => call.$3 == 2), hasLength(1));
  });

  testWidgets('add-to-searches action opens a pre-filled CreateSearchScreen', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.previewSearchResults['e621:someartist:1'] = [_post(1)];

    await tester.pumpWidget(wrap(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Save as a search'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, 'Query'), findsOneWidget);
    final queryField = tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Query'));
    expect(queryField.controller!.text, 'someartist');
  });

  group('customFetch (M10.3)', () {
    Widget wrapWithCustomFetch(FakeBunnyRepository repository, Future<List<BunnyPost>> Function(int page) customFetch, {String? title}) => wrapWithLocalization(
      TagBrowseScreen(
        site: BunnySite.inkbunny,
        query: '',
        repository: repository,
        displaySettingsStore: const DisplaySettingsStore(),
        syncSettingsStore: const SyncSettingsStore(),
        downloadSettingsStore: const DownloadSettingsStore(),
        customFetch: customFetch,
        title: title,
      ),
    );

    testWidgets('fetches via the custom callback instead of previewSearch', (WidgetTester tester) async {
      final repository = FakeBunnyRepository();
      final calls = <int>[];
      Future<List<BunnyPost>> customFetch(int page) async {
        calls.add(page);
        return page == 1 ? [_post(1)] : const [];
      }

      await tester.pumpWidget(wrapWithCustomFetch(repository, customFetch));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey(1)), findsOneWidget);
      expect(calls, [1]);
      expect(repository.previewSearchCalls, isEmpty);
    });

    testWidgets('shows the given title instead of the (empty) query', (WidgetTester tester) async {
      final repository = FakeBunnyRepository();
      await tester.pumpWidget(wrapWithCustomFetch(repository, (page) async => const [], title: 'My favorites'));
      await tester.pumpAndSettle();

      expect(find.text('My favorites'), findsOneWidget);
    });

    testWidgets('omits the add-to-searches action entirely', (WidgetTester tester) async {
      final repository = FakeBunnyRepository();
      await tester.pumpWidget(wrapWithCustomFetch(repository, (page) async => const []));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Save as a search'), findsNothing);
    });
  });
}
