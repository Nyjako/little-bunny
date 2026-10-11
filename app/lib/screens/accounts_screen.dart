import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../settings/display_settings_store.dart';
import '../settings/download_settings_store.dart';
import '../settings/sync_settings_store.dart';
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
  final SyncSettingsStore syncSettingsStore;
  final DownloadSettingsStore downloadSettingsStore;

  const AccountsScreen({super.key, required this.repository, required this.displaySettingsStore, required this.syncSettingsStore, required this.downloadSettingsStore});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  Future<Map<BunnySite, BunnyAccount?>>? _accountsFuture;

  @override
  void initState() {
    super.initState();
    _accountsFuture = _loadAccounts();
  }

  Future<Map<BunnySite, BunnyAccount?>> _loadAccounts() async {
    final repository = widget.repository;
    final results = await Future.wait([repository.getAccount(BunnySite.e621), repository.getAccount(BunnySite.inkbunny)]);
    return {BunnySite.e621: results[0], BunnySite.inkbunny: results[1]};
  }

  void _refresh() {
    setState(() {
      _accountsFuture = _loadAccounts();
    });
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
          syncSettingsStore: widget.syncSettingsStore,
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
          syncSettingsStore: widget.syncSettingsStore,
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
      body: FutureBuilder<Map<BunnySite, BunnyAccount?>>(
        future: _accountsFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final accounts = snapshot.data!;
          return ListView(
            children: BunnySite.values.map((site) {
              final account = accounts[site];
              return ListTile(
                title: Text(site.toWireString()),
                subtitle: Text(account != null ? l10n.accountsLoggedInAs(account.username) : l10n.accountsNotConnected),
                trailing: account == null
                    ? null
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
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
