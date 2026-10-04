import 'package:flutter/material.dart';

import '../bunny_repository_scope.dart';
import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../settings/app_lock_service.dart';
import '../settings/sync_settings_store.dart';
import '../settings/theme_settings_store.dart';
import 'accounts_screen.dart';
import 'create_search_screen.dart';
import 'post_grid_screen.dart';
import 'settings_screen.dart';

/// The app's actual home screen (M8.2 promoted this over [AccountsScreen] --
/// browse/search is the daily-use surface, site login is a one-time setup
/// concern). Lists saved searches; each will open a post grid (M8.3) once
/// that exists.
class SearchesScreen extends StatefulWidget {
  final AppLockService lockService;
  final ThemeSettingsStore themeSettingsStore;
  final SyncSettingsStore syncSettingsStore;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  const SearchesScreen({super.key, required this.lockService, required this.themeSettingsStore, required this.syncSettingsStore, required this.onThemeModeChanged});

  @override
  State<SearchesScreen> createState() => _SearchesScreenState();
}

class _SearchesScreenState extends State<SearchesScreen> {
  BunnyRepository? _repository;
  Future<List<BunnySearch>>? _searchesFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _repository = BunnyRepositoryScope.of(context);
    _searchesFuture ??= _repository!.listSearches();
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.searchesScreenTitle),
        actions: [
          IconButton(icon: const Icon(Icons.person_outline), tooltip: l10n.searchesAccountsTooltip, onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => AccountsScreen(repository: _repository!)))),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.searchesSettingsTooltip,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    SettingsScreen(themeSettingsStore: widget.themeSettingsStore, lockService: widget.lockService, syncSettingsStore: widget.syncSettingsStore, onThemeModeChanged: widget.onThemeModeChanged),
              ),
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<BunnySearch>>(
        future: _searchesFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final searches = snapshot.data!;
          if (searches.isEmpty) {
            return Center(child: Text(l10n.searchesEmptyState));
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
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => PostGridScreen(search: search, repository: _repository!))),
                  ),
                )
                .toList(),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(onPressed: _createSearch, tooltip: l10n.searchesNewSearchTooltip, child: const Icon(Icons.add)),
    );
  }
}
