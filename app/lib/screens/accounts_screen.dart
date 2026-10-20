import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../settings/display_settings_store.dart';
import '../settings/download_settings_store.dart';
import 'login_form_screen.dart';
import 'tag_browse_screen.dart';

/// Site login management (M7.3) -- reachable from [SearchesScreen]'s app bar
/// (M8.2 promoted browse/search to the app's actual home, since that's the
/// daily-use surface; this screen only matters when setting up or changing
/// site credentials). Takes [repository] explicitly rather than through
/// `BunnyRepositoryScope.of(context)` -- it's only ever reached via
/// `Navigator.push`, which puts it in a separate route subtree from
/// wherever the scope is set up, same reasoning as [LoginFormScreen] and
/// `CreateSearchScreen`. The three settings stores (unused by this screen's
/// own UI) are only here to pass through to [TagBrowseScreen] for the
/// "view my favorites" heart icon (M10.3).
class AccountsScreen extends StatefulWidget {
  final BunnyRepository repository;
  final DisplaySettingsStore displaySettingsStore;
  final DownloadSettingsStore downloadSettingsStore;

  const AccountsScreen({super.key, required this.repository, required this.displaySettingsStore, required this.downloadSettingsStore});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

typedef _AccountsData = ({Map<BunnySite, BunnyAccount?> accounts, List<BunnySearch> searches});

class _AccountsScreenState extends State<AccountsScreen> {
  Future<_AccountsData>? _dataFuture;

  /// Which sites currently have a manual favorites sync in flight -- a set
  /// rather than a single flag, mirroring [SearchesScreen]'s per-row sync
  /// tracking, since both accounts can be synced independently.
  final Set<BunnySite> _syncingFavorites = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dataFuture ??= _loadData();
  }

  Future<_AccountsData> _loadData() async {
    // Read before the first `await` below -- same reasoning as
    // [SearchesScreen]'s own version of this method: this can run again from
    // a later setState, where `context` can't be trusted to still be valid.
    final label = AppLocalizations.of(context)!.searchesFavoritesLabel;
    final repository = widget.repository;
    final results = await Future.wait([repository.getAccount(BunnySite.e621), repository.getAccount(BunnySite.inkbunny)]);
    final accounts = {BunnySite.e621: results[0], BunnySite.inkbunny: results[1]};
    var searches = await repository.listSearches();
    if (await _ensureFavoritesSearches(accounts, searches, label)) {
      searches = await repository.listSearches();
    }
    return (accounts: accounts, searches: searches);
  }

  /// Auto-creates a "Favorites" search (M27, moved here from [SearchesScreen]
  /// in M30 once the dedicated Favorites tab was removed) for every
  /// configured account that doesn't already have one -- the `pool:<id>`
  /// -style sentinel-query trick [BunnySearch.isFavorites] documents, so an
  /// account's favorites get cached/paginated/synced through the exact same
  /// machinery as any other saved search, with no dedicated
  /// favorites-fetching code anywhere else in the app. Runs on every load
  /// (cheap: a skip-if-present check) rather than only right after account
  /// setup, so it's self-healing if the search is ever deleted and covers
  /// accounts configured before this screen is visited again. Returns true
  /// if anything was created, so the caller knows to reload [listSearches].
  Future<bool> _ensureFavoritesSearches(Map<BunnySite, BunnyAccount?> accounts, List<BunnySearch> existing, String label) async {
    var created = false;
    for (final site in BunnySite.values) {
      final account = accounts[site];
      if (account == null) {
        continue;
      }
      if (existing.any((search) => search.site == site && search.isFavorites)) {
        continue;
      }
      final query = site == BunnySite.e621 ? 'fav:${account.username}' : 'favorited_by:me';
      await widget.repository.createSearch(site, label, query);
      created = true;
    }
    return created;
  }

  void _refresh() {
    setState(() {
      _dataFuture = _loadData();
    });
  }

  BunnySearch? _favoritesSearchFor(List<BunnySearch> searches, BunnySite site) => searches.where((search) => search.site == site && search.isFavorites).firstOrNull;

