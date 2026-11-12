import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'bunny_repository_scope.dart';
import 'l10n/app_localizations.dart';
import 'native_dependency_licenses.dart';
import 'repository/bunny_repository.dart';
import 'repository/bunny_repository_factory.dart';
import 'screens/lock_screen.dart';
import 'screens/searches_screen.dart';
import 'screens/setup_screen.dart';
import 'services/android_foreground_service_queue_notifier.dart';
import 'services/download_manager.dart';
import 'services/download_queue_service.dart';
import 'services/flutter_local_notifications_queue_notifier.dart';
import 'services/preview_cache_service.dart';
import 'settings/app_lock_service.dart';
import 'settings/display_settings_store.dart';
import 'settings/download_settings_store.dart';
import 'settings/repository_settings_store.dart';
import 'settings/secret_store.dart';
import 'settings/theme_settings_store.dart';
import 'settings/update_settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerNativeDependencyLicenses();
  // video_player has no official Linux/Windows implementation; fvp fills the
  // gap for exactly those platforms via its own bundled decoder, leaving
  // Android/iOS on video_player's official backend untouched.
  fvp.registerWith(options: {'platforms': ['windows', 'linux']});
  // just_audio (M28 Phase 4) has the same gap on Linux/Windows -- media_kit
  // fills it here too. Android/iOS/macOS keep just_audio's own official
  // backend untouched (default-disabled above).
  JustAudioMediaKit.ensureInitialized();
  final secretStore = FlutterSecureStorageSecretStore();
  // Best-effort (M43) -- a platform this plugin doesn't support, or a denied
  // permission, must never block app startup; see the notifier's own doc
  // comment for why every one of its methods already swallows its own
  // exceptions. Still initialized on Android even though
  // AndroidForegroundServiceQueueNotifier (M57) handles the actual queue
  // notifications there -- this is what requests the POST_NOTIFICATIONS
  // runtime permission and creates the shared "download_queue" channel the
  // native foreground service's own notification reuses.
  final flnNotifier = FlutterLocalNotificationsQueueNotifier();
  await flnNotifier.initialize();
  final androidNotifier = Platform.isAndroid ? AndroidForegroundServiceQueueNotifier() : null;
  final notifier = androidNotifier ?? flnNotifier;
  final downloadQueueService = DownloadQueueService(downloadManager: const DownloadManager(), downloadSettingsStore: const DownloadSettingsStore(), notifier: notifier);
  // Reads _activeRepository live (not a snapshot taken here) -- by the time
  // this actually fires (a real notification tap, well after this closure
  // is created), _LittleBunnyAppState may have replaced it via a mode
  // switch, or it may still be null if nothing's configured yet.
  void onResumeRequested() {
    final repository = _activeRepository;
    if (repository != null) {
      downloadQueueService.resume(repository);
    }
  }

  flnNotifier.onResumeRequested = onResumeRequested;
  if (androidNotifier != null) {
    androidNotifier.onResumeRequested = onResumeRequested;
    // Covers a "Resume" tap that launched a fresh engine -- MainActivity.kt
    // only stores that case rather than pushing it immediately, since this
    // handler couldn't have been registered yet at that point.
    unawaited(androidNotifier.checkPendingResumeRequest());
  }
  runApp(
    LittleBunnyApp(
      settingsStore: RepositorySettingsStore(secretStore),
      lockService: AppLockService(secretStore),
      themeSettingsStore: const ThemeSettingsStore(),
      displaySettingsStore: const DisplaySettingsStore(),
      downloadSettingsStore: const DownloadSettingsStore(),
      downloadQueueService: downloadQueueService,
      updateSettingsStore: const UpdateSettingsStore(),
    ),
  );
}

/// The currently-active repository, if any -- kept outside the widget tree
/// (unlike `_LittleBunnyAppState._repository`, which this mirrors) so
/// [FlutterLocalNotificationsQueueNotifier.onResumeRequested]'s closure
/// (set up in [main], before any widget exists) has something to read when
/// a notification action fires (M65). `_LittleBunnyAppState` updates this
/// alongside every `_repository = ...` assignment of its own.
BunnyRepository? _activeRepository;

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
  final UpdateSettingsStore updateSettingsStore;

  const LittleBunnyApp({
    super.key,
    required this.settingsStore,
    required this.lockService,
    required this.themeSettingsStore,
    required this.displaySettingsStore,
    required this.downloadSettingsStore,
    required this.downloadQueueService,
    required this.updateSettingsStore,
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

  /// Needs no settings/notifier wiring (unlike [DownloadQueueService] above),
  /// so this is just a plain field rather than something [main] has to
  /// create before [runApp] -- shared app-wide purely so a preview warmed
  /// from the stats screen's recommendations is still warm by the time
  /// [TagBrowseScreen] actually opens it.
  final _previewCacheService = PreviewCacheService();

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
    _activeRepository = repository;
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
    _activeRepository = repository;
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
      home = SearchesScreen(
        lockService: widget.lockService,
        themeSettingsStore: widget.themeSettingsStore,
        displaySettingsStore: widget.displaySettingsStore,
        downloadSettingsStore: widget.downloadSettingsStore,
        downloadQueueService: widget.downloadQueueService,
        previewCacheService: _previewCacheService,
        settingsStore: widget.settingsStore,
        updateSettingsStore: widget.updateSettingsStore,
        onThemeModeChanged: (mode) => setState(() => _themeMode = mode),
        onThemeColorChanged: (color) => setState(() => _themeColor = color),
        onAmoledChanged: (amoled) => setState(() => _amoled = amoled),
        onLanguageCodeChanged: (languageCode) => setState(() => _languageCode = languageCode),
        onRepositoryConfigured: _onConfigured,
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

    final app = MaterialApp(
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
    // Wraps the whole MaterialApp, not just `home` -- `home`'s own content
    // only ever becomes the *first* route's widget subtree; a screen reached
    // via Navigator.push (DownloadQueueScreen, PostGridScreen, ...) lives in
    // a separate route subtree that's a sibling of it under the Navigator's
    // Overlay, not a descendant. Scoping this only around `home` meant every
    // pushed screen calling BunnyRepositoryScope.of(context) hit a null
    // ancestor and crashed with a null-check error -- undetected by the
    // widget tests, which pump each screen wrapped in its own standalone
    // BunnyRepositoryScope rather than through real app navigation. Scoping
    // around the whole MaterialApp instead makes it an ancestor of the
    // Navigator itself, hence of every route pushed onto it.
    return _repository == null ? app : BunnyRepositoryScope(repository: _repository!, child: app);
  }
}
