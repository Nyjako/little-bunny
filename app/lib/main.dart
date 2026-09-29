import 'package:flutter/material.dart';

import 'bunny_repository_scope.dart';
import 'repository/bunny_repository.dart';
import 'repository/bunny_repository_factory.dart';
import 'screens/accounts_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/setup_screen.dart';
import 'settings/app_lock_service.dart';
import 'settings/repository_settings_store.dart';
import 'settings/secret_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final secretStore = FlutterSecureStorageSecretStore();
  runApp(LittleBunnyApp(settingsStore: RepositorySettingsStore(secretStore), lockService: AppLockService(secretStore)));
}

/// Root widget: on boot, tries to load a persisted [BunnyRepositoryConfig]
/// (M7.2); if none exists yet (first launch), shows [SetupScreen] until one
/// is chosen and confirmed to work. Once a repository is ready, gates it
/// behind [LockScreen] if app-lock (M7.4) is enabled. Only ever depends on
/// the abstract [BunnyRepository] interface once configured, regardless of
/// which implementation M6.2 (FFI) or M6.3 (HTTP) built.
class LittleBunnyApp extends StatefulWidget {
  final RepositorySettingsStore settingsStore;
  final AppLockService lockService;

  const LittleBunnyApp({super.key, required this.settingsStore, required this.lockService});

  @override
  State<LittleBunnyApp> createState() => _LittleBunnyAppState();
}

class _LittleBunnyAppState extends State<LittleBunnyApp> {
  BunnyRepository? _repository;
  bool _loading = true;
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    _loadPersistedConfig();
  }

  Future<void> _loadPersistedConfig() async {
    final config = await widget.settingsStore.load();
    if (config == null) {
      if (mounted) {
        setState(() => _loading = false);
      }
      return;
    }
    final repository = await createBunnyRepository(config);
    final locked = await widget.lockService.isEnabled();
    if (!mounted) {
      return;
    }
    setState(() {
      _repository = repository;
      _locked = locked;
      _loading = false;
    });
  }

  Future<void> _onConfigured(BunnyRepository repository) async {
    final locked = await widget.lockService.isEnabled();
    if (!mounted) {
      return;
    }
    setState(() {
      _repository = repository;
      _locked = locked;
    });
  }

  void _onUnlocked() {
    setState(() => _locked = false);
  }

  @override
  Widget build(BuildContext context) {
    final Widget home;
    if (_loading) {
      home = const Scaffold(body: Center(child: CircularProgressIndicator()));
    } else if (_repository == null) {
      home = SetupScreen(settingsStore: widget.settingsStore, onConfigured: _onConfigured);
    } else if (_locked) {
      home = LockScreen(lockService: widget.lockService, onUnlocked: _onUnlocked);
    } else {
      home = BunnyRepositoryScope(repository: _repository!, child: AccountsScreen(lockService: widget.lockService));
    }

    return MaterialApp(
      title: 'LittleBunny',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: home,
    );
  }
}