  /// Manual sync (no per-search editing/pinning/interval UI here, unlike a
  /// normal search row -- the user explicitly asked for just a count + sync
  /// button). Background sync at the search's own default interval already
  /// happens server-side regardless of whether this screen is ever opened.
  Future<void> _syncFavorites(BunnySearch search) async {
    setState(() => _syncingFavorites.add(search.site));
    try {
      await widget.repository.syncSearch(search.id);
      while (mounted) {
        final status = await widget.repository.getSyncStatus();
        if (!status.active) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }
    } catch (_) {
      // Same tolerance as SearchesScreen's per-row sync -- leave it, the
      // user can retry.
    }
    if (!mounted) {
      return;
    }
    setState(() => _syncingFavorites.remove(search.site));
    _refresh();
  }

  Future<void> _openLoginForm(BunnySite site) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (context) => LoginFormScreen(site: site, repository: widget.repository)));
    if (saved == true) {
      _refresh();
    }
  }

  Future<void> _removeAccount(BunnySite site) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.accountsRemoveDialogTitle),
        content: Text(l10n.accountsRemoveDialogContent(site.toWireString())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.commonCancel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.commonRemove)),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await widget.repository.deleteAccount(site);
    _refresh();
  }

  /// e621's own tag-search syntax treats `fav:<username>` as a literal query
  /// -- `previewSearch`/`TagBrowseScreen` already handle this with zero
  /// backend changes, the same way `pool:<id>` already does (M10.3).
  Future<void> _openMyE621Favorites(String username) async {
    final l10n = AppLocalizations.of(context)!;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TagBrowseScreen(
          site: BunnySite.e621,
          query: 'fav:$username',
          title: l10n.accountsMyFavoritesTitle,
          repository: widget.repository,
          displaySettingsStore: widget.displaySettingsStore,
          downloadSettingsStore: widget.downloadSettingsStore,
        ),
      ),
    );
  }

  /// Inkbunny has no equivalent query syntax -- it needs the logged-in
  /// account's own numeric user id in a dedicated search param instead,
  /// resolved entirely server/core-side via [BunnyRepository.
  /// myInkbunnyFavorites] (M10.3), so this uses [TagBrowseScreen]'s
  /// `customFetch` override rather than a crafted query string.
  Future<void> _openMyInkbunnyFavorites() async {
    final l10n = AppLocalizations.of(context)!;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TagBrowseScreen(
          site: BunnySite.inkbunny,
          query: '',
          title: l10n.accountsMyFavoritesTitle,
          customFetch: (page) => widget.repository.myInkbunnyFavorites(page: page),
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
      appBar: AppBar(title: Text(l10n.accountsScreenTitle)),
      body: FutureBuilder<_AccountsData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final accounts = snapshot.data!.accounts;
          final searches = snapshot.data!.searches;
          return ListView(
            children: BunnySite.values.map((site) {
              final account = accounts[site];
              final favoritesSearch = account == null ? null : _favoritesSearchFor(searches, site);
              final syncing = _syncingFavorites.contains(site);
              return ListTile(
                title: Text(site.toWireString()),
                subtitle: Text(
                  account == null
                      ? l10n.accountsNotConnected
                      : favoritesSearch == null
                      ? l10n.accountsLoggedInAs(account.username)
                      : '${l10n.accountsLoggedInAs(account.username)} · ${l10n.accountsFavoritesCount(favoritesSearch.totalCount)}',
                ),
                trailing: account == null
                    ? null
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (favoritesSearch != null)
                            IconButton(
                              icon: syncing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync),
                              tooltip: l10n.accountsSyncFavoritesTooltip,
                              onPressed: syncing ? null : () => _syncFavorites(favoritesSearch),
                            ),
                          IconButton(
                            icon: const Icon(Icons.favorite),
                            tooltip: l10n.accountsMyFavoritesTooltip,
                            onPressed: site == BunnySite.e621 ? () => _openMyE621Favorites(account.username) : () => _openMyInkbunnyFavorites(),
                          ),
                          IconButton(icon: const Icon(Icons.delete), onPressed: () => _removeAccount(site)),
                        ],
                      ),
                onTap: account == null ? () => _openLoginForm(site) : null,
              );
            }).toList(),
          );
        },
      ),
    );
  }
}
