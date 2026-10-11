import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/screens/tag_browse_screen.dart';
import 'package:little_bunny/screens/tag_stats_screen.dart';
import 'package:little_bunny/settings/display_settings_store.dart';
import 'package:little_bunny/settings/download_settings_store.dart';
import 'package:little_bunny/settings/sync_settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_bunny_repository.dart';
import '../fakes/test_app.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget wrap(FakeBunnyRepository repository) => wrapWithLocalization(
    TagStatsScreen(repository: repository, displaySettingsStore: const DisplaySettingsStore(), syncSettingsStore: const SyncSettingsStore(), downloadSettingsStore: const DownloadSettingsStore()),
  );

  testWidgets('shows the empty state when nothing is favorited', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(FakeBunnyRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No favorited posts yet -- favorite some to see their tags here.'), findsOneWidget);
  });

  testWidgets('lists the top favorited tags for the selected site, with counts', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.topFavoritedTagsBySite[BunnySite.e621] = const [BunnyTagStat(name: 'wolf', count: 5), BunnyTagStat(name: 'forest', count: 2)];

    await tester.pumpWidget(wrap(repository));
    await tester.pumpAndSettle();

    expect(find.text('wolf'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('forest'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('switching site reloads the list for that site (M10.2)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.topFavoritedTagsBySite[BunnySite.e621] = const [BunnyTagStat(name: 'wolf', count: 5)];
    repository.topFavoritedTagsBySite[BunnySite.inkbunny] = const [BunnyTagStat(name: 'fox', count: 3)];

    await tester.pumpWidget(wrap(repository));
    await tester.pumpAndSettle();
    expect(find.text('wolf'), findsOneWidget);
    expect(find.text('fox'), findsNothing);

    await tester.tap(find.text('Inkbunny'));
    await tester.pumpAndSettle();

    expect(find.text('fox'), findsOneWidget);
    expect(find.text('wolf'), findsNothing);
  });

  testWidgets('switching to "All" shows tags from every synced post, not just favorited ones (M14.4)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.topFavoritedTagsBySite[BunnySite.e621] = const [BunnyTagStat(name: 'wolf', count: 5)];
    repository.topUsedTagsBySite[BunnySite.e621] = const [BunnyTagStat(name: 'wolf', count: 5), BunnyTagStat(name: 'forest', count: 9)];

    await tester.pumpWidget(wrap(repository));
    await tester.pumpAndSettle();
    expect(find.text('forest'), findsNothing);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    expect(find.text('wolf'), findsOneWidget);
    expect(find.text('forest'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
  });

  testWidgets('shows the "All" empty state when nothing is synced (M14.4)', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(FakeBunnyRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    expect(find.text('No synced posts yet -- sync a search to see their tags here.'), findsOneWidget);
  });

  testWidgets('tapping a tag opens TagBrowseScreen for it on the selected site', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.topFavoritedTagsBySite[BunnySite.e621] = const [BunnyTagStat(name: 'wolf', count: 5)];

    await tester.pumpWidget(wrap(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('wolf'));
    await tester.pumpAndSettle();

    final browseScreen = tester.widget<TagBrowseScreen>(find.byType(TagBrowseScreen));
    expect(browseScreen.site, BunnySite.e621);
    expect(browseScreen.query, 'wolf');
  });
}
