import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../services/download_queue_service.dart';
import '../services/preview_cache_service.dart';
import '../services/search_recommendations.dart';
import '../settings/display_settings_store.dart';
import '../settings/download_settings_store.dart';
import '../util/site_prefixed_name.dart';
import 'tag_browse_screen.dart';

/// Shows the unified tag-stats report (M40): top favorited tags, top used
/// tags, top pools (by favorited post count), and most-visited searches, each
/// as a bar chart for its top 10 entries (M72) with the rest available as a
/// plain ranked list underneath. A "Recommended searches" section up top
/// (M72) suggests tag pairs that co-occur on favorited posts -- beyond
/// M10.2's original "the tag itself is the recommendation" stance -- filtered
/// against searches already saved, via [buildSearchRecommendations]; tapping
/// one opens a live preview ([TagBrowseScreen]) rather than saving it
/// outright, and [PreviewCacheService.prefetch] warms that preview's first
/// page in the background as soon as the recommendations are computed, so
/// opening it feels close to instant.
///
/// Replaces M10.2/M14.4's per-site/"Favorites vs All" tabbed screen, which
/// ran four full-table aggregate queries fresh on every page open -- that's
/// what hung it. The report is cached for up to 24h; as of M55, both
/// loading the screen ([BunnyRepository.getStatsReport]) and the app bar's
/// refresh action ([BunnyRepository.refreshStatsReport]) only ever show
/// whatever's cached right now rather than waiting for a fresh build, so
/// [BunnyStatsReport.computedAt] can come back null the very first time
/// (nothing built yet) -- the screen shows [AppLocalizations.
/// tagStatsBuildingLabel] instead of a timestamp in that case, and the user
/// is expected to just come back to this screen later to see the result,
/// same as any other background job in this app.
class TagStatsScreen extends StatefulWidget {
  final BunnyRepository repository;
  final DisplaySettingsStore displaySettingsStore;
  final DownloadSettingsStore downloadSettingsStore;
  final DownloadQueueService downloadQueueService;
  final PreviewCacheService previewCacheService;

  const TagStatsScreen({
    super.key,
    required this.repository,
    required this.displaySettingsStore,
    required this.downloadSettingsStore,
    required this.downloadQueueService,
    required this.previewCacheService,
  });

  @override
  State<TagStatsScreen> createState() => _TagStatsScreenState();
}

/// Only the top this many entries of a section get a chart bar -- the rest
/// (up to [BunnyStatsReport]'s own 20-entry cap) stay available as a plain
/// ranked list underneath, so no data disappears, just the visual treatment.
const _chartedEntryCount = 10;

class _TagStatsScreenState extends State<TagStatsScreen> {
  Future<BunnyStatsReport>? _reportFuture;
  bool _refreshing = false;

  /// Built once both the report and the existing searches resolve (see
  /// [_loadRecommendations]) -- empty until then, same "just show nothing
  /// yet" treatment every other section already gives a still-loading list.
  List<RecommendedSearch> _recommendations = const [];

  /// Guards against re-triggering [PreviewCacheService.prefetch] for the
  /// same recommendations on every rebuild -- set once, right after they're
  /// first computed for this screen instance.
  bool _prefetchedRecommendations = false;

  @override
  void initState() {
    super.initState();
    _reportFuture = widget.repository.getStatsReport();
    _loadRecommendations();
  }

  Future<void> _loadRecommendations() async {
    final report = await _reportFuture;
    final existingSearches = await widget.repository.listSearches();
    if (!mounted || report == null) {
      return;
    }
    final recommendations = buildSearchRecommendations(report, existingSearches);
    setState(() => _recommendations = recommendations);
    if (!_prefetchedRecommendations) {
      _prefetchedRecommendations = true;
      for (final recommendation in recommendations) {
        widget.previewCacheService.prefetch(widget.repository, recommendation.site, recommendation.query);
      }
    }
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    final future = widget.repository.refreshStatsReport();
    setState(() {
      _reportFuture = future;
      _prefetchedRecommendations = false;
    });
    await future;
    if (!mounted) {
      return;
    }
    setState(() => _refreshing = false);
    await _loadRecommendations();
  }

