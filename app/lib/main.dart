import 'dart:async';

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
import 'services/download_manager.dart';
import 'services/download_queue_service.dart';
import 'services/flutter_local_notifications_queue_notifier.dart';
import 'settings/app_lock_service.dart';
import 'settings/display_settings_store.dart';
import 'settings/download_settings_store.dart';
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
  // Best-effort (M43) -- a platform this plugin doesn't support, or a denied
  // permission, must never block app startup; see the notifier's own doc
  // comment for why every one of its methods already swallows its own
  // exceptions.
  final notifier = FlutterLocalNotificationsQueueNotifier();
  await notifier.initialize();
  final downloadQueueService = DownloadQueueService(downloadManager: const DownloadManager(), downloadSettingsStore: const DownloadSettingsStore(), notifier: notifier);
  runApp(
    LittleBunnyApp(
      settingsStore: RepositorySettingsStore(secretStore),
      lockService: AppLockService(secretStore),
      themeSettingsStore: const ThemeSettingsStore(),
      displaySettingsStore: const DisplaySettingsStore(),
      downloadSettingsStore: const DownloadSettingsStore(),
      downloadQueueService: downloadQueueService,
    ),
  );
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
  final DisplaySettingsStore displaySettingsStore;
  final DownloadSettingsStore downloadSettingsStore;
  final DownloadQueueService downloadQueueService;

  const LittleBunnyApp({
    super.key,
    required this.settingsStore,
    required this.lockService,
    required this.themeSettingsStore,
    required this.displaySettingsStore,
    required this.downloadSettingsStore,
    required this.downloadQueueService,
  });

  @override
  State<LittleBunnyApp> createState() => _LittleBunnyAppState();
}

class _LittleBunnyAppState extends State<LittleBunnyApp> {
  BunnyRepository? _repository;
  bool _loading = true;
  bool _locked = false;
  // Instant, sensible defaults (match ThemeSettingsStore's own defaults) so
  // the very first frame doesn't flash the wrong theme before the real
  // values load.
  ThemeMode _themeMode = ThemeMode.dark;
  ThemeColorOption _themeColor = ThemeColorOption.purple;
  bool _amoled = false;
  String? _languageCode;

  @override
  void initState() {
    super.initState();
    _loadPersistedConfig();
    _loadThemeSettings();
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
    unawaited(widget.downloadQueueService.restore(repository));
  }

  Future<void> _loadThemeSettings() async {
    final mode = await widget.themeSettingsStore.load();
    final color = await widget.themeSettingsStore.loadColor();
    final amoled = await widget.themeSettingsStore.loadAmoled();
    final languageCode = await widget.themeSettingsStore.loadLanguageCode();
    if (!mounted) {
      return;
    }
    setState(() {
      _themeMode = mode;
      _themeColor = color;
      _amoled = amoled;
      _languageCode = languageCode;
    });
  }

  Future<void> _onConfigured(BunnyRepository repository) async {
    // Previously only ever called once at first launch, when _repository was
    // still null -- now also reachable from Settings (M15) to switch
    // standalone <-> networked mid-run, so the old repository must be closed
    // (kills the FFI isolate / closes the HTTP client) rather than just
    // dropped, or it would leak.
    await _repository?.close();
    final locked = await widget.lockService.isEnabled();
    if (!mounted) {
      return;
    }
    setState(() {
      _repository = repository;
      _locked = locked;
    });
    unawaited(widget.downloadQueueService.restore(repository));
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
      home = BunnyRepositoryScope(
        repository: _repository!,
        child: SearchesScreen(
          lockService: widget.lockService,
          themeSettingsStore: widget.themeSettingsStore,
          displaySettingsStore: widget.displaySettingsStore,
          downloadSettingsStore: widget.downloadSettingsStore,
          downloadQueueService: widget.downloadQueueService,
          settingsStore: widget.settingsStore,
          onThemeModeChanged: (mode) => setState(() => _themeMode = mode),
          onThemeColorChanged: (color) => setState(() => _themeColor = color),
          onAmoledChanged: (amoled) => setState(() => _amoled = amoled),
          onLanguageCodeChanged: (languageCode) => setState(() => _languageCode = languageCode),
          onRepositoryConfigured: _onConfigured,
        ),
      );
    }

    var darkColorScheme = ColorScheme.fromSeed(seedColor: _themeColor.seedColor, brightness: Brightness.dark);
    if (_amoled) {
      // "True black" (AMOLED) dark mode: every surface level flattened to
      // pure black, which actually saves power on OLED/AMOLED screens
      // (unlike Material 3's default dark surfaces, which are dark grey,
      // not black) -- scaffoldBackgroundColor below covers the one surface
      // ColorScheme itself doesn't drive.
      darkColorScheme = darkColorScheme.copyWith(
        surface: Colors.black,
        surfaceContainerLowest: Colors.black,
        surfaceContainerLow: Colors.black,
        surfaceContainer: Colors.black,
        surfaceContainerHigh: Colors.black,
        surfaceContainerHighest: Colors.black,
      );
    }

    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      localizationsDelegates: const [AppLocalizations.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      // Leaving `locale` unset lets Flutter's own resolution run (device
      // locale, falling back to supportedLocales' first entry/English if
      // the device's language isn't shipped yet) -- a manual override
      // (M30) is the only tier that needs explicit code, since it's the
      // only one that doesn't already happen on its own.
      locale: _languageCode == null ? null : Locale(_languageCode!),
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: _themeColor.seedColor, brightness: Brightness.light)),
      darkTheme: ThemeData(colorScheme: darkColorScheme, scaffoldBackgroundColor: _amoled ? Colors.black : null),
      themeMode: _themeMode,
      home: home,
    );
  }
}
