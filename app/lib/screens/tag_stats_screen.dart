import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../settings/display_settings_store.dart';
import '../settings/download_settings_store.dart';
import 'tag_browse_screen.dart';

/// Shows the unified tag-stats report (M40): top favorited tags, top used
/// tags, top pools (by favorited post count), and most-visited searches.
/// Replaces M10.2/M14.4's per-site/"Favorites vs All" tabbed screen, which
/// ran four full-table aggregate queries fresh on every page open -- that's
/// what hung it. The report is cached server-side for up to 24h
/// ([BunnyRepository.getStatsReport]); the app bar's refresh action forces a
/// recompute ([BunnyRepository.refreshStatsReport]).
class TagStatsScreen extends StatefulWidget {
  final BunnyRepository repository;
  final DisplaySettingsStore displaySettingsStore;
  final DownloadSettingsStore downloadSettingsStore;

  const TagStatsScreen({
    super.key,
    required this.repository,
    required this.displaySettingsStore,
    required this.downloadSettingsStore,
  });

  @override
  State<TagStatsScreen> createState() => _TagStatsScreenState();
}

class _TagStatsScreenState extends State<TagStatsScreen> {
  Future<BunnyStatsReport>? _reportFuture;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _reportFuture = widget.repository.getStatsReport();
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    final future = widget.repository.refreshStatsReport();
    setState(() {
      _reportFuture = future;
    });
    await future;
    if (mounted) {
      setState(() => _refreshing = false);
    }
  }

  /// Splits a merged section's "e621: wolf"/"inkbunny: wolf" entry back into
  /// its site and display name -- the prefix bunny_core's report builder adds
  /// so the same tag/label text on both sites can't collide (M40). Returns
  /// `null` for a name with neither prefix (shouldn't happen for a
  /// server-produced report, but a tap handler silently doing nothing is
  /// safer than crashing on an unexpected shape).
  (BunnySite, String)? _splitSitePrefixedName(String name) {
    const e621Prefix = 'e621: ';
    const inkbunnyPrefix = 'inkbunny: ';
    if (name.startsWith(e621Prefix)) {
      return (BunnySite.e621, name.substring(e621Prefix.length));
    }
    if (name.startsWith(inkbunnyPrefix)) {
      return (BunnySite.inkbunny, name.substring(inkbunnyPrefix.length));
    }
    return null;
  }

  void _openTag(String mergedName) {
    final split = _splitSitePrefixedName(mergedName);
    if (split == null) {
      return;
    }
    final (site, tag) = split;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            TagBrowseScreen(site: site, query: tag, repository: widget.repository, displaySettingsStore: widget.displaySettingsStore, downloadSettingsStore: widget.downloadSettingsStore),
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
        ),
      ),
    );
  }

  Widget _section(AppLocalizations l10n, String title, List<BunnyTagStat> stats, void Function(BunnyTagStat stat)? onTap, String Function(BunnyTagStat stat) label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
        if (stats.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(l10n.tagStatsSectionEmptyState, style: Theme.of(context).textTheme.bodyMedium))
        else
          ...stats.map((stat) => ListTile(title: Text(label(stat)), trailing: Text('${stat.count}'), onTap: onTap == null ? null : () => onTap(stat))),
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
              Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: Text(l10n.tagStatsLastUpdatedLabel(report.computedAt), style: Theme.of(context).textTheme.bodySmall)),
              _section(l10n, l10n.tagStatsTopFavoritedTagsLabel, report.topFavoritedTags, (stat) => _openTag(stat.name), (stat) => stat.name),
              const Divider(height: 1),
              _section(l10n, l10n.tagStatsTopUsedTagsLabel, report.topUsedTags, (stat) => _openTag(stat.name), (stat) => stat.name),
              const Divider(height: 1),
              _section(l10n, l10n.tagStatsTopPoolsLabel, report.topPools, (stat) => _openPool(stat.name), (stat) => l10n.tagBrowseRelatedPoolChip(int.parse(stat.name.substring(5)))),
              const Divider(height: 1),
              _section(l10n, l10n.tagStatsTopViewedSearchesLabel, report.topViewedSearches, null, (stat) => stat.name),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }
}