  void _openTag(String mergedName) {
    final split = splitSitePrefixedName(mergedName);
    if (split == null) {
      return;
    }
    final (site, tag) = split;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TagBrowseScreen(
          site: site,
          query: tag,
          repository: widget.repository,
          displaySettingsStore: widget.displaySettingsStore,
          downloadSettingsStore: widget.downloadSettingsStore,
          downloadQueueService: widget.downloadQueueService,
        ),
      ),
    );
  }

  void _openPool(String poolQuery) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TagBrowseScreen(
          site: BunnySite.e621,
          query: poolQuery,
          repository: widget.repository,
          displaySettingsStore: widget.displaySettingsStore,
          downloadSettingsStore: widget.downloadSettingsStore,
          downloadQueueService: widget.downloadQueueService,
        ),
      ),
    );
  }

  /// Opens a live preview, not a save -- the user decides whether to add it
  /// via [TagBrowseScreen]'s own existing "+" action, same flow as tapping
  /// any other tag/pool elsewhere in the app. [PreviewCacheService.
  /// previewCacheService] lets page 1 come back instantly if
  /// [_loadRecommendations] already warmed it.
  void _openRecommendation(RecommendedSearch recommendation) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TagBrowseScreen(
          site: recommendation.site,
          query: recommendation.query,
          repository: widget.repository,
          displaySettingsStore: widget.displaySettingsStore,
          downloadSettingsStore: widget.downloadSettingsStore,
          downloadQueueService: widget.downloadQueueService,
          previewCache: widget.previewCacheService,
        ),
      ),
    );
  }

  Widget _recommendationsSection(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text(l10n.tagStatsRecommendedSearchesLabel, style: Theme.of(context).textTheme.titleMedium)),
        if (_recommendations.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(l10n.tagStatsSectionEmptyState, style: Theme.of(context).textTheme.bodyMedium))
        else
          ..._recommendations.map(
            (recommendation) => ListTile(
              title: Text(recommendation.label),
              subtitle: Text(l10n.tagStatsRecommendationCountLabel(recommendation.count)),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => _openRecommendation(recommendation),
            ),
          ),
      ],
    );
  }

  Widget _barChart(List<BunnyTagStat> charted, void Function(BunnyTagStat stat)? onTap) {
    final color = Theme.of(context).colorScheme.primary;
    final maxCount = charted.map((stat) => stat.count).reduce(math.max);
    return SizedBox(
      height: 180,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
        child: BarChart(
          BarChartData(
            maxY: maxCount * 1.2,
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index < 0 || index >= charted.length) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Transform.rotate(
                        alignment: Alignment.topCenter,
                        angle: -math.pi / 5,
                        child: Text(charted[index].name, style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis),
                      ),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchCallback: onTap == null
                  ? null
                  : (event, response) {
                      if (event is! FlTapUpEvent) {
                        return;
                      }
                      final index = response?.spot?.touchedBarGroupIndex;
                      if (index == null || index < 0 || index >= charted.length) {
                        return;
                      }
                      onTap(charted[index]);
                    },
            ),
            barGroups: [
              for (var i = 0; i < charted.length; i++) BarChartGroupData(x: i, barRods: [BarChartRodData(toY: charted[i].count.toDouble(), color: color, width: 16)]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _overflowList(List<BunnyTagStat> overflow, void Function(BunnyTagStat stat)? onTap, String Function(BunnyTagStat stat) label) {
    return Column(children: overflow.map((stat) => ListTile(title: Text(label(stat)), trailing: Text('${stat.count}'), onTap: onTap == null ? null : () => onTap(stat))).toList(growable: false));
  }

  Widget _chartSection(AppLocalizations l10n, String title, List<BunnyTagStat> stats, void Function(BunnyTagStat stat)? onTap, String Function(BunnyTagStat stat) label) {
    final charted = stats.take(_chartedEntryCount).toList(growable: false);
    final overflow = stats.length > _chartedEntryCount ? stats.sublist(_chartedEntryCount) : const <BunnyTagStat>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
        if (stats.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(l10n.tagStatsSectionEmptyState, style: Theme.of(context).textTheme.bodyMedium))
        else ...[
          _barChart(charted, onTap == null ? null : (stat) => onTap(stat)),
          _overflowList(overflow, onTap, (stat) => label(stat)),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tagStatsScreenTitle),
        actions: [
          _refreshing
              ? const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
              : IconButton(icon: const Icon(Icons.refresh), tooltip: l10n.tagStatsRefreshTooltip, onPressed: _refresh),
        ],
      ),
      body: FutureBuilder<BunnyStatsReport>(
        future: _reportFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final report = snapshot.data!;
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  report.computedAt == null ? l10n.tagStatsBuildingLabel : l10n.tagStatsLastUpdatedLabel(report.computedAt!),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              _recommendationsSection(l10n),
              const Divider(height: 1),
              _chartSection(l10n, l10n.tagStatsTopFavoritedTagsLabel, report.topFavoritedTags, (stat) => _openTag(stat.name), (stat) => stat.name),
              const Divider(height: 1),
              _chartSection(l10n, l10n.tagStatsTopUsedTagsLabel, report.topUsedTags, (stat) => _openTag(stat.name), (stat) => stat.name),
              const Divider(height: 1),
              _chartSection(l10n, l10n.tagStatsTopPoolsLabel, report.topPools, (stat) => _openPool(stat.name), (stat) => l10n.tagBrowseRelatedPoolChip(int.parse(stat.name.substring(5)))),
              const Divider(height: 1),
              _chartSection(l10n, l10n.tagStatsTopViewedSearchesLabel, report.topViewedSearches, null, (stat) => stat.name),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }
}
