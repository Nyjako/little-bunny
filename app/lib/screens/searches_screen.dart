import 'dart:async';

import 'package:flutter/material.dart';

import '../bunny_repository_scope.dart';
import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../services/download_manager.dart';
import '../services/download_queue_service.dart';
import '../services/preview_cache_service.dart';
import '../services/update_apply_service.dart';
import '../services/update_check_service.dart';
import '../settings/app_lock_service.dart';
import '../settings/display_settings_store.dart';
import '../settings/download_settings_store.dart';
import '../settings/repository_settings_store.dart';
import '../settings/theme_settings_store.dart';
import '../settings/update_settings_store.dart';
import '../util/create_pool_search_dialog.dart';
import '../util/duplicate_searches.dart';
import '../util/duration_format.dart';
import '../util/responsive.dart';
import '../widgets/update_dialog.dart';
import 'accounts_screen.dart';
import 'create_search_screen.dart';
import 'custom_search_screen.dart';
import 'download_queue_screen.dart';
import 'edit_search_screen.dart';
import 'post_grid_screen.dart';
import 'settings_screen.dart';
import 'slideshows_screen.dart';
import 'tag_stats_screen.dart';

/// A search/pool row's long-press menu actions -- see `_showSearchRowMenu`.
enum _SearchRowAction { edit, addToSlideshow }

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
  final PreviewCacheService previewCacheService;
  final RepositorySettingsStore settingsStore;
  final UpdateSettingsStore updateSettingsStore;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<ThemeColorOption> onThemeColorChanged;
  final ValueChanged<bool> onAmoledChanged;
  final ValueChanged<String?> onLanguageCodeChanged;
  final ValueChanged<BunnyRepository> onRepositoryConfigured;

  /// Injectable for tests (same reasoning as every other service field
  /// here); both default to real instances.
  final UpdateCheckService updateCheckService;
  final UpdateApplyService updateApplyService;

  const SearchesScreen({
    super.key,
    required this.lockService,
    required this.themeSettingsStore,
    required this.displaySettingsStore,
    required this.downloadSettingsStore,
    required this.downloadQueueService,
    required this.previewCacheService,
    required this.settingsStore,
    required this.updateSettingsStore,
    required this.onThemeModeChanged,
    required this.onThemeColorChanged,
    required this.onAmoledChanged,
    required this.onLanguageCodeChanged,
    required this.onRepositoryConfigured,
    this.updateCheckService = const UpdateCheckService(),
    this.updateApplyService = const UpdateApplyService(),
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

  /// The most recent sync-found-a-new-post timestamp across this entry
  /// (M69) -- '' (sorts last, same convention as [lastViewedAt]) if none.
  String get lastUpdatedAt;
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
  @override
  String get lastUpdatedAt => search.lastUpdatedAt ?? '';
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
  @override
  String get lastUpdatedAt => members.map((search) => search.lastUpdatedAt ?? '').fold('', (a, b) => a.compareTo(b) >= 0 ? a : b);
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

  /// A local, client-side filter over this screen's own already-saved
  /// searches/pools -- not a live site search. Session-only, same
  /// "toggle-able, re-hidden rather than persisted" convention as
  /// [_duplicatesBannerDismissed] above; starts hidden so the already-dense
  /// app bar/list isn't cluttered until the user actually wants it.
  final _finderController = TextEditingController();
  bool _finderVisible = false;

  void _toggleFinder() {
    setState(() {
      _finderVisible = !_finderVisible;
      if (!_finderVisible) {
        _finderController.clear();
      }
    });
  }

  /// Matches [filter] (already trimmed/lowercased by the caller) against a
  /// search's own label or query text -- covers title, tags, and author,
  /// since a search's query is typically the artist/tag text being
  /// searched and its label defaults to mirroring it. A pool's numeric id
  /// is matched directly too (same `substring(5)` convention [BunnySearch.
  /// isPool] call sites elsewhere in the app already use to parse it),
  /// since the id itself isn't otherwise repeated in the label/query text.
  bool _matchesFinder(BunnySearch search, String filter) {
    if (filter.isEmpty) {
      return true;
    }
    if (search.label.toLowerCase().contains(filter) || search.query.toLowerCase().contains(filter)) {
      return true;
    }
    return search.isPool && int.tryParse(search.query.substring(5))?.toString() == filter;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this)..addListener(() => setState(() {}));
    _finderController.addListener(() => setState(() {}));
    _loadSortOrder();
    _pollSyncStatusOnce();
    _syncStatusPollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollSyncStatusOnce());
    // Once per app launch, not persisted/throttled further (M23) -- this
    // screen is itself only reached once per launch anyway (the app's main
    // post-setup/post-unlock home), so there's no risk of nagging the user
    // repeatedly within one session.
    _maybeCheckForUpdate();
  }

  Future<void> _maybeCheckForUpdate() async {
    final autoCheckEnabled = await widget.updateSettingsStore.loadAutoCheckEnabled();
    if (!mounted || !autoCheckEnabled) {
      return;
    }
    checkForUpdateAndMaybePrompt(context, checkService: widget.updateCheckService, applyService: widget.updateApplyService);
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
        case SearchSortOrder.lastUpdated:
          list.sort((a, b) => (b.lastUpdatedAt ?? '').compareTo(a.lastUpdatedAt ?? ''));
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
        case SearchSortOrder.lastUpdated:
          list.sort((a, b) => b.lastUpdatedAt.compareTo(a.lastUpdatedAt));
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
    _finderController.dispose();
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
    final created = await showCreatePoolSearchDialog(context, _repository!);
    if (created) {
      _refresh();
    }
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

  /// Download-selection mode (M65) -- a bare toggle (unlike [PostGridScreen]'s
  /// own "non-empty set = selection mode" convention), since this screen's
  /// tiles already use `onTap`/`onLongPress` for opening/editing a search --
  /// an explicit app-bar action is what enters/exits this mode instead, so
  /// those two gestures stay available for a non-selected search even while
  /// others are selected. Only standalone searches are selectable, not whole
  /// groups at once -- expand a group to select its members individually.
  bool _selectionMode = false;
  final Set<int> _selectedSearchIds = {};
  bool _loadingSelectedSearches = false;

  void _toggleSearchSelection(int searchId) {
    setState(() {
      if (!_selectedSearchIds.remove(searchId)) {
        _selectedSearchIds.add(searchId);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedSearchIds.clear();
    });
  }

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

  /// Downloads every post matched by each selected search (M65) -- not just
  /// whatever a post grid happened to have loaded, same "I actually want
  /// everything" intent as [PostGridScreen._selectEntireSearch], just
  /// starting from this screen's own multi-search selection instead of one
  /// already-open search. Pages through [BunnyRepository.listSearchPosts]
  /// until an empty page, per search, sequentially -- same stopping
  /// condition [PostGridScreen._selectEntireSearch] already uses. One
  /// combined [DownloadQueueService.enqueueAll] call across every selected
  /// search's posts at the end, so enqueueAll's own dedup (a post could
  /// legitimately appear in more than one of the selected searches) only
  /// ever queues it once.
  ///
  /// This can take a while for several large searches, and the old bare
  /// AppBar spinner gave no sense of how far along it was -- [_loadProgress]
  /// (M67) drives a modal dialog showing which search (of how many
  /// selected) is loading right now and how many of its posts (each
  /// [BunnySearch.totalCount] is already known) have come in so far, rather
  /// than leaving the user staring at an un-cancellable spinner with no
  /// feedback. [enqueueAll] is awaited (M67 follow-up) so the "N queued"
  /// confirmation -- and the selection actually clearing -- only happens
  /// once every row is durably persisted, closing the window where closing
  /// the app right after that confirmation could lose some of them.
  Future<void> _downloadSelectedSearches(AppLocalizations l10n) async {
    final selectedIds = _selectedSearchIds.toSet();
    if (selectedIds.isEmpty || _dataFuture == null) {
      return;
    }
    setState(() => _loadingSelectedSearches = true);
    final loadProgress = _SelectedSearchesLoadProgress();
    unawaited(showDialog<void>(context: context, barrierDismissible: false, builder: (context) => _SelectedSearchesLoadDialog(progress: loadProgress)));
    try {
      final data = await _dataFuture!;
      final selectedSearches = data.searches.where((search) => selectedIds.contains(search.id)).toList();
      final allPosts = <BunnyPost>[];
      for (final (index, search) in selectedSearches.indexed) {
        loadProgress.startSearch(index: index + 1, count: selectedSearches.length, label: search.label, total: search.totalCount);
        var page = 1;
        var searchLoaded = 0;
        while (true) {
          final pageItems = await _repository!.listSearchPosts(search.id, page: page);
          if (pageItems.isEmpty) {
            break;
          }
          allPosts.addAll(pageItems);
          searchLoaded += pageItems.length;
          loadProgress.setLoaded(searchLoaded);
          page++;
        }
      }
      if (!mounted) {
        return;
      }
      await widget.downloadQueueService.enqueueAll(allPosts, _repository!);
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingSelectedSearches = false;
        _selectionMode = false;
        _selectedSearchIds.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.searchesMassDownloadQueued(allPosts.length))));
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _loadingSelectedSearches = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.searchesMassDownloadError)));
    } finally {
      if (mounted) {
        Navigator.of(context).pop();
      }
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

  /// Long-press's menu (below) for a single search/pool row -- mirrors
  /// `PostDetailScreen._showTagMenu`'s own bottom-sheet-plus-enum pattern.
  /// `edit` keeps today's exact destination (long-press used to jump
  /// straight there); `addToSlideshow` is new.
  Future<void> _showSearchRowMenu(AppLocalizations l10n, BunnySearch search) async {
    final action = await showModalBottomSheet<_SearchRowAction>(
      context: context,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(leading: const Icon(Icons.edit_outlined), title: Text(l10n.searchesRowMenuEditLabel), onTap: () => Navigator.pop(context, _SearchRowAction.edit)),
              ListTile(
                leading: const Icon(Icons.slideshow_outlined),
                title: Text(l10n.searchesRowMenuAddToSlideshowLabel),
                onTap: () => Navigator.pop(context, _SearchRowAction.addToSlideshow),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case _SearchRowAction.edit:
        await _editSearch(search);
      case _SearchRowAction.addToSlideshow:
        await _addSearchToSlideshow(l10n, search);
    }
  }

  /// Tap-to-pick slideshow dialog shared by the single-search path
  /// ([_addSearchToSlideshow]) and the bulk path
  /// ([_addSelectedSearchesToSlideshow]) -- `null` means there were no
  /// slideshows to pick from (already snackbar'd here) or the user backed
  /// out of the picker.
  Future<BunnySlideshow?> _pickSlideshow(AppLocalizations l10n) async {
    final slideshows = await _repository!.slideshowList();
    if (slideshows.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.searchesNoSlideshowsYet)));
      }
      return null;
    }
    if (!mounted) {
      return null;
    }
    return showDialog<BunnySlideshow>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.searchesAddToSlideshowDialogTitle),
        children: [for (final slideshow in slideshows) SimpleDialogOption(onPressed: () => Navigator.pop(context, slideshow), child: Text(slideshow.label))],
      ),
    );
  }

  /// Individual "add to slideshow" (from the row's long-press menu) --
  /// self-contained, no navigation into [SlideshowEditScreen] needed.
  Future<void> _addSearchToSlideshow(AppLocalizations l10n, BunnySearch search) async {
    final slideshow = await _pickSlideshow(l10n);
    if (slideshow == null) {
      return;
    }
    await _repository!.slideshowSearchAdd(slideshow.id, search.id);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.searchesAddedToSlideshow(slideshow.label))));
  }

  /// Bulk "add to slideshow" from selection mode -- same iterate-then-one-
  /// confirmation shape [_downloadSelectedSearches] already uses for its own
  /// bulk action, just linking into a slideshow instead of enqueueing
  /// downloads.
  Future<void> _addSelectedSearchesToSlideshow(AppLocalizations l10n) async {
    final selectedIds = _selectedSearchIds.toSet();
    if (selectedIds.isEmpty) {
      return;
    }
    final slideshow = await _pickSlideshow(l10n);
    if (slideshow == null) {
      return;
    }
    for (final searchId in selectedIds) {
      await _repository!.slideshowSearchAdd(slideshow.id, searchId);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _selectionMode = false;
      _selectedSearchIds.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.searchesAddedSelectedToSlideshow(selectedIds.length, slideshow.label))));
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

  /// "Updated {duration} ago" (M69) -- null if [lastUpdatedAt] is null/
  /// unparseable (no sync has ever found a new post for this search/group
  /// yet), in which case the row just shows nothing extra rather than a
  /// placeholder like "never".
  Widget? _lastUpdatedSubtitle(AppLocalizations l10n, String? lastUpdatedAt) {
    if (lastUpdatedAt == null) {
      return null;
    }
    final parsed = DateTime.tryParse(lastUpdatedAt);
    if (parsed == null) {
      return null;
    }
    final ago = formatDurationCompact(DateTime.now().toUtc().difference(parsed));
    return Text(l10n.searchesLastUpdatedSubtitle(ago), style: Theme.of(context).textTheme.bodySmall);
  }

  Widget _unseenBadge(int unseenCount) => Container(
    margin: const EdgeInsets.only(right: 8),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(12)),
    child: Text('$unseenCount', style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontSize: 12)),
  );

  Widget _searchTile(BunnySearch search) {
    final l10n = AppLocalizations.of(context)!;
    if (_selectionMode) {
      return CheckboxListTile(
        value: _selectedSearchIds.contains(search.id),
        onChanged: (_) => _toggleSearchSelection(search.id),
        title: Text(search.label),
        subtitle: Text(l10n.searchesIntervalSubtitle(search.site.toWireString(), search.intervalHours, search.totalCount)),
        secondary: search.unseenCount > 0 ? _unseenBadge(search.unseenCount) : null,
      );
    }
    final lastUpdatedSubtitle = _lastUpdatedSubtitle(l10n, search.lastUpdatedAt);
    return ListTile(
      title: Text(search.label),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.searchesIntervalSubtitle(search.site.toWireString(), search.intervalHours, search.totalCount)),
          ?lastUpdatedSubtitle,
        ],
      ),
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
      onLongPress: () => _showSearchRowMenu(l10n, search),
    );
  }

  /// A folder-like row (M21) -- expands to show its member searches (each
  /// rendered the same as a standalone row via [_searchTile]), with its own
  /// pin toggle and a rename/delete menu in place of the per-search sync
  /// icon, which doesn't make sense for a whole group at once.
  Widget _groupTile(_GroupEntry entry) {
    final l10n = AppLocalizations.of(context)!;
    final members = _sorted(entry.members);
    final lastUpdatedSubtitle = _lastUpdatedSubtitle(l10n, entry.lastUpdatedAt.isEmpty ? null : entry.lastUpdatedAt);
    return ExpansionTile(
      key: PageStorageKey('group-${entry.group.id}'),
      leading: const Icon(Icons.folder_outlined),
      title: Row(
        children: [Expanded(child: Text(entry.group.name, overflow: TextOverflow.ellipsis)), if (entry.unseenCount > 0) _unseenBadge(entry.unseenCount)],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.searchesGroupSubtitle(entry.totalCount)),
          ?lastUpdatedSubtitle,
        ],
      ),
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

  List<Widget> _selectionModeActions(AppLocalizations l10n) => [
    _loadingSelectedSearches
        ? const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
        : IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: l10n.searchesDownloadSelectedTooltip,
            onPressed: _selectedSearchIds.isEmpty ? null : () => _downloadSelectedSearches(l10n),
          ),
    IconButton(
      icon: const Icon(Icons.slideshow_outlined),
      tooltip: l10n.searchesAddSelectedToSlideshowTooltip,
      onPressed: _selectedSearchIds.isEmpty ? null : () => _addSelectedSearchesToSlideshow(l10n),
    ),
  ];

  Widget _syncIconButton(AppLocalizations l10n) => IconButton(
    icon: _syncStatus.active ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync),
    tooltip: l10n.searchesCheckForUpdatesTooltip,
    onPressed: _syncStatus.active ? null : _checkForUpdates,
  );

  Widget _finderIconButton(AppLocalizations l10n) =>
      IconButton(icon: Icon(_finderVisible ? Icons.search_off : Icons.search), tooltip: l10n.searchesFinderTooltip, onPressed: _toggleFinder);

  Widget _downloadQueueIconButton(AppLocalizations l10n) => IconButton(
    icon: const Icon(Icons.download_outlined),
    tooltip: l10n.searchesDownloadQueueTooltip,
    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => DownloadQueueScreen(downloadQueueService: widget.downloadQueueService))),
  );

  void _openCustomSearch() => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) =>
          CustomSearchScreen(repository: _repository!, displaySettingsStore: widget.displaySettingsStore, downloadSettingsStore: widget.downloadSettingsStore, downloadQueueService: widget.downloadQueueService),
    ),
  );

  void _openAccounts() => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) =>
          AccountsScreen(repository: _repository!, displaySettingsStore: widget.displaySettingsStore, downloadSettingsStore: widget.downloadSettingsStore, downloadQueueService: widget.downloadQueueService),
    ),
  );

  void _openTagStats() => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => TagStatsScreen(
        repository: _repository!,
        displaySettingsStore: widget.displaySettingsStore,
        downloadSettingsStore: widget.downloadSettingsStore,
        downloadQueueService: widget.downloadQueueService,
        previewCacheService: widget.previewCacheService,
      ),
    ),
  );

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          repository: _repository!,
          themeSettingsStore: widget.themeSettingsStore,
          lockService: widget.lockService,
          displaySettingsStore: widget.displaySettingsStore,
          downloadSettingsStore: widget.downloadSettingsStore,
          downloadQueueService: widget.downloadQueueService,
          settingsStore: widget.settingsStore,
          updateSettingsStore: widget.updateSettingsStore,
          onThemeModeChanged: widget.onThemeModeChanged,
          onThemeColorChanged: widget.onThemeColorChanged,
          onAmoledChanged: widget.onAmoledChanged,
          onLanguageCodeChanged: widget.onLanguageCodeChanged,
          onRepositoryConfigured: widget.onRepositoryConfigured,
        ),
      ),
    );
    // Settings can create searches (the Backup section's import, M11) --
    // unconditionally refresh on return rather than threading a bool pop
    // result through, since there's no "cancelled" case worth skipping a
    // cheap reload for.
    _refresh();
  }

  List<PopupMenuEntry<SearchSortOrder>> _sortMenuItems(AppLocalizations l10n) => [
    CheckedPopupMenuItem(value: SearchSortOrder.mostUnseen, checked: _sortOrder == SearchSortOrder.mostUnseen, child: Text(l10n.searchesSortMostUnseen)),
    CheckedPopupMenuItem(value: SearchSortOrder.label, checked: _sortOrder == SearchSortOrder.label, child: Text(l10n.searchesSortLabel)),
    CheckedPopupMenuItem(value: SearchSortOrder.recentlyCreated, checked: _sortOrder == SearchSortOrder.recentlyCreated, child: Text(l10n.searchesSortRecentlyCreated)),
    CheckedPopupMenuItem(value: SearchSortOrder.lastViewed, checked: _sortOrder == SearchSortOrder.lastViewed, child: Text(l10n.searchesSortLastViewed)),
    CheckedPopupMenuItem(value: SearchSortOrder.lastUpdated, checked: _sortOrder == SearchSortOrder.lastUpdated, child: Text(l10n.searchesSortLastUpdated)),
  ];

  /// A plain icon+label row for a [PopupMenuItem] that reuses an existing
  /// app-bar icon/tooltip as its own label, rather than new l10n strings.
  Widget _menuRow(IconData icon, String label) => Row(children: [Icon(icon), const SizedBox(width: 12), Text(label)]);

  List<Widget> _wideModeActions(AppLocalizations l10n) => [
    _syncIconButton(l10n),
    _finderIconButton(l10n),
    IconButton(icon: const Icon(Icons.travel_explore), tooltip: l10n.searchesCustomSearchTooltip, onPressed: _openCustomSearch),
    _downloadQueueIconButton(l10n),
    IconButton(icon: const Icon(Icons.person_outline), tooltip: l10n.searchesAccountsTooltip, onPressed: _openAccounts),
    IconButton(icon: const Icon(Icons.bar_chart_outlined), tooltip: l10n.searchesTagStatsTooltip, onPressed: _openTagStats),
    IconButton(icon: const Icon(Icons.settings_outlined), tooltip: l10n.searchesSettingsTooltip, onPressed: _openSettings),
    IconButton(icon: const Icon(Icons.create_new_folder_outlined), tooltip: l10n.searchesNewGroupTooltip, onPressed: _createGroup),
    PopupMenuButton<SearchSortOrder>(
      icon: const Icon(Icons.sort),
      tooltip: l10n.searchesSortTooltip,
      initialValue: _sortOrder,
      onSelected: _setSortOrder,
      itemBuilder: (context) => [
        ..._sortMenuItems(l10n),
        const PopupMenuDivider(),
        // No value -- the parent's onSelected (_setSortOrder) above is only
        // ever asked about SearchSortOrder values, never this one;
        // PopupMenuItem.onTap runs regardless (M65). Folded in here rather
        // than its own app-bar icon since a 9th icon doesn't fit next to
        // the other 8 on a narrow window (M9.6.6's own compact-width test).
        PopupMenuItem<SearchSortOrder>(onTap: () => setState(() => _selectionMode = true), child: Text(l10n.searchesSelectForDownloadTooltip)),
      ],
    ),
  ];

  /// Narrow/mobile width (M9.6.6's breakpoint): only [_syncIconButton],
  /// [_finderIconButton], and [_downloadQueueIconButton] -- the most
  /// frequently used -- stay as direct icons; everything else
  /// [_wideModeActions] shows individually
  /// (custom search, accounts, tag stats, settings, new group, sort, and
  /// select-for-download) folds into one overflow menu, same `value:`-vs-
  /// `onTap:`-only trick the sort menu above already uses for its own
  /// value-less item, just extended to more of them.
  List<Widget> _narrowModeActions(AppLocalizations l10n) => [
    _syncIconButton(l10n),
    _finderIconButton(l10n),
    _downloadQueueIconButton(l10n),
    PopupMenuButton<SearchSortOrder>(
      icon: const Icon(Icons.more_vert),
      tooltip: l10n.searchesMoreActionsTooltip,
      initialValue: _sortOrder,
      onSelected: _setSortOrder,
      itemBuilder: (context) => [
        ..._sortMenuItems(l10n),
        const PopupMenuDivider(),
        PopupMenuItem<SearchSortOrder>(onTap: () => setState(() => _selectionMode = true), child: Text(l10n.searchesSelectForDownloadTooltip)),
        const PopupMenuDivider(),
        PopupMenuItem<SearchSortOrder>(onTap: _openCustomSearch, child: _menuRow(Icons.travel_explore, l10n.searchesCustomSearchTooltip)),
        PopupMenuItem<SearchSortOrder>(onTap: _openAccounts, child: _menuRow(Icons.person_outline, l10n.searchesAccountsTooltip)),
        PopupMenuItem<SearchSortOrder>(onTap: _openTagStats, child: _menuRow(Icons.bar_chart_outlined, l10n.searchesTagStatsTooltip)),
        PopupMenuItem<SearchSortOrder>(onTap: _openSettings, child: _menuRow(Icons.settings_outlined, l10n.searchesSettingsTooltip)),
        PopupMenuItem<SearchSortOrder>(onTap: _createGroup, child: _menuRow(Icons.create_new_folder_outlined, l10n.searchesNewGroupTooltip)),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final onPoolsTab = _tabController.index == 1;
    final onSlideshowsTab = _tabController.index == 2;
    final wide = isWideScreen(context);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: wide ? compactToolbarHeight : null,
        title: Text(
          _selectionMode
              ? l10n.searchesSelectedCount(_selectedSearchIds.length)
              : !_syncStatus.active
              ? l10n.searchesScreenTitle
              : _syncStatus.total > 0
              ? l10n.searchesSyncAllProgress(_syncStatus.position, _syncStatus.total)
              : l10n.searchesSyncInProgress,
        ),
        leading: _selectionMode ? IconButton(icon: const Icon(Icons.close), tooltip: l10n.commonCancel, onPressed: _exitSelectionMode) : null,
        actions: _selectionMode ? _selectionModeActions(l10n) : (wide ? _wideModeActions(l10n) : _narrowModeActions(l10n)),
        bottom: TabBar(
          controller: _tabController,
          labelPadding: wide ? const EdgeInsets.symmetric(horizontal: 16, vertical: 4) : null,
          tabs: [Tab(text: l10n.searchesTabSearches), Tab(text: l10n.searchesTabPools), Tab(text: l10n.searchesTabSlideshows)],
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
          final rawFilter = _finderController.text.trim();
          final filter = rawFilter.toLowerCase();
          final searches = _sortedEntries(_buildEntries(all.where((search) => !search.isPool && !search.isFavorites && _matchesFinder(search, filter)).toList(), groups));
          final pools = _sortedEntries(_buildEntries(all.where((search) => search.isPool && _matchesFinder(search, filter)).toList(), groups));
          final duplicateGroups = findDuplicateSearchGroups(all);
          return Column(
            children: [
              if (duplicateGroups.isNotEmpty && !_duplicatesBannerDismissed) _duplicatesBanner(l10n, duplicateGroups, groups),
              if (_finderVisible)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: TextField(
                    controller: _finderController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: l10n.searchesFinderHint,
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _finderController.text.isEmpty
                          ? null
                          : IconButton(icon: const Icon(Icons.clear), tooltip: l10n.searchesFinderClearTooltip, onPressed: _finderController.clear),
                      isDense: true,
                    ),
                  ),
                ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _searchList(searches, filter.isEmpty ? l10n.searchesEmptyState : l10n.searchesFinderEmptyState(rawFilter)),
                    _searchList(pools, filter.isEmpty ? l10n.searchesPoolsEmptyState : l10n.searchesFinderEmptyState(rawFilter)),
                    SlideshowsScreen(
                      repository: _repository!,
                      downloadManager: const DownloadManager(),
                      downloadSettingsStore: widget.downloadSettingsStore,
                      downloadQueueService: widget.downloadQueueService,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      // null on the Slideshows tab -- SlideshowsScreen owns its own FAB
      // (creating a slideshow, not a search/pool).
      floatingActionButton: onSlideshowsTab
          ? null
          : FloatingActionButton(
              onPressed: onPoolsTab ? _createPoolSearch : _createSearch,
              tooltip: onPoolsTab ? l10n.searchesNewPoolTooltip : l10n.searchesNewSearchTooltip,
              child: const Icon(Icons.add),
            ),
    );
  }
}

/// Backs [_SearchesScreenState._downloadSelectedSearches]'s loading dialog
/// (M67) -- a plain [ChangeNotifier] (same pattern [DownloadQueueService]
/// already uses) rather than a [Stream], since this only ever has the one
/// dialog listening to it and plain field reads are simpler than wiring a
/// controller for that.
class _SelectedSearchesLoadProgress extends ChangeNotifier {
  int searchIndex = 0;
  int searchCount = 0;
  String searchLabel = '';
  int loaded = 0;
  int total = 0;

  /// Call once per search, before paging through it -- resets [loaded] to 0
  /// since it tracks *this* search's own posts loaded so far, not a running
  /// total across every selected search.
  void startSearch({required int index, required int count, required String label, required int total}) {
    searchIndex = index;
    searchCount = count;
    searchLabel = label;
    loaded = 0;
    this.total = total;
    notifyListeners();
  }

  void setLoaded(int loaded) {
    this.loaded = loaded;
    notifyListeners();
  }
}

/// Non-dismissible -- there's nothing sensible to resume into partway
/// through paging every selected search's posts, so this blocks the screen
/// until [_SearchesScreenState._downloadSelectedSearches] either finishes
/// or fails, same as it already did before this dialog existed (just as a
/// bare un-cancellable spinner instead).
class _SelectedSearchesLoadDialog extends StatelessWidget {
  final _SelectedSearchesLoadProgress progress;

  const _SelectedSearchesLoadDialog({required this.progress});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: AnimatedBuilder(
          animation: progress,
          builder: (context, child) {
            // Partial credit for the current search's own progress, not
            // just a discrete step per search -- smoother for a selection
            // with only a couple of large searches, where "step" progress
            // would otherwise sit at the same fraction for a long time.
            final overall = progress.searchCount > 0 ? (progress.searchIndex - 1 + (progress.total > 0 ? progress.loaded / progress.total : 0)) / progress.searchCount : null;
            final perSearch = progress.total > 0 ? progress.loaded / progress.total : null;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.searchesLoadingPostsDialogTitle(progress.searchIndex, progress.searchCount)),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: overall),
                const SizedBox(height: 16),
                Text(l10n.searchesLoadingPostsSearchProgress(progress.searchLabel, progress.loaded, progress.total)),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: perSearch),
              ],
            );
          },
        ),
      ),
    );
  }
}
