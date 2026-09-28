import 'package:flutter/material.dart';

import 'repository/bunny_repository.dart';
import 'repository/bunny_repository_factory.dart';
import 'screens/setup_screen.dart';
import 'settings/repository_settings_store.dart';
import 'settings/secret_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(LittleBunnyApp(settingsStore: RepositorySettingsStore(FlutterSecureStorageSecretStore())));
}

/// Makes the active [BunnyRepository] available to the widget tree without
/// each screen needing to know which implementation is active -- the "one
/// repository interface" wiring the M6 roadmap entry describes.
class BunnyRepositoryScope extends InheritedWidget {
  final BunnyRepository repository;

  const BunnyRepositoryScope({super.key, required this.repository, required super.child});

  static BunnyRepository of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<BunnyRepositoryScope>()!.repository;

  @override
  bool updateShouldNotify(BunnyRepositoryScope oldWidget) => repository != oldWidget.repository;
}

/// Root widget: on boot, tries to load a persisted [BunnyRepositoryConfig]
/// (M7.2); if none exists yet (first launch), shows [SetupScreen] until one
/// is chosen and confirmed to work. Only ever depends on the abstract
/// [BunnyRepository] interface once configured, regardless of which
/// implementation M6.2 (FFI) or M6.3 (HTTP) built.
class LittleBunnyApp extends StatefulWidget {
  final RepositorySettingsStore settingsStore;

  const LittleBunnyApp({super.key, required this.settingsStore});

  @override
  State<LittleBunnyApp> createState() => _LittleBunnyAppState();
}

class _LittleBunnyAppState extends State<LittleBunnyApp> {
  BunnyRepository? _repository;
  bool _loading = true;

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
    if (!mounted) {
      return;
    }
    setState(() {
      _repository = repository;
      _loading = false;
    });
  }

  void _onConfigured(BunnyRepository repository) {
    setState(() => _repository = repository);
  }

  @override
  Widget build(BuildContext context) {
    final Widget home;
    if (_loading) {
      home = const Scaffold(body: Center(child: CircularProgressIndicator()));
    } else if (_repository == null) {
      home = SetupScreen(settingsStore: widget.settingsStore, onConfigured: _onConfigured);
    } else {
      home = BunnyRepositoryScope(repository: _repository!, child: const _PlaceholderHomePage());
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

/// App shell (M6/M7.2). No real screens yet -- login is M7.3, app-lock is
/// M7.4, browse/search is M8. This just proves the app boots on top of the
/// repository interface and the M7.2 settings/setup flow.
class _PlaceholderHomePage extends StatelessWidget {
  const _PlaceholderHomePage();

  @override
  Widget build(BuildContext context) {
    final repository = BunnyRepositoryScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('LittleBunny')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('App shell (M6) -- no screens yet.'),
            Text('Active repository: ${repository.runtimeType}'),
          ],
        ),
      ),
    );
  }
}
