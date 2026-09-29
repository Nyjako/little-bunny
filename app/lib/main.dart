import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:fvp/fvp.dart' as fvp;

import 'bunny_repository_scope.dart';
import 'l10n/app_localizations.dart';
import 'repository/bunny_repository.dart';
import 'repository/bunny_repository_factory.dart';
import 'screens/lock_screen.dart';
import 'screens/searches_screen.dart';
import 'screens/setup_screen.dart';
import 'settings/app_lock_service.dart';
import 'settings/repository_settings_store.dart';
import 'settings/secret_store.dart';
import 'settings/theme_settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // video_player has no official Linux/Windows implementation; fvp fills the
  // gap for exactly those platforms via its own bundled decoder, leaving
  // Android/iOS on video_player's official backend untouched.
  fvp.registerWith(options: {'platforms': ['windows', 'linux']});
  final secretStore = FlutterSecureStorageSecretStore();
  runApp(LittleBunnyApp(settingsStore: RepositorySettingsStore(secretStore), lockService: AppLockService(secretStore), themeSettingsStore: const ThemeSettingsStore()));
}

/// Root widget: on boot, tries to load a persisted [BunnyRepositoryConfig]
/// (M7.2); if none exists yet (first launch), shows [SetupScreen] until one
/// is chosen and confirmed to work. Once a repository is ready, gates it
/// behind [LockScreen] if app-lock (M7.4) is enabled. Only ever depends on
/// the abstract [BunnyRepository] interface once configured, regardless of
/// which implementation M6.2 (FFI) or M6.3 (HTTP) built. The chosen
/// [ThemeMode] is loaded independently of all of that, since even
/// [SetupScreen]/[LockScreen] should respect it.
class LittleBunnyApp extends StatefulWidget {
  final RepositorySettingsStore settingsStore;
  final AppLockService lockService;
  final ThemeSettingsStore themeSettingsStore;

  const LittleBunnyApp({super.key, required this.settingsStore, required this.lockService, required this.themeSettingsStore});

  @override
  State<LittleBunnyApp> createState() => _LittleBunnyAppState();
}

class _LittleBunnyAppState extends State<LittleBunnyApp> {
  BunnyRepository? _repository;
  bool _loading = true;
  bool _locked = false;
  // Instant, sensible default (matches ThemeSettingsStore's own default) so
  // the very first frame doesn't flash light before the real value loads.
  ThemeMode _themeMode = ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    _loadPersistedConfig();
    _loadThemeMode();
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

  Future<void> _loadThemeMode() async {
    final mode = await widget.themeSettingsStore.load();
    if (!mounted) {
      return;
    }
    setState(() => _themeMode = mode);
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
      home = BunnyRepositoryScope(repository: _repository!, child: SearchesScreen(lockService: widget.lockService, themeSettingsStore: widget.themeSettingsStore, onThemeModeChanged: (mode) => setState(() => _themeMode = mode)));
    }

    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      localizationsDelegates: const [AppLocalizations.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.light)),
      darkTheme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.dark)),
      themeMode: _themeMode,
      home: home,
    );
  }
}
