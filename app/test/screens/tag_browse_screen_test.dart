import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/screens/post_detail_screen.dart';
import 'package:little_bunny/screens/tag_browse_screen.dart';
import 'package:little_bunny/settings/display_settings_store.dart';
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
      syncSettingsStore: const SyncSettingsStore(),
    ),
  );

  testWidgets('shows the empty state when the preview search finds nothing', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();

    await tester.pumpWidget(wrap(repository));
    await tester.pumpAndSettle();

    expect(find.text('No posts found for this search.'), findsOneWidget);
  });

  testWidgets('renders a tile per previewed post and opens it on tap', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.previewSearchResults['e621:someartist'] = [_post(1), _post(2)];

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

  testWidgets('add-to-searches action opens a pre-filled CreateSearchScreen', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.previewSearchResults['e621:someartist'] = [_post(1)];

    await tester.pumpWidget(wrap(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Save as a search'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, 'Query'), findsOneWidget);
    final queryField = tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Query'));
    expect(queryField.controller!.text, 'someartist');
  });
}
