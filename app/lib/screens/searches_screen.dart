import 'dart:async';

import 'package:flutter/material.dart';

import '../bunny_repository_scope.dart';
import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../services/download_queue_service.dart';
import '../settings/app_lock_service.dart';
import '../settings/display_settings_store.dart';
import '../settings/download_settings_store.dart';
import '../settings/repository_settings_store.dart';
import '../settings/theme_settings_store.dart';
import '../util/duplicate_searches.dart';
import '../util/responsive.dart';
import '../widgets/update_dialog.dart';
import 'accounts_screen.dart';
import 'create_search_screen.dart';
import 'custom_search_screen.dart';
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
  final DisplaySettingsStore displaySettingsStore;
  final DownloadSettingsStore downloadSettingsStore;
  final DownloadQueueService downloadQueueService;
  final RepositorySettingsStore settingsStore;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<ThemeColorOption> onThemeColorChanged;
  final ValueChanged<bool> onAmoledChanged;
  final ValueChanged<String?> onLanguageCodeChanged;
  final ValueChanged<BunnyRepository> onRepositoryConfigured;

  const SearchesScreen({
    super.key,
    required this.lockService,
    required this.themeSettingsStore,
    required this.displaySettingsStore,
    required this.downloadSettingsStore,
    required this.downloadQueueService,
    required this.settingsStore,
    required this.onThemeModeChanged,
    required this.onThemeColorChanged,
    required this.onAmoledChanged,
    required this.onLanguageCodeChanged,
    required this.onRepositoryConfigured,
  });

  @override
  State<SearchesScreen> createState() => _SearchesScreenState();
}

/// One row in the tree view (M21) -- either a standalone search or a group
/// with its member searches nested inside an [ExpansionTile]. A common
/// shape lets both kinds share one pin-first/[SearchSortOrder] sort pass.
sealed class _TreeEntry {
  bool get pinned;
  String get label;
  String get createdAt;
  String get lastViewedAt;
  int get unseenCount;
}

class _SearchEntry extends _TreeEntry {
  final BunnySearch search;

  _SearchEntry(this.search);

  @override
  bool get pinned => search.pinned;
  @override
  String get label => search.label;
  @override
  String get createdAt => search.createdAt;
  @override
  String get lastViewedAt => search.lastViewedAt ?? '';
  @override
  int get unseenCount => search.unseenCount;
}

class _GroupEntry extends _TreeEntry {
  final BunnyGroup group;
  final List<BunnySearch> members;

  _GroupEntry(this.group, this.members);

  @override
  bool get pinned => group.pinned;
  @override
  String get label => group.name;
  @override
  String get createdAt => group.createdAt;
  @override
  String get lastViewedAt => members.map((search) => search.lastViewedAt ?? '').fold('', (a, b) => a.compareTo(b) >= 0 ? a : b);
  @override
  int get unseenCount => members.fold(0, (sum, search) => sum + search.unseenCount);
  int get totalCount => members.fold(0, (sum, search) => sum + search.totalCount);
}

class _SearchesScreenState extends State<SearchesScreen> with SingleTickerProviderStateMixin {
  BunnyRepository? _repository;
  Future<({List<BunnySearch> searches, List<BunnyGroup> groups})>? _dataFuture;
  late final TabController _tabController;
  SearchSortOrder _sortOrder = SearchSortOrder.mostUnseen;

