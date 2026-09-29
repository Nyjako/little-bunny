import 'package:flutter/material.dart';

import '../bunny_repository_scope.dart';
import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../settings/app_lock_service.dart';
import 'login_form_screen.dart';
import 'lock_setup_screen.dart';

/// The interim real "home" page (M7.3), replacing M6's placeholder: lists
/// both sites' configured accounts and lets the user log in/remove them.
/// Browse/search (M8) will build on top of this rather than replace it.
class AccountsScreen extends StatefulWidget {
  final AppLockService lockService;

  const AccountsScreen({super.key, required this.lockService});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  BunnyRepository? _repository;
  Future<Map<BunnySite, BunnyAccount?>>? _accountsFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _repository = BunnyRepositoryScope.of(context);
    _accountsFuture ??= _loadAccounts();
  }

  Future<Map<BunnySite, BunnyAccount?>> _loadAccounts() async {
    final repository = _repository!;
    final results = await Future.wait([repository.getAccount(BunnySite.e621), repository.getAccount(BunnySite.inkbunny)]);
    return {BunnySite.e621: results[0], BunnySite.inkbunny: results[1]};
  }

  void _refresh() {
    setState(() {
      _accountsFuture = _loadAccounts();
    });
  }

  Future<void> _openLoginForm(BunnySite site) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (context) => LoginFormScreen(site: site, repository: _repository!)));
    if (saved == true) {
      _refresh();
    }
  }

  Future<void> _removeAccount(BunnySite site) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove account?'),
        content: Text('This removes the saved ${site.toWireString()} account from this app. You can log in again later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await _repository!.deleteAccount(site);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: [
          IconButton(icon: const Icon(Icons.lock_outline), tooltip: 'App lock', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => LockSetupScreen(lockService: widget.lockService)))),
        ],
      ),
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
                subtitle: Text(account != null ? 'Logged in as ${account.username}' : 'Not connected'),
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
