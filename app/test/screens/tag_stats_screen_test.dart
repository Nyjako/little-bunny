import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/screens/tag_browse_screen.dart';
import 'package:little_bunny/screens/tag_stats_screen.dart';
import 'package:little_bunny/services/download_manager.dart';
import 'package:little_bunny/services/download_queue_service.dart';
import 'package:little_bunny/settings/display_settings_store.dart';
import 'package:little_bunny/settings/download_settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_bunny_repository.dart';
import '../fakes/test_app.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget wrap(FakeBunnyRepository repository) => wrapWithLocalization(
    TagStatsScreen(
      repository: repository,
      displaySettingsStore: const DisplaySettingsStore(),
      downloadSettingsStore: const DownloadSettingsStore(),
      downloadQueueService: DownloadQueueService(downloadManager: const DownloadManager(), downloadSettingsStore: const DownloadSettingsStore()),
    ),
  );

  testWidgets('shows the empty state for every section when the report is empty (M40)', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(FakeBunnyRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Nothing here yet.'), findsNWidgets(4));
  });

  testWidgets('shows a "building" message instead of a timestamp when nothing has been computed yet (M55)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.statsReport = const BunnyStatsReport(computedAt: null, topFavoritedTags: [], topUsedTags: [], topPools: [], topViewedSearches: []);

    await tester.pumpWidget(wrap(repository));
    await tester.pumpAndSettle();

    expect(find.text('Building the report for the first time -- check back shortly.'), findsOneWidget);
    expect(find.textContaining('Updated'), findsNothing);
  });

  testWidgets('lists each section with its own entries and counts (M40)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.statsReport = const BunnyStatsReport(
      computedAt: '2026-01-01T00:00:00Z',
      topFavoritedTags: [BunnyTagStat(name: 'e621: wolf', count: 5)],
      topUsedTags: [BunnyTagStat(name: 'inkbunny: fox', count: 3)],
      topPools: [BunnyTagStat(name: 'pool:5', count: 2)],
      topViewedSearches: [BunnyTagStat(name: 'e621: My search', count: 9)],
    );

    await tester.pumpWidget(wrap(repository));
    await tester.pumpAndSettle();

    expect(find.text('Updated 2026-01-01T00:00:00Z'), findsOneWidget);
    expect(find.text('e621: wolf'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('inkbunny: fox'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Pool #5'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('e621: My search'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
  });

  testWidgets('tapping a merged tag entry opens TagBrowseScreen for its own site, stripped of the prefix', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.statsReport = const BunnyStatsReport(
      computedAt: '2026-01-01T00:00:00Z',
      topFavoritedTags: [BunnyTagStat(name: 'inkbunny: wolf', count: 5)],
      topUsedTags: [],
      topPools: [],
      topViewedSearches: [],
    );

    await tester.pumpWidget(wrap(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('inkbunny: wolf'));
    await tester.pumpAndSettle();

    final browseScreen = tester.widget<TagBrowseScreen>(find.byType(TagBrowseScreen));
    expect(browseScreen.site, BunnySite.inkbunny);
    expect(browseScreen.query, 'wolf');
  });

  testWidgets('tapping a pool entry opens TagBrowseScreen for the pool: query on e621', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.statsReport = const BunnyStatsReport(computedAt: '2026-01-01T00:00:00Z', topFavoritedTags: [], topUsedTags: [], topPools: [BunnyTagStat(name: 'pool:42', count: 1)], topViewedSearches: []);

    await tester.pumpWidget(wrap(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pool #42'));
    await tester.pumpAndSettle();

    final browseScreen = tester.widget<TagBrowseScreen>(find.byType(TagBrowseScreen));
    expect(browseScreen.site, BunnySite.e621);
    expect(browseScreen.query, 'pool:42');
  });

  testWidgets('most-visited searches entries are not tappable (M40)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.statsReport = const BunnyStatsReport(
      computedAt: '2026-01-01T00:00:00Z',
      topFavoritedTags: [],
      topUsedTags: [],
      topPools: [],
      topViewedSearches: [BunnyTagStat(name: 'e621: My search', count: 9)],
    );

    await tester.pumpWidget(wrap(repository));
    await tester.pumpAndSettle();

    final tile = tester.widget<ListTile>(find.widgetWithText(ListTile, 'e621: My search'));
    expect(tile.onTap, isNull);
  });

  testWidgets('the refresh action calls refreshStatsReport and reloads the report (M40)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.statsReport = const BunnyStatsReport(computedAt: '2026-01-01T00:00:00Z', topFavoritedTags: [BunnyTagStat(name: 'e621: wolf', count: 1)], topUsedTags: [], topPools: [], topViewedSearches: []);

    await tester.pumpWidget(wrap(repository));
    await tester.pumpAndSettle();

    repository.statsReport = const BunnyStatsReport(computedAt: '2026-02-01T00:00:00Z', topFavoritedTags: [BunnyTagStat(name: 'e621: fox', count: 2)], topUsedTags: [], topPools: [], topViewedSearches: []);

    // Not pumpAndSettle -- the refresh action shows an indeterminate
    // CircularProgressIndicator while in flight, which never "settles" on
    // its own (it animates forever until the refresh completes and swaps it
    // back out). A couple of bounded pumps is enough to drain the fake
    // repository's microtask-only async gap.
    await tester.tap(find.byTooltip('Refresh now'));
    await tester.pump();
    await tester.pump();

    expect(repository.refreshStatsReportCallCount, 1);
    expect(find.text('e621: fox'), findsOneWidget);
    expect(find.text('Updated 2026-02-01T00:00:00Z'), findsOneWidget);
  });
}
