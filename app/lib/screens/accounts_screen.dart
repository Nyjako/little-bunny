import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import 'login_form_screen.dart';

/// Site login management (M7.3) -- reachable from [SearchesScreen]'s app bar
/// (M8.2 promoted browse/search to the app's actual home, since that's the
/// daily-use surface; this screen only matters when setting up or changing
/// site credentials). Takes [repository] explicitly rather than through
/// `BunnyRepositoryScope.of(context)` -- it's only ever reached via
/// `Navigator.push`, which puts it in a separate route subtree from
/// wherever the scope is set up, same reasoning as [LoginFormScreen] and
/// `CreateSearchScreen`.
class AccountsScreen extends StatefulWidget {
  final BunnyRepository repository;

  const AccountsScreen({super.key, required this.repository});

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
                trailing: account != null ? IconButton(icon: const Icon(Icons.delete), onPressed: () => _removeAccount(site)) : null,
                onTap: account == null ? () => _openLoginForm(site) : null,
              );
            }).toList(),
          );
        },
      ),
    );
  }
}
