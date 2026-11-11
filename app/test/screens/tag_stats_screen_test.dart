import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/screens/tag_browse_screen.dart';
import 'package:little_bunny/screens/tag_stats_screen.dart';
import 'package:little_bunny/services/download_manager.dart';
import 'package:little_bunny/services/download_queue_service.dart';
import 'package:little_bunny/services/preview_cache_service.dart';
import 'package:little_bunny/settings/display_settings_store.dart';
import 'package:little_bunny/settings/download_settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_bunny_repository.dart';
import '../fakes/test_app.dart';

/// 11 entries -- one past [TagStatsScreen]'s own 10-entry chart cutoff, so
/// the 11th always lands in the plain overflow list (still a real,
/// tappable `ListTile`), the only part of a charted section this file can
/// reliably assert on without simulating a touch at fl_chart's own
/// internal bar coordinates (never verified visually in this environment --
/// see this file's own note further down).
List<BunnyTagStat> _elevenTags(String prefix) => List.generate(11, (i) => BunnyTagStat(name: '$prefix: tag$i', count: 11 - i));

void main() {
  late PreviewCacheService previewCacheService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    previewCacheService = PreviewCacheService();
  });

  Widget wrap(FakeBunnyRepository repository) => wrapWithLocalization(
    TagStatsScreen(
      repository: repository,
      displaySettingsStore: const DisplaySettingsStore(),
      downloadSettingsStore: const DownloadSettingsStore(),
      downloadQueueService: DownloadQueueService(downloadManager: const DownloadManager(), downloadSettingsStore: const DownloadSettingsStore()),
      previewCacheService: previewCacheService,
    ),
  );

  testWidgets('shows the empty state for every section (recommendations + all four charted ones) when the report is empty (M40/M72)', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(FakeBunnyRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Nothing here yet.'), findsNWidgets(5));
  });

  testWidgets('shows a "building" message instead of a timestamp when nothing has been computed yet (M55)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.statsReport = const BunnyStatsReport(computedAt: null, topFavoritedTags: [], topUsedTags: [], topPools: [], topViewedSearches: [], topTagPairs: []);

    await tester.pumpWidget(wrap(repository));
    await tester.pumpAndSettle();

    expect(find.text('Building the report for the first time -- check back shortly.'), findsOneWidget);
    expect(find.textContaining('Updated'), findsNothing);
  });

  testWidgets('a section with entries renders a chart plus the last-updated timestamp (M40/M72)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.statsReport = BunnyStatsReport(
      computedAt: '2026-01-01T00:00:00Z',
      topFavoritedTags: [const BunnyTagStat(name: 'e621: wolf', count: 5)],
      topUsedTags: const [],
      topPools: const [],
      topViewedSearches: const [],
      topTagPairs: const [],
    );

    await tester.pumpWidget(wrap(repository));
    await tester.pumpAndSettle();

    expect(find.text('Updated 2026-01-01T00:00:00Z'), findsOneWidget);
    expect(find.byType(BarChart), findsOneWidget);
  });

  testWidgets('an 11th entry spills into the plain overflow list below the chart, and tapping it still opens TagBrowseScreen (M72)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.statsReport = BunnyStatsReport(computedAt: '2026-01-01T00:00:00Z', topFavoritedTags: _elevenTags('inkbunny'), topUsedTags: const [], topPools: const [], topViewedSearches: const [], topTagPairs: const []);

    await tester.pumpWidget(wrap(repository));
    await tester.pumpAndSettle();

    expect(find.text('inkbunny: tag10'), findsOneWidget); // the 11th entry (index 10), only in the overflow list

    await tester.ensureVisible(find.text('inkbunny: tag10'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('inkbunny: tag10'));
    await tester.pumpAndSettle();

    final browseScreen = tester.widget<TagBrowseScreen>(find.byType(TagBrowseScreen));
    expect(browseScreen.site, BunnySite.inkbunny);
    expect(browseScreen.query, 'tag10');
  });

  testWidgets('an overflow pool entry opens TagBrowseScreen for the pool: query on e621', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final pools = List.generate(11, (i) => BunnyTagStat(name: 'pool:${i + 1}', count: 11 - i));
    repository.statsReport = BunnyStatsReport(computedAt: '2026-01-01T00:00:00Z', topFavoritedTags: const [], topUsedTags: const [], topPools: pools, topViewedSearches: const [], topTagPairs: const []);

    await tester.pumpWidget(wrap(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pool #11'));
    await tester.pumpAndSettle();

    final browseScreen = tester.widget<TagBrowseScreen>(find.byType(TagBrowseScreen));
    expect(browseScreen.site, BunnySite.e621);
    expect(browseScreen.query, 'pool:11');
  });

  testWidgets('an overflow most-visited-searches entry is not tappable (M40)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.statsReport = BunnyStatsReport(computedAt: '2026-01-01T00:00:00Z', topFavoritedTags: const [], topUsedTags: const [], topPools: const [], topViewedSearches: _elevenTags('e621'), topTagPairs: const []);

    await tester.pumpWidget(wrap(repository));
    await tester.pumpAndSettle();

    final tile = tester.widget<ListTile>(find.widgetWithText(ListTile, 'e621: tag10'));
    expect(tile.onTap, isNull);
  });

  testWidgets('the refresh action calls refreshStatsReport and reloads the report (M40)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.statsReport = const BunnyStatsReport(computedAt: '2026-01-01T00:00:00Z', topFavoritedTags: [BunnyTagStat(name: 'e621: wolf', count: 1)], topUsedTags: [], topPools: [], topViewedSearches: [], topTagPairs: []);

    await tester.pumpWidget(wrap(repository));
    await tester.pumpAndSettle();

    repository.statsReport = const BunnyStatsReport(computedAt: '2026-02-01T00:00:00Z', topFavoritedTags: [BunnyTagStat(name: 'e621: fox', count: 2)], topUsedTags: [], topPools: [], topViewedSearches: [], topTagPairs: []);

    // Not pumpAndSettle -- the refresh action shows an indeterminate
    // CircularProgressIndicator while in flight, which never "settles" on
    // its own (it animates forever until the refresh completes and swaps it
    // back out). A couple of bounded pumps is enough to drain the fake
    // repository's microtask-only async gap.
    await tester.tap(find.byTooltip('Refresh now'));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Updated 2026-02-01T00:00:00Z'), findsOneWidget);
  });

  group('recommended searches (M72)', () {
    testWidgets('a tag pair not yet covered by an existing search shows up as a recommendation', (WidgetTester tester) async {
      final repository = FakeBunnyRepository();
      repository.statsReport = const BunnyStatsReport(
        computedAt: '2026-01-01T00:00:00Z',
        topFavoritedTags: [],
        topUsedTags: [],
        topPools: [],
        topViewedSearches: [],
        topTagPairs: [BunnyTagStat(name: 'e621: forest + wolf', count: 7)],
      );

      await tester.pumpWidget(wrap(repository));
      await tester.pumpAndSettle();

      expect(find.text('forest + wolf'), findsOneWidget);
      expect(find.text('7 favorites'), findsOneWidget);
    });

    testWidgets('a pair already covered by an existing search (any tag order) is not recommended', (WidgetTester tester) async {
      final repository = FakeBunnyRepository();
      repository.searches.add(BunnySearch(id: 1, site: BunnySite.e621, label: 'mine', query: 'wolf forest', intervalHours: 24, createdAt: '2026-01-01T00:00:00Z'));
      repository.statsReport = const BunnyStatsReport(
        computedAt: '2026-01-01T00:00:00Z',
        topFavoritedTags: [],
        topUsedTags: [],
        topPools: [],
        topViewedSearches: [],
        topTagPairs: [BunnyTagStat(name: 'e621: forest + wolf', count: 7)],
      );

      await tester.pumpWidget(wrap(repository));
      await tester.pumpAndSettle();

      expect(find.text('forest + wolf'), findsNothing);
      expect(find.text('Nothing here yet.'), findsNWidgets(5)); // the deduped recommendation plus all four (empty) charted sections
    });

    testWidgets('tapping a recommendation opens a live preview with the shared preview cache, not a save', (WidgetTester tester) async {
      final repository = FakeBunnyRepository();
      repository.statsReport = const BunnyStatsReport(
        computedAt: '2026-01-01T00:00:00Z',
        topFavoritedTags: [],
        topUsedTags: [],
        topPools: [],
        topViewedSearches: [],
        topTagPairs: [BunnyTagStat(name: 'e621: forest + wolf', count: 7)],
      );

      await tester.pumpWidget(wrap(repository));
      await tester.pumpAndSettle();

      await tester.tap(find.text('forest + wolf'));
      await tester.pumpAndSettle();

      final browseScreen = tester.widget<TagBrowseScreen>(find.byType(TagBrowseScreen));
      expect(browseScreen.site, BunnySite.e621);
      expect(browseScreen.query, 'forest wolf');
      expect(browseScreen.previewCache, same(previewCacheService));
    });

    testWidgets('prefetches every shown recommendation in the background', (WidgetTester tester) async {
      final repository = FakeBunnyRepository();
      repository.previewSearchResults['e621:forest wolf:1'] = const [];
      repository.statsReport = const BunnyStatsReport(
        computedAt: '2026-01-01T00:00:00Z',
        topFavoritedTags: [],
        topUsedTags: [],
        topPools: [],
        topViewedSearches: [],
        topTagPairs: [BunnyTagStat(name: 'e621: forest + wolf', count: 7)],
      );

      await tester.pumpWidget(wrap(repository));
      await tester.pumpAndSettle();

      expect(repository.previewSearchCalls, contains((BunnySite.e621, 'forest wolf', 1)));
    });
  });
}
