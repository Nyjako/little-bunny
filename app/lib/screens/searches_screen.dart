import 'package:flutter/material.dart';

import '../bunny_repository_scope.dart';
import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../settings/app_lock_service.dart';
import '../settings/display_settings_store.dart';
import '../settings/download_settings_store.dart';
import '../settings/sync_settings_store.dart';
import '../settings/theme_settings_store.dart';
import '../util/responsive.dart';
import 'accounts_screen.dart';
import 'create_search_screen.dart';
import 'edit_search_screen.dart';
import 'post_grid_screen.dart';
import 'settings_screen.dart';
import 'tag_stats_screen.dart';

/// The app's actual home screen (M8.2 promoted this over [AccountsScreen] --
/// browse/search is the daily-use surface, site login is a one-time setup
/// concern). Lists saved searches; each will open a post grid (M8.3) once
/// that exists.
class SearchesScreen extends StatefulWidget {
  final AppLockService lockService;
  final ThemeSettingsStore themeSettingsStore;
  final SyncSettingsStore syncSettingsStore;
  final DisplaySettingsStore displaySettingsStore;
  final DownloadSettingsStore downloadSettingsStore;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  const SearchesScreen({
    super.key,
    required this.lockService,
    required this.themeSettingsStore,
    required this.syncSettingsStore,
    required this.displaySettingsStore,
    required this.downloadSettingsStore,
    required this.onThemeModeChanged,
  });

  @override
  State<SearchesScreen> createState() => _SearchesScreenState();
}

/// e621's own tag-search syntax treats `pool:<id>` as a literal query string
/// -- `bunny_core_search_create(site: e621, query: 'pool:$id')` already works
/// today with no new backend logic, so a "pool search" is just a regular
/// [BunnySearch] with a recognizable query shape, filtered into its own tab.
bool _isPoolSearch(BunnySearch search) => search.site == BunnySite.e621 && search.query.startsWith('pool:');

class _SearchesScreenState extends State<SearchesScreen> with SingleTickerProviderStateMixin {
  BunnyRepository? _repository;
  Future<List<BunnySearch>>? _searchesFuture;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)..addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _repository = BunnyRepositoryScope.of(context);
    _searchesFuture ??= _repository!.listSearches();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _searchesFuture = _repository!.listSearches();
    });
  }

  Future<void> _createSearch() async {
    final created = await Navigator.push<bool>(context, MaterialPageRoute(builder: (context) => CreateSearchScreen(repository: _repository!, syncSettingsStore: widget.syncSettingsStore)));
    if (created == true) {
      _refresh();
    }
  }

  Future<void> _createPoolSearch() async {
    final l10n = AppLocalizations.of(context)!;
    final poolIdText = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: Text(l10n.createPoolSearchDialogTitle),
          content: TextField(controller: controller, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: l10n.createPoolSearchIdLabel), autofocus: true),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonCancel)),
            TextButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(l10n.createPoolSearchSubmit)),
          ],
        );
      },
    );
    final poolId = poolIdText == null ? null : int.tryParse(poolIdText);
    if (poolId == null) {
      return;
    }

    // The pool's own name makes a far more useful label than the raw id, but
    // this works purely as a nice-to-have -- a failed lookup (network error,
    // deleted pool, etc.) still creates a perfectly functional pool search
    // with a fallback label, rather than blocking the whole action on it.
    String label = 'pool:$poolId';
    try {
      final info = await _repository!.fetchPool(poolId);
      if (info.name != null && info.name!.isNotEmpty) {
        label = info.name!;
      }
    } catch (_) {
      // Fall back to the default label above.
    }

    await _repository!.createSearch(BunnySite.e621, label, 'pool:$poolId');
    _refresh();
  }

  Future<void> _removeSearch(BunnySearch search) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.searchesRemoveDialogTitle),
        content: Text(l10n.searchesRemoveDialogContent(search.label)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.commonCancel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.commonRemove)),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await _repository!.deleteSearch(search.id);
    _refresh();
  }

  Future<void> _editSearch(BunnySearch search) async {
    final updated = await Navigator.push<bool>(context, MaterialPageRoute(builder: (context) => EditSearchScreen(repository: _repository!, search: search)));
    if (updated == true) {
      _refresh();
    }
  }

  Widget _searchList(List<BunnySearch> searches, String emptyState) {
    final l10n = AppLocalizations.of(context)!;
    if (searches.isEmpty) {
      return Center(child: Text(emptyState));
    }
    return ListView(
      children: searches
          .map(
            (search) => ListTile(
              title: Text(search.label),
              subtitle: Text(l10n.searchesIntervalSubtitle(search.site.toWireString(), search.intervalHours)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (search.unseenCount > 0)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(12)),
                      child: Text('${search.unseenCount}', style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontSize: 12)),
                    ),
                  IconButton(icon: const Icon(Icons.delete), onPressed: () => _removeSearch(search)),
                ],
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      PostGridScreen(search: search, repository: _repository!, displaySettingsStore: widget.displaySettingsStore, syncSettingsStore: widget.syncSettingsStore, downloadSettingsStore: widget.downloadSettingsStore),
                ),
              ),
              onLongPress: () => _editSearch(search),
            ),
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final onPoolsTab = _tabController.index == 1;
    final wide = isWideScreen(context);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: wide ? compactToolbarHeight : null,
        title: Text(l10n.searchesScreenTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: l10n.searchesAccountsTooltip,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AccountsScreen(
                  repository: _repository!,
                  displaySettingsStore: widget.displaySettingsStore,
                  syncSettingsStore: widget.syncSettingsStore,
                  downloadSettingsStore: widget.downloadSettingsStore,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart_outlined),
            tooltip: l10n.searchesTagStatsTooltip,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => TagStatsScreen(
                  repository: _repository!,
                  displaySettingsStore: widget.displaySettingsStore,
                  syncSettingsStore: widget.syncSettingsStore,
                  downloadSettingsStore: widget.downloadSettingsStore,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.searchesSettingsTooltip,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SettingsScreen(
                  themeSettingsStore: widget.themeSettingsStore,
                  lockService: widget.lockService,
                  syncSettingsStore: widget.syncSettingsStore,
                  displaySettingsStore: widget.displaySettingsStore,
                  downloadSettingsStore: widget.downloadSettingsStore,
                  onThemeModeChanged: widget.onThemeModeChanged,
                ),
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelPadding: wide ? const EdgeInsets.symmetric(horizontal: 16, vertical: 4) : null,
          tabs: [Tab(text: l10n.searchesTabSearches), Tab(text: l10n.searchesTabPools)],
        ),
      ),
      body: FutureBuilder<List<BunnySearch>>(
        future: _searchesFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snapshot.data!;
          final searches = all.where((search) => !_isPoolSearch(search)).toList();
          final pools = all.where(_isPoolSearch).toList();
          return TabBarView(controller: _tabController, children: [_searchList(searches, l10n.searchesEmptyState), _searchList(pools, l10n.searchesPoolsEmptyState)]);
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: onPoolsTab ? _createPoolSearch : _createSearch,
        tooltip: onPoolsTab ? l10n.searchesNewPoolTooltip : l10n.searchesNewSearchTooltip,
        child: const Icon(Icons.add),
      ),
    );
  }
}