  /// Session-only (M41) -- re-shown on the next [_refresh] rather than
  /// persisted, so dismissing it doesn't hide a *different* set of
  /// duplicates that shows up later.
  bool _duplicatesBannerDismissed = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)..addListener(() => setState(() {}));
    _loadSortOrder();
    _pollSyncStatusOnce();
    _syncStatusPollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollSyncStatusOnce());
    // Once per app launch, not persisted/throttled further (M23) -- this
    // screen is itself only reached once per launch anyway (the app's main
    // post-setup/post-unlock home), so there's no risk of nagging the user
    // repeatedly within one session.
    checkForUpdateAndMaybePrompt(context);
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

  /// Same pin-first/[SearchSortOrder] pass as [_sorted], generalized to
  /// [_TreeEntry] (M21) so a group sorts alongside standalone searches using
  /// its own aggregated unseen count / name / earliest-created / latest-
  /// viewed-member in place of a single search's own fields.
  List<_TreeEntry> _sortedEntries(List<_TreeEntry> entries) {
    void sortBy(List<_TreeEntry> list) {
      switch (_sortOrder) {
        case SearchSortOrder.mostUnseen:
          list.sort((a, b) => b.unseenCount.compareTo(a.unseenCount));
        case SearchSortOrder.label:
          list.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
        case SearchSortOrder.recentlyCreated:
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        case SearchSortOrder.lastViewed:
          list.sort((a, b) => b.lastViewedAt.compareTo(a.lastViewedAt));
      }
    }

    final pinned = entries.where((entry) => entry.pinned).toList();
    final unpinned = entries.where((entry) => !entry.pinned).toList();
    sortBy(pinned);
    sortBy(unpinned);
    return [...pinned, ...unpinned];
  }

  /// Groups [searches] by [BunnySearch.groupId] (M21) -- a search with no
  /// group (0) becomes a standalone [_SearchEntry]; everything else is
  /// bucketed under its [BunnyGroup], dropped entirely if that group has no
  /// members in this particular tab (a group can have members split across
  /// the Searches/Pools tabs, each tab only shows its own slice).
  List<_TreeEntry> _buildEntries(List<BunnySearch> searches, List<BunnyGroup> groups) {
    final byGroupId = <int, List<BunnySearch>>{};
    final entries = <_TreeEntry>[];
    for (final search in searches) {
      if (search.groupId == 0) {
        entries.add(_SearchEntry(search));
      } else {
        byGroupId.putIfAbsent(search.groupId, () => []).add(search);
      }
    }
    for (final group in groups) {
      final members = byGroupId[group.id];
      if (members != null) {
        entries.add(_GroupEntry(group, members));
      }
    }
    return entries;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _repository = BunnyRepositoryScope.of(context);
    _dataFuture ??= _loadData();
  }

  Future<({List<BunnySearch> searches, List<BunnyGroup> groups})> _loadData() async {
    final searches = await _repository!.listSearches();
    final groups = await _repository!.listGroups();
    return (searches: searches, groups: groups);
  }

  @override
  void dispose() {
    _syncStatusPollTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _dataFuture = _loadData();
      _duplicatesBannerDismissed = false;
    });
  }

  /// Polled every 2s (and once immediately after [_checkForUpdates]
  /// triggers a sync) so the app bar reflects live progress of whatever's
  /// currently syncing server-side -- the scheduler, this device's own
  /// "check for updates", a single-row sync, or another device's, all look
  /// the same from here (M20). Replaces the old purely-local
  /// `_syncAllProgress` counter, which was invisible to every device except
  /// the one that started the sync and vanished on app restart.
  BunnySyncStatus _syncStatus = BunnySyncStatus.inactive;
  Timer? _syncStatusPollTimer;

  Future<void> _pollSyncStatusOnce() async {
    if (_repository == null) {
      return;
    }
    try {
      final status = await _repository!.getSyncStatus();
      if (!mounted) {
        return;
      }
      final wasActive = _syncStatus.active;
      setState(() {
        _syncStatus = status;
        if (status.active) {
          // Keep post/unseen counts climbing live while a sync runs,
          // instead of only refreshing once at the very end.
          _dataFuture = _loadData();
        }
      });
      if (wasActive && !status.active) {
        _refresh();
      }
    } catch (_) {
      // Transient network hiccup -- the next periodic tick will retry.
    }
  }

  /// Forces every saved search to sync right now (M13.2), ignoring each
  /// search's own due-interval -- a single call to the server-side sync
  /// worker (M20), which runs the whole batch in the background and keeps
  /// going past a single search's failure, same tolerance as before.
  /// Returns as soon as the server accepts the job (fire-and-forget for the
  /// server implementation; the standalone/FFI implementation runs the
  /// whole loop itself before resolving, since it has no server thread
  /// pool to protect) -- [_syncStatusPollTimer] is what actually shows
  /// progress.
  Future<void> _checkForUpdates() async {
    try {
      await _repository!.syncAllSearches();
    } catch (_) {
      // Surfaced via the polled status / next list refresh.
    }
    await _pollSyncStatusOnce();
  }

  Future<void> _createSearch() async {
    final created = await Navigator.push<bool>(context, MaterialPageRoute(builder: (context) => CreateSearchScreen(repository: _repository!)));
    if (created == true) {
      _refresh();
    }
  }

  Future<void> _createPoolSearch() async {
    final l10n = AppLocalizations.of(context)!;
    final result = await showDialog<(BunnySite, String)>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        var site = BunnySite.e621;
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(l10n.createPoolSearchDialogTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<BunnySite>(
                  segments: const [ButtonSegment(value: BunnySite.e621, label: Text('e621')), ButtonSegment(value: BunnySite.inkbunny, label: Text('Inkbunny'))],
                  selected: {site},
                  onSelectionChanged: (selection) => setState(() => site = selection.first),
                ),
                const SizedBox(height: 12),
                TextField(controller: controller, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: l10n.createPoolSearchIdLabel), autofocus: true),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonCancel)),
              TextButton(onPressed: () => Navigator.pop(context, (site, controller.text)), child: Text(l10n.createPoolSearchSubmit)),
            ],
          ),
        );
      },
    );
    if (result == null) {
      return;
    }
    final (site, poolIdText) = result;
    final poolId = int.tryParse(poolIdText);
    if (poolId == null) {
      return;
    }

    // Same duplicate-prevention check TagBrowseScreen's own checkmark action
    // applies (M38) -- a second pool search for the same (site, pool id)
    // would be functionally identical to the first.
    final existing = await _repository!.listSearches();
    if (existing.any((search) => search.site == site && search.query == 'pool:$poolId')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.createPoolSearchAlreadyExists)));
      }
      return;
    }

    // The pool's own name makes a far more useful label than the raw id, but
    // this works purely as a nice-to-have -- a failed lookup (network error,
    // deleted pool, etc.) still creates a perfectly functional pool search
    // with a fallback label, rather than blocking the whole action on it.
    // Inkbunny has no "fetch pool metadata" endpoint at all (M28) -- always
    // falls back to the raw-id label there, no lookup attempted (pool ids
    // aren't shared/comparable across sites, so trying e621's own lookup
    // with an Inkbunny pool id would risk silently naming it after an
    // unrelated e621 pool that happens to share the same numeric id).
    String label = 'pool:$poolId';
    if (site == BunnySite.e621) {
      try {
        final info = await _repository!.fetchPool(poolId);
        if (info.name != null && info.name!.isNotEmpty) {
          label = info.name!;
        }
      } catch (_) {
        // Fall back to the default label above.
      }
    }

    await _repository!.createSearch(site, label, 'pool:$poolId', usesDefaultInterval: true);
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
      await _waitForSyncToFinish();
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

  /// [syncSearch] returns as soon as the server *accepts* the job (M20), not
  /// when it finishes -- without this, the row's spinner would vanish
  /// almost instantly instead of for roughly the sync's real duration.
  /// bunny_core serializes every site-facing sync against the others, so
  /// "nothing is active" is a reasonable (if not perfectly scoped to just
  /// this one row) stand-in for "whatever was just enqueued is done".
  Future<void> _waitForSyncToFinish() async {
    while (mounted) {
      final status = await _repository!.getSyncStatus();
      if (!status.active) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
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
            PostGridScreen(
              search: search,
              repository: _repository!,
              displaySettingsStore: widget.displaySettingsStore,
              downloadSettingsStore: widget.downloadSettingsStore,
              downloadQueueService: widget.downloadQueueService,
            ),
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

  Future<String?> _promptForGroupName({required String title, required String submitLabel, String? initialValue}) {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, decoration: InputDecoration(labelText: l10n.searchesGroupNameLabel), autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonCancel)),
          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(submitLabel)),
        ],
      ),
    );
  }

  Future<void> _createGroup() async {
    final l10n = AppLocalizations.of(context)!;
    final name = await _promptForGroupName(title: l10n.searchesCreateGroupDialogTitle, submitLabel: l10n.searchesCreateGroupSubmit);
    if (name == null || name.trim().isEmpty) {
      return;
    }
    await _repository!.createGroup(name.trim(), false);
    _refresh();
  }

  Future<void> _renameGroup(BunnyGroup group) async {
    final l10n = AppLocalizations.of(context)!;
    final name = await _promptForGroupName(title: l10n.searchesRenameGroupDialogTitle, submitLabel: l10n.searchesRenameGroupSubmit, initialValue: group.name);
    if (name == null || name.trim().isEmpty) {
      return;
    }
    await _repository!.updateGroup(group.id, name.trim(), group.pinned);
    _refresh();
  }

  Future<void> _toggleGroupPinned(BunnyGroup group) async {
    await _repository!.updateGroup(group.id, group.name, !group.pinned);
    _refresh();
  }

  Future<void> _deleteGroup(BunnyGroup group) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.searchesDeleteGroupDialogTitle),
        content: Text(l10n.searchesDeleteGroupDialogContent(group.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.commonCancel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.commonRemove)),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await _repository!.deleteGroup(group.id);
    _refresh();
  }

  Widget _unseenBadge(int unseenCount) => Container(
    margin: const EdgeInsets.only(right: 8),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(12)),
    child: Text('$unseenCount', style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontSize: 12)),
  );

  Widget _searchTile(BunnySearch search) {
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      title: Text(search.label),
      subtitle: Text(l10n.searchesIntervalSubtitle(search.site.toWireString(), search.intervalHours, search.totalCount)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (search.unseenCount > 0) _unseenBadge(search.unseenCount),
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
    );
  }

  /// A folder-like row (M21) -- expands to show its member searches (each
  /// rendered the same as a standalone row via [_searchTile]), with its own
  /// pin toggle and a rename/delete menu in place of the per-search sync
  /// icon, which doesn't make sense for a whole group at once.
  Widget _groupTile(_GroupEntry entry) {
    final l10n = AppLocalizations.of(context)!;
    final members = _sorted(entry.members);
    return ExpansionTile(
      key: PageStorageKey('group-${entry.group.id}'),
      leading: const Icon(Icons.folder_outlined),
      title: Row(
        children: [Expanded(child: Text(entry.group.name, overflow: TextOverflow.ellipsis)), if (entry.unseenCount > 0) _unseenBadge(entry.unseenCount)],
      ),
      subtitle: Text(l10n.searchesGroupSubtitle(entry.totalCount)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(entry.group.pinned ? Icons.push_pin : Icons.push_pin_outlined),
            tooltip: entry.group.pinned ? l10n.searchesUnpinTooltip : l10n.searchesPinTooltip,
            onPressed: () => _toggleGroupPinned(entry.group),
          ),
          PopupMenuButton<String>(
            onSelected: (action) {
              switch (action) {
                case 'rename':
                  _renameGroup(entry.group);
                case 'delete':
                  _deleteGroup(entry.group);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'rename', child: Text(l10n.searchesRenameGroupMenuItem)),
              PopupMenuItem(value: 'delete', child: Text(l10n.searchesDeleteGroupMenuItem)),
            ],
          ),
        ],
      ),
      children: members.map(_searchTile).toList(),
    );
  }

  Widget _entryTile(_TreeEntry entry) => switch (entry) {
    _SearchEntry(search: final search) => _searchTile(search),
    _GroupEntry() => _groupTile(entry),
  };

  Widget _searchList(List<_TreeEntry> entries, String emptyState) {
    if (entries.isEmpty) {
      return Center(child: Text(emptyState));
    }
    return ListView(children: entries.map(_entryTile).toList());
  }

  /// Flags pre-existing (site, query) duplicates (M41) -- M38's own create-
  /// time check only stops new ones. Dismissing this is session-only (see
  /// [_duplicatesBannerDismissed]'s own doc comment); it doesn't touch any
  /// search data by itself, only [_resolveDuplicates] does that.
  Widget _duplicatesBanner(AppLocalizations l10n, List<List<BunnySearch>> duplicateGroups, List<BunnyGroup> groups) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(child: Text(l10n.searchesDuplicatesBannerMessage(duplicateGroups.length))),
            TextButton(onPressed: () => _resolveDuplicates(l10n, duplicateGroups, groups), child: Text(l10n.searchesDuplicatesBannerReviewAction)),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: l10n.searchesDuplicatesBannerDismissTooltip,
              onPressed: () => setState(() => _duplicatesBannerDismissed = true),
            ),
          ],
        ),
      ),
    );
  }

  /// One member of a duplicate group's own detail row in the resolve
  /// dialog -- enough to tell divergent duplicates apart (interval, pinned,
  /// group) without opening the full edit form for each one.
  Widget _duplicateCandidateTile(AppLocalizations l10n, BunnySearch search, List<BunnyGroup> groups, VoidCallback onKeep) {
    String? groupName;
    for (final group in groups) {
      if (group.id == search.groupId) {
        groupName = group.name;
        break;
      }
    }
    return ListTile(
      title: Text(search.label),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.searchesResolveDuplicatesIntervalLabel(search.intervalHours)),
          if (search.pinned) Text(l10n.searchesResolveDuplicatesPinnedLabel),
          if (groupName != null) Text(l10n.searchesResolveDuplicatesGroupLabel(groupName)),
        ],
      ),
      isThreeLine: search.pinned || groupName != null,
      trailing: TextButton(onPressed: onKeep, child: Text(l10n.searchesResolveDuplicatesKeepButton)),
    );
  }

  /// Merges every other member of [group] into [keeper] -- see
  /// [BunnyRepository.mergeDuplicateSearch]'s own doc comment for what
  /// "merge" means here (synced posts move over, settings aren't
  /// reconciled). Sequential rather than parallel: a mass-action volume
  /// (at most a handful of duplicates per group) that doesn't need the
  /// batching this app's mass-download/favorite actions already use.
  Future<void> _keepDuplicate(BunnySearch keeper, List<BunnySearch> group) async {
    for (final other in group) {
      if (other.id != keeper.id) {
        await _repository!.mergeDuplicateSearch(keeper.id, other.id);
      }
    }
  }

  Future<void> _resolveDuplicates(AppLocalizations l10n, List<List<BunnySearch>> initialGroups, List<BunnyGroup> groups) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        var remainingGroups = initialGroups;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(l10n.searchesResolveDuplicatesDialogTitle),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final group in remainingGroups) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(l10n.searchesResolveDuplicatesGroupHeading(group.first.site.toWireString(), group.first.query), style: Theme.of(context).textTheme.titleSmall),
                    ),
                    for (final search in group)
                      _duplicateCandidateTile(l10n, search, groups, () async {
                        await _keepDuplicate(search, group);
                        setDialogState(() => remainingGroups = remainingGroups.where((g) => g != group).toList());
                        if (remainingGroups.isEmpty && context.mounted) {
                          Navigator.pop(context);
                        }
                      }),
                  ],
                ],
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.searchesResolveDuplicatesDoneButton))],
          ),
        );
      },
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final onPoolsTab = _tabController.index == 1;
    final wide = isWideScreen(context);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: wide ? compactToolbarHeight : null,
        title: Text(
          !_syncStatus.active
              ? l10n.searchesScreenTitle
              : _syncStatus.total > 0
              ? l10n.searchesSyncAllProgress(_syncStatus.position, _syncStatus.total)
              : l10n.searchesSyncInProgress,
        ),
        actions: [
          IconButton(
            icon: _syncStatus.active ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync),
            tooltip: l10n.searchesCheckForUpdatesTooltip,
            onPressed: _syncStatus.active ? null : _checkForUpdates,
          ),
          IconButton(
            icon: const Icon(Icons.travel_explore),
            tooltip: l10n.searchesCustomSearchTooltip,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CustomSearchScreen(
                  repository: _repository!,
                  displaySettingsStore: widget.displaySettingsStore,
                  downloadSettingsStore: widget.downloadSettingsStore,
                  downloadQueueService: widget.downloadQueueService,
                ),
              ),
            ),
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
                  downloadSettingsStore: widget.downloadSettingsStore,
                  downloadQueueService: widget.downloadQueueService,
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
                  downloadSettingsStore: widget.downloadSettingsStore,
                  downloadQueueService: widget.downloadQueueService,
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
                    displaySettingsStore: widget.displaySettingsStore,
                    downloadSettingsStore: widget.downloadSettingsStore,
                    settingsStore: widget.settingsStore,
                    onThemeModeChanged: widget.onThemeModeChanged,
                    onThemeColorChanged: widget.onThemeColorChanged,
                    onAmoledChanged: widget.onAmoledChanged,
                    onLanguageCodeChanged: widget.onLanguageCodeChanged,
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
          IconButton(icon: const Icon(Icons.create_new_folder_outlined), tooltip: l10n.searchesNewGroupTooltip, onPressed: _createGroup),
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
      body: FutureBuilder<({List<BunnySearch> searches, List<BunnyGroup> groups})>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snapshot.data!.searches;
          final groups = snapshot.data!.groups;
          final searches = _sortedEntries(_buildEntries(all.where((search) => !search.isPool && !search.isFavorites).toList(), groups));
          final pools = _sortedEntries(_buildEntries(all.where((search) => search.isPool).toList(), groups));
          final duplicateGroups = findDuplicateSearchGroups(all);
          return Column(
            children: [
              if (duplicateGroups.isNotEmpty && !_duplicatesBannerDismissed) _duplicatesBanner(l10n, duplicateGroups, groups),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [_searchList(searches, l10n.searchesEmptyState), _searchList(pools, l10n.searchesPoolsEmptyState)],
                ),
              ),
            ],
          );
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
