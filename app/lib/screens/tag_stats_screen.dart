import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../settings/display_settings_store.dart';
import '../settings/download_settings_store.dart';
import 'tag_browse_screen.dart';

/// Shows the most-favorited tags per site (M10.2), reusing [BunnyTagStat]
/// as-is -- the same shape [CreateSearchScreen]'s autocomplete already uses.
/// Tapping a tag is the "recommended search": it opens [TagBrowseScreen],
/// which already has its own "add to searches" action, so no separate
/// recommendation/save flow is built here -- the tag itself is the
/// recommendation. e621/Inkbunny tags are tracked as distinct rows
/// (`tags` is `UNIQUE(site, name)`), so results are switched per site via a
/// [SegmentedButton] rather than shown as one ambiguous merged list.
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
  BunnySite _site = BunnySite.e621;

  /// Whether to rank only favorited posts' tags (M10.2's original behavior)
  /// or every synced post's tags (M14.4).
  bool _favoritesOnly = true;
  Future<List<BunnyTagStat>>? _statsFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _statsFuture = _favoritesOnly ? widget.repository.topFavoritedTags(_site) : widget.repository.topUsedTags(_site);
  }

  void _openTag(BunnyTagStat stat) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TagBrowseScreen(
          site: _site,
          query: stat.name,
          repository: widget.repository,
          displaySettingsStore: widget.displaySettingsStore,
          downloadSettingsStore: widget.downloadSettingsStore,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tagStatsScreenTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<BunnySite>(
              segments: const [ButtonSegment(value: BunnySite.e621, label: Text('e621')), ButtonSegment(value: BunnySite.inkbunny, label: Text('Inkbunny'))],
              selected: {_site},
              onSelectionChanged: (selection) => setState(() {
                _site = selection.first;
                _load();
              }),
            ),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: [ButtonSegment(value: true, label: Text(l10n.tagStatsFavoritesLabel)), ButtonSegment(value: false, label: Text(l10n.tagStatsAllLabel))],
              selected: {_favoritesOnly},
              onSelectionChanged: (selection) => setState(() {
                _favoritesOnly = selection.first;
                _load();
              }),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: FutureBuilder<List<BunnyTagStat>>(
                future: _statsFuture,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final stats = snapshot.data!;
                  if (stats.isEmpty) {
                    return Center(child: Text(_favoritesOnly ? l10n.tagStatsEmptyState : l10n.tagStatsAllEmptyState));
                  }
                  return ListView.builder(
                    itemCount: stats.length,
                    itemBuilder: (context, index) {
                      final stat = stats[index];
                      return ListTile(title: Text(stat.name), trailing: Text('${stat.count}'), onTap: () => _openTag(stat));
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
