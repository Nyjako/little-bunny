import 'dart:async';

import 'package:flutter/material.dart';

import '../bunny_repository_scope.dart';
import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../settings/app_lock_service.dart';
import '../settings/display_settings_store.dart';
import '../settings/download_settings_store.dart';
import '../settings/repository_settings_store.dart';
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
  final RepositorySettingsStore settingsStore;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<BunnyRepository> onRepositoryConfigured;

  const SearchesScreen({
    super.key,
    required this.lockService,
    required this.themeSettingsStore,
    required this.syncSettingsStore,
    required this.displaySettingsStore,
    required this.downloadSettingsStore,
    required this.settingsStore,
    required this.onThemeModeChanged,
    required this.onRepositoryConfigured,
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
  SearchSortOrder _sortOrder = SearchSortOrder.mostUnseen;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)..addListener(() => setState(() {}));
    _loadSortOrder();
  }

  Future<void> _loadSortOrder() async {
    final order = await widget.displaySettingsStore.loadSearchSortOrder();
    if (mounted) {
      setState(() => _sortOrder = order);
    }
  }

  Future<void> _setSortOrder(SearchSortOrder order) async {
    setState(() => _sortOrder = order);
    await widget.displaySettingsStore.saveSearchSortOrder(order);
  }

  List<BunnySearch> _sorted(List<BunnySearch> searches) {
    void sortBy(List<BunnySearch> list) {
      switch (_sortOrder) {
        case SearchSortOrder.mostUnseen:
          list.sort((a, b) => b.unseenCount.compareTo(a.unseenCount));
        case SearchSortOrder.label:
          list.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
        case SearchSortOrder.recentlyCreated:
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        case SearchSortOrder.lastViewed:
          list.sort((a, b) => (b.lastViewedAt ?? '').compareTo(a.lastViewedAt ?? ''));
      }
    }

    // Pinned searches always come first (M14.1), each group internally
    // ordered by the usual sort choice.
    final pinned = searches.where((search) => search.pinned).toList();
    final unpinned = searches.where((search) => !search.pinned).toList();
    sortBy(pinned);
    sortBy(unpinned);
    return [...pinned, ...unpinned];
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

  /// Non-null only while [_checkForUpdates]'s loop is running -- same
  /// `(done, total)` shape `PostGridScreen._massDownloadProgress` uses
  /// (M9.5), swapped into the app bar title the same way that screen swaps
  /// it into its own title.
  (int, int)? _syncAllProgress;

  /// Forces every saved search to sync right now (M13.2), ignoring each
  /// search's own due-interval -- unlike the scheduled/manual batch sync
  /// (`syncDueSearches`), this syncs one search at a time so progress can
  /// be shown, and keeps going past a single search's failure (network
  /// error, etc.) rather than aborting the whole run. Refreshes the list
  /// after every search (not just once at the end) so unseen-count badges
  /// update live and nothing is lost if the run is interrupted partway
  /// through (M14.3).
  Future<void> _checkForUpdates() async {
    final searches = await _repository!.listSearches();
    if (searches.isEmpty) {
      return;
    }
    setState(() => _syncAllProgress = (0, searches.length));
    for (var i = 0; i < searches.length; i++) {
      try {
        await _repository!.syncSearch(searches[i].id);
      } catch (_) {
        // Leave it and move on -- same tolerance the scheduled sync already
        // has for a single search failing.
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _syncAllProgress = (i + 1, searches.length);
        _searchesFuture = _repository!.listSearches();
      });
    }
    if (!mounted) {
      return;
    }
    setState(() => _syncAllProgress = null);
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

  Future<void> _togglePin(BunnySearch search) async {
    await _repository!.setSearchPinned(search.id, !search.pinned);
    _refresh();
  }

  /// Which searches currently have a per-row sync in flight (M14.1) -- a set
  /// rather than a single flag, since multiple rows can be synced
  /// independently and concurrently, unlike the single sequential "check
  /// for updates" app bar action above.
  final Set<int> _syncingSearchIds = {};

  Future<void> _syncOneSearch(BunnySearch search) async {
    setState(() => _syncingSearchIds.add(search.id));
    try {
      await _repository!.syncSearch(search.id);
    } catch (_) {
      // Same tolerance as "check for updates" -- leave it, the user can
      // retry the single row.
    }
    if (!mounted) {
      return;
    }
    setState(() => _syncingSearchIds.remove(search.id));
    _refresh();
  }

  /// Records the open (fire-and-forget -- shouldn't delay navigation) for the
  /// "last viewed" sort order, then awaits the post grid so returning from it
  /// re-sorts the list and the reordering is actually visible (M15).
  Future<void> _openSearch(BunnySearch search) async {
    unawaited(_repository!.touchSearchViewed(search.id));
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            PostGridScreen(search: search, repository: _repository!, displaySettingsStore: widget.displaySettingsStore, syncSettingsStore: widget.syncSettingsStore, downloadSettingsStore: widget.downloadSettingsStore),
      ),
    );
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
              subtitle: Text(l10n.searchesIntervalSubtitle(search.site.toWireString(), search.intervalHours, search.totalCount)),
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
                  IconButton(
                    icon: Icon(search.pinned ? Icons.push_pin : Icons.push_pin_outlined),
                    tooltip: search.pinned ? l10n.searchesUnpinTooltip : l10n.searchesPinTooltip,
                    onPressed: () => _togglePin(search),
                  ),
                  _syncingSearchIds.contains(search.id)
                      ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                      : IconButton(icon: const Icon(Icons.refresh), tooltip: l10n.searchesSyncRowTooltip, onPressed: () => _syncOneSearch(search)),
                ],
              ),
              onTap: () => _openSearch(search),
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
        title: Text(switch (_syncAllProgress) { (final done, final total) => l10n.searchesSyncAllProgress(done, total), null => l10n.searchesScreenTitle }),
        actions: [
          IconButton(
            icon: _syncAllProgress != null ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync),
            tooltip: l10n.searchesCheckForUpdatesTooltip,
            onPressed: _syncAllProgress != null ? null : _checkForUpdates,
          ),
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
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SettingsScreen(
                    repository: _repository!,
                    themeSettingsStore: widget.themeSettingsStore,
                    lockService: widget.lockService,
                    syncSettingsStore: widget.syncSettingsStore,
                    displaySettingsStore: widget.displaySettingsStore,
                    downloadSettingsStore: widget.downloadSettingsStore,
                    settingsStore: widget.settingsStore,
                    onThemeModeChanged: widget.onThemeModeChanged,
                    onRepositoryConfigured: widget.onRepositoryConfigured,
                  ),
                ),
              );
              // Settings can create searches (the Backup section's import,
              // M11) -- unconditionally refresh on return rather than
              // threading a bool pop result through, since there's no
              // "cancelled" case worth skipping a cheap reload for.
              _refresh();
            },
          ),
          PopupMenuButton<SearchSortOrder>(
            icon: const Icon(Icons.sort),
            tooltip: l10n.searchesSortTooltip,
            initialValue: _sortOrder,
            onSelected: _setSortOrder,
            itemBuilder: (context) => [
              CheckedPopupMenuItem(value: SearchSortOrder.mostUnseen, checked: _sortOrder == SearchSortOrder.mostUnseen, child: Text(l10n.searchesSortMostUnseen)),
              CheckedPopupMenuItem(value: SearchSortOrder.label, checked: _sortOrder == SearchSortOrder.label, child: Text(l10n.searchesSortLabel)),
              CheckedPopupMenuItem(value: SearchSortOrder.recentlyCreated, checked: _sortOrder == SearchSortOrder.recentlyCreated, child: Text(l10n.searchesSortRecentlyCreated)),
              CheckedPopupMenuItem(value: SearchSortOrder.lastViewed, checked: _sortOrder == SearchSortOrder.lastViewed, child: Text(l10n.searchesSortLastViewed)),
            ],
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
          final searches = _sorted(all.where((search) => !_isPoolSearch(search)).toList());
          final pools = _sorted(all.where(_isPoolSearch).toList());
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
