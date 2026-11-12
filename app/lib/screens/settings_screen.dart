import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:saf_util/saf_util.dart';

import '../l10n/app_localizations.dart';
import '../l10n/translation_completeness.dart';
import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../repository/bunny_repository_factory.dart';
import '../repository/http_bunny_repository.dart';
import '../services/download_queue_service.dart';
import '../services/search_backup_service.dart';
import '../settings/app_lock_service.dart';
import '../settings/display_settings_store.dart';
import '../settings/download_settings_store.dart';
import '../settings/repository_settings_store.dart';
import '../settings/theme_settings_store.dart';
import '../settings/update_settings_store.dart';
import '../util/post_navigation.dart';
import '../util/tag_query.dart';
import 'about_screen.dart';
import 'connection_qr_screen.dart';
import 'lock_setup_screen.dart';
import 'server_logs_screen.dart';
import 'setup_screen.dart';
import 'task_queue_screen.dart';

/// One place for cross-cutting app preferences -- reachable from
/// [AccountsScreen]'s app bar. Structured so adding more appearance options
/// later (or more sections entirely) doesn't need a redesign: each concern
/// (theme, app lock, sync, display, downloads, backup) is its own section
/// backed by its own settings store.
class SettingsScreen extends StatefulWidget {
  final BunnyRepository repository;
  final ThemeSettingsStore themeSettingsStore;
  final AppLockService lockService;
  final DisplaySettingsStore displaySettingsStore;
  final DownloadSettingsStore downloadSettingsStore;
  final DownloadQueueService downloadQueueService;
  final RepositorySettingsStore settingsStore;
  final UpdateSettingsStore updateSettingsStore;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<ThemeColorOption> onThemeColorChanged;
  final ValueChanged<bool> onAmoledChanged;
  final ValueChanged<String?> onLanguageCodeChanged;
  final ValueChanged<BunnyRepository> onRepositoryConfigured;

  const SettingsScreen({
    super.key,
    required this.repository,
    required this.themeSettingsStore,
    required this.lockService,
    required this.displaySettingsStore,
    required this.downloadSettingsStore,
    required this.downloadQueueService,
    required this.settingsStore,
    required this.updateSettingsStore,
    required this.onThemeModeChanged,
    required this.onThemeColorChanged,
    required this.onAmoledChanged,
    required this.onLanguageCodeChanged,
    required this.onRepositoryConfigured,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  BunnyRepositoryConfig? _repositoryConfig;
  ThemeMode? _themeMode;
  ThemeColorOption? _themeColor;
  bool _amoled = false;
  String? _languageCode;
  /// Keyed by language code, English excluded -- see
  /// [loadTranslationCompletenessPercent]'s own doc comment. Loaded by
  /// [_loadTranslationCompleteness]; a code missing from this map (still
  /// loading, or its ARB asset wasn't found) just shows no percentage.
  Map<String, int> _translationCompletenessPercent = const {};
  PreviewQuality? _previewQuality;
  String? _downloadFolder;
  bool _autoFavoriteOnDownload = false;
  bool _autoUpvoteOnDownload = false;
  bool _autoCheckForUpdates = true;
  final _intervalController = TextEditingController();
  final _gridColumnsController = TextEditingController();
  final _preloadCountController = TextEditingController();

  static const _backupService = SearchBackupService();

  /// Non-null only while [_importSearches]'s create loop is running --
  /// mirrors `PostGridScreen._massDownloadProgress`'s "replace the action's
  /// own label with a running count, re-enable on completion" shape (M9.5).
  (int, int)? _importProgress;

  BunnySite _blacklistSite = BunnySite.e621;
  List<String> _blacklistTags = [];
  final _blacklistTagController = TextEditingController();
  bool _syncingE621Blacklist = false;

  /// Byte offset of the first syntax problem in the add field's current
  /// text (M28/M54), or null if it's valid (including empty -- see
  /// bunny_tag_query_validate's own doc comment on why an empty query is
  /// vacuously valid, not an error). Debounced so every keystroke doesn't
  /// round-trip through validateTagQuery.
  int? _blacklistQueryError;
  Timer? _blacklistValidateDebounce;

  /// Suggestions for the tag token under the cursor in the add field (M54)
  /// -- same debounced `tagAutocomplete` pattern as `CreateSearchScreen`'s
  /// query field, since a blacklist "line" is really a full tag-query
  /// expression (M28), not just a single bare tag, so autocompleting
  /// whichever token the cursor is currently in (not just the trailing
  /// one) matters here too.
  List<BunnyTagStat> _blacklistSuggestions = [];
  Timer? _blacklistAutocompleteDebounce;

  @override
  void initState() {
    super.initState();
    _load();
    _loadTranslationCompleteness();
    _loadBlacklist();
    _blacklistTagController.addListener(_onBlacklistTagChanged);
    _blacklistTagController.addListener(_onBlacklistTagChangedAutocomplete);
  }

  @override
  void dispose() {
    _intervalController.dispose();
    _gridColumnsController.dispose();
    _preloadCountController.dispose();
    _blacklistValidateDebounce?.cancel();
    _blacklistAutocompleteDebounce?.cancel();
    _blacklistTagController.removeListener(_onBlacklistTagChanged);
    _blacklistTagController.removeListener(_onBlacklistTagChangedAutocomplete);
    _blacklistTagController.dispose();
    super.dispose();
  }

  void _onBlacklistTagChanged() {
    _blacklistValidateDebounce?.cancel();
    final text = _blacklistTagController.text;
    _blacklistValidateDebounce = Timer(const Duration(milliseconds: 300), () async {
      final errorPos = await widget.repository.validateTagQuery(_blacklistSite, text);
      if (mounted) {
        setState(() => _blacklistQueryError = errorPos);
      }
    });
  }

  int get _blacklistCursorOffset {
    final selectionOffset = _blacklistTagController.selection.baseOffset;
    return selectionOffset >= 0 ? selectionOffset : _blacklistTagController.text.length;
  }

  void _onBlacklistTagChangedAutocomplete() {
    _blacklistAutocompleteDebounce?.cancel();
    final text = _blacklistTagController.text;
    final (start, end) = tagTokenRangeAt(text, _blacklistCursorOffset);
    final (_, tag) = splitTagPrefix(text.substring(start, end));
    if (tag.length < tagAutocompleteMinPrefixLength || tagHasWildcard(tag)) {
      setState(() => _blacklistSuggestions = []);
      return;
    }
    _blacklistAutocompleteDebounce = Timer(const Duration(seconds: 3), () async {
      final suggestions = await widget.repository.tagAutocomplete(_blacklistSite, tag);
      if (mounted) {
        setState(() => _blacklistSuggestions = suggestions);
      }
    });
  }

  void _applyBlacklistSuggestion(String tag) {
    final (newText, newCursor) = applyTagSuggestion(_blacklistTagController.text, _blacklistCursorOffset, tag);
    _blacklistTagController.value = TextEditingValue(text: newText, selection: TextSelection.collapsed(offset: newCursor));
    setState(() => _blacklistSuggestions = []);
  }

  Future<void> _load() async {
    final repositoryConfig = await widget.settingsStore.load();
    final mode = await widget.themeSettingsStore.load();
    final themeColor = await widget.themeSettingsStore.loadColor();
    final amoled = await widget.themeSettingsStore.loadAmoled();
    final languageCode = await widget.themeSettingsStore.loadLanguageCode();
    final intervalHours = await widget.repository.getDefaultSyncIntervalHours();
    final previewQuality = await widget.displaySettingsStore.loadPreviewQuality();
    final gridColumns = await widget.displaySettingsStore.loadGridColumns();
    final preloadCount = await widget.displaySettingsStore.loadImagePreloadCount();
    final downloadFolder = await widget.downloadSettingsStore.loadDestinationFolder();
    final autoFavoriteOnDownload = await widget.downloadSettingsStore.loadAutoFavoriteOnDownload();
    final autoUpvoteOnDownload = await widget.downloadSettingsStore.loadAutoUpvoteOnDownload();
    final autoCheckForUpdates = await widget.updateSettingsStore.loadAutoCheckEnabled();
    if (!mounted) {
      return;
    }
    setState(() {
      _repositoryConfig = repositoryConfig;
      _themeMode = mode;
      _themeColor = themeColor;
      _amoled = amoled;
      _languageCode = languageCode;
      _intervalController.text = '$intervalHours';
      _previewQuality = previewQuality;
      _gridColumnsController.text = '$gridColumns';
      _preloadCountController.text = '$preloadCount';
      _downloadFolder = downloadFolder;
      _autoFavoriteOnDownload = autoFavoriteOnDownload;
      _autoUpvoteOnDownload = autoUpvoteOnDownload;
      _autoCheckForUpdates = autoCheckForUpdates;
    });
  }

  /// Separate from [_load] (and its own `setState`), not one more awaited
  /// step inside it -- this is purely decorative (a "(NN%)" suffix on the
  /// language picker), reads a bundled asset rather than a settings store
  /// like everything [_load] already awaits, and gating every other
  /// setting's own load on it buys nothing. Best-effort: a locale missing
  /// its bundled ARB asset just shows no percentage.
  Future<void> _loadTranslationCompleteness() async {
    try {
      final percent = await loadTranslationCompletenessPercent(AppLocalizations.supportedLocales.map((locale) => locale.languageCode));
      if (mounted) {
        setState(() => _translationCompletenessPercent = percent);
      }
    } catch (_) {
      // Ignored -- see above.
    }
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    await widget.themeSettingsStore.save(mode);
    widget.onThemeModeChanged(mode);
  }

  Future<void> _setThemeColor(ThemeColorOption color) async {
    setState(() => _themeColor = color);
    await widget.themeSettingsStore.saveColor(color);
    widget.onThemeColorChanged(color);
  }

  Future<void> _setAmoled(bool amoled) async {
    setState(() => _amoled = amoled);
    await widget.themeSettingsStore.saveAmoled(amoled);
    widget.onAmoledChanged(amoled);
  }

  Future<void> _setLanguageCode(String? languageCode) async {
    setState(() => _languageCode = languageCode);
    await widget.themeSettingsStore.saveLanguageCode(languageCode);
    widget.onLanguageCodeChanged(languageCode);
  }

  String _themeColorLabel(AppLocalizations l10n, ThemeColorOption color) => switch (color) {
    ThemeColorOption.purple => l10n.settingsThemeColorPurple,
    ThemeColorOption.blue => l10n.settingsThemeColorBlue,
    ThemeColorOption.green => l10n.settingsThemeColorGreen,
    ThemeColorOption.orange => l10n.settingsThemeColorOrange,
    ThemeColorOption.red => l10n.settingsThemeColorRed,
    ThemeColorOption.teal => l10n.settingsThemeColorTeal,
    ThemeColorOption.pink => l10n.settingsThemeColorPink,
  };

  /// Each supported locale's own name, in that language (not translated --
  /// "English" stays "English" regardless of which language is currently
  /// active, same convention most apps' own language pickers use so a user
  /// who doesn't read the current language can still find their own in the
  /// list). Falls back to the bare language code for anything not listed
  /// here yet, rather than crashing, when a new locale is added to
  /// AppLocalizations.supportedLocales before this map catches up.
  String _languageLabel(Locale locale) => switch (locale.languageCode) {
    'en' => 'English',
    'pl' => 'Polski',
    _ => locale.languageCode,
  };

  /// [_languageLabel] plus a "(NN%)" translation-completeness suffix for
  /// anything that isn't English (the template itself, always complete by
  /// definition -- see [loadTranslationCompletenessPercent]'s own doc
  /// comment) and that a percentage has actually loaded for yet.
  String _languageLabelWithCompleteness(Locale locale) {
    final label = _languageLabel(locale);
    if (locale.languageCode == 'en') {
      return label;
    }
    final percent = _translationCompletenessPercent[locale.languageCode];
    return percent == null ? label : '$label ($percent%)';
  }

  Future<void> _setDefaultIntervalHours(String value) async {
    final hours = int.tryParse(value);
    if (hours == null || hours <= 0) {
      return;
    }
    await widget.repository.setDefaultSyncIntervalHours(hours);
  }

  Future<void> _setPreviewQuality(PreviewQuality quality) async {
    setState(() => _previewQuality = quality);
    await widget.displaySettingsStore.savePreviewQuality(quality);
  }

  Future<void> _setGridColumns(String value) async {
    final columns = int.tryParse(value);
    if (columns == null || columns <= 0) {
      return;
    }
    await widget.displaySettingsStore.saveGridColumns(columns);
  }

  Future<void> _setImagePreloadCount(String value) async {
    final count = int.tryParse(value);
    if (count == null || count < 0) {
      return;
    }
    await widget.displaySettingsStore.saveImagePreloadCount(count);
  }

  /// `file_picker`'s own directory picker returns a `content://` URI on
  /// Android (Storage Access Framework) that `dart:io`'s `File`/`Directory`
  /// can't write to at all -- `file_picker` dropped its old SAF-write
  /// support in a rewrite, so Android uses the dedicated `saf_util` picker
  /// instead, requesting a *persistable* write grant so the chosen folder
  /// stays usable across app restarts. [DownloadManager] branches on
  /// whether the saved folder looks like a SAF URI to decide how to
  /// actually write files there (see its own doc comment).
  Future<void> _chooseDownloadFolder() async {
    String? chosen;
    if (Platform.isAndroid) {
      final picked = await SafUtil().pickDirectory(writePermission: true, persistablePermission: true);
      chosen = picked?.uri;
    } else {
      chosen = await FilePicker.getDirectoryPath();
    }
    if (chosen == null) {
      return;
    }
    setState(() => _downloadFolder = chosen);
    await widget.downloadSettingsStore.saveDestinationFolder(chosen);
  }

  Future<void> _setAutoFavoriteOnDownload(bool value) async {
    setState(() => _autoFavoriteOnDownload = value);
    await widget.downloadSettingsStore.saveAutoFavoriteOnDownload(value);
  }

  Future<void> _setAutoUpvoteOnDownload(bool value) async {
    setState(() => _autoUpvoteOnDownload = value);
    await widget.downloadSettingsStore.saveAutoUpvoteOnDownload(value);
  }

  Future<void> _setAutoCheckForUpdates(bool value) async {
    setState(() => _autoCheckForUpdates = value);
    await widget.updateSettingsStore.saveAutoCheckEnabled(value);
  }

  Future<void> _loadBlacklist() async {
    final tags = await widget.repository.getBlacklist(_blacklistSite);
    if (mounted) {
      setState(() => _blacklistTags = tags);
    }
  }

  Future<void> _setBlacklistSite(BunnySite site) async {
    setState(() => _blacklistSite = site);
    await _loadBlacklist();
    // The two sites' grammars differ (Inkbunny is a strict subset, M28/
    // M54) -- whatever's currently typed needs re-checking under the new
    // site's dialect, not just left showing the previous site's verdict.
    _onBlacklistTagChanged();
    _onBlacklistTagChangedAutocomplete();
  }

  Future<void> _addBlacklistTag() async {
    final tag = _blacklistTagController.text.trim();
    if (tag.isEmpty || _blacklistQueryError != null) {
      return;
    }
    await widget.repository.addBlacklistTag(_blacklistSite, tag);
    _blacklistTagController.clear();
    setState(() => _blacklistQueryError = null);
    await _loadBlacklist();
  }

  Future<void> _removeBlacklistTag(String tag) async {
    await widget.repository.removeBlacklistTag(_blacklistSite, tag);
    await _loadBlacklist();
  }

  Future<void> _syncE621Blacklist(AppLocalizations l10n) async {
    setState(() => _syncingE621Blacklist = true);
    try {
      final stats = await widget.repository.syncE621Blacklist();
      await _loadBlacklist();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.settingsBlacklistSyncE621Result(stats.added, stats.alreadyPresent, stats.skippedInvalid))));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.settingsBlacklistSyncE621Failed)));
      }
    } finally {
      if (mounted) {
        setState(() => _syncingE621Blacklist = false);
      }
    }
  }

  Future<void> _exportSearches(AppLocalizations l10n) async {
    final searches = await widget.repository.listSearches();
    final groups = await widget.repository.listGroups();
    final json = jsonEncode(_backupService.exportSearches(searches, groups));
    final saved = await FilePicker.saveFile(fileName: 'little_bunny_searches.json', bytes: Uint8List.fromList(utf8.encode(json)));
    if (!mounted || saved == null) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.settingsBackupExportSuccess(searches.length))));
  }

  /// Dedupes against the current `(site, query)` set so re-importing the
  /// same file is a no-op the second time (M11) -- mirrors the "queue N,
  /// drain once" mass-action shape elsewhere in this app by doing all the
  /// reads up front, then looping `createSearch` without re-checking
  /// anything already decided.
  Future<void> _importSearches(AppLocalizations l10n) async {
    final file = await FilePicker.pickFile();
    if (file == null) {
      return;
    }
    final contents = utf8.decode(await file.readAsBytes());
    final defaultIntervalHours = await widget.repository.getDefaultSyncIntervalHours();
    final parsed = _backupService.parseImportFile(contents, defaultIntervalHours: defaultIntervalHours);
    if (!mounted) {
      return;
    }
    if (parsed.format == ImportFormat.unrecognized) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.settingsBackupImportUnrecognizedFormat)));
      return;
    }

    final existing = (await widget.repository.listSearches()).map((search) => (search.site, search.query)).toSet();
    // Resolved/created on demand and cached by name so re-importing the same
    // file (or a file with multiple searches sharing a group) doesn't create
    // duplicate groups (M21) -- group ids aren't portable across installs,
    // so matching is by name against this install's existing groups.
    final groupIdsByName = {for (final group in await widget.repository.listGroups()) group.name: group.id};
    var imported = 0;
    var duplicates = 0;
    setState(() => _importProgress = (0, parsed.entries.length));
    for (final entry in parsed.entries) {
      final key = (entry.site, entry.query);
      if (existing.contains(key)) {
        duplicates++;
      } else {
        final id = await widget.repository.createSearch(entry.site, entry.label, entry.query, intervalHours: entry.intervalHours, autoFavorite: entry.autoFavorite, autoFavoriteStars: entry.autoFavoriteStars, autoUpvote: entry.autoUpvote);
        if (entry.pinned) {
          await widget.repository.setSearchPinned(id, true);
        }
        final groupName = entry.groupName;
        if (groupName != null) {
          final groupId = groupIdsByName[groupName] ?? await widget.repository.createGroup(groupName, entry.groupPinned);
          groupIdsByName[groupName] = groupId;
          await widget.repository.setSearchGroup(id, groupId);
        }
        existing.add(key); // catches duplicates within the same file too, not just against what was already saved
        imported++;
      }
      if (!mounted) {
        return;
      }
      setState(() => _importProgress = (imported + duplicates, parsed.entries.length));
    }
    if (!mounted) {
      return;
    }
    setState(() => _importProgress = null);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.settingsBackupImportSummary(imported, duplicates, parsed.invalidCount))));
  }

  Future<void> _switchConnectionMode() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => SetupScreen(settingsStore: widget.settingsStore, onConfigured: widget.onRepositoryConfigured, isReconfigure: true)),
    );
    // The reconfigure flow pops itself (and this screen, and everything
    // beneath it) back to the app's root once a new repository is ready --
    // see SetupScreen.isReconfigure. If the user backed out instead, nothing
    // changed and this screen is still showing, so re-load to reflect
    // whichever outcome actually happened.
    if (mounted) {
      _load();
    }
  }

  /// Jumps straight to a post by its external (site-native) id -- a
  /// debugging aid (M76) for reproducing a specific post's issue without
  /// hunting for it through search, same underlying lookup as a parent/
  /// child/pool cross-reference chip ([openExternalPost]). Validation is
  /// inline in the dialog itself (an invalid/empty id just disables "Open")
  /// rather than a separate error state, since there's nothing to show
  /// until a well-formed id is actually submitted.
  Future<void> _openPostById(AppLocalizations l10n) async {
    final idController = TextEditingController();
    var site = BunnySite.e621;
    final result = await showDialog<(BunnySite, int)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final parsedId = int.tryParse(idController.text.trim());
          return AlertDialog(
            title: Text(l10n.settingsOpenPostByIdDialogTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<BunnySite>(
                  segments: const [ButtonSegment(value: BunnySite.e621, label: Text('e621')), ButtonSegment(value: BunnySite.inkbunny, label: Text('Inkbunny'))],
                  selected: {site},
                  onSelectionChanged: (selection) => setDialogState(() => site = selection.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('settingsOpenPostByIdField'),
                  controller: idController,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: l10n.settingsOpenPostByIdFieldLabel),
                  onChanged: (_) => setDialogState(() {}),
                  onSubmitted: (_) => parsedId == null ? null : Navigator.pop(context, (site, parsedId)),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonCancel)),
              TextButton(onPressed: parsedId == null ? null : () => Navigator.pop(context, (site, parsedId)), child: Text(l10n.settingsOpenPostByIdOpenButton)),
            ],
          );
        },
      ),
    );
    // Not disposed here, deliberately -- same as SlideshowEditScreen's
    // own dialog-local controllers (_editOverrideCount, for one): the
    // dialog's exit transition keeps rebuilding this TextField for a few
    // more frames after showDialog's future completes, so disposing it
    // immediately throws "used after being disposed" mid-animation.
    if (result == null || !mounted) {
      return;
    }
    final (selectedSite, postId) = result;
    await openExternalPost(
      context: context,
      l10n: l10n,
      repository: widget.repository,
      site: selectedSite,
      externalId: postId,
      displaySettingsStore: widget.displaySettingsStore,
      downloadSettingsStore: widget.downloadSettingsStore,
      downloadQueueService: widget.downloadQueueService,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final themeMode = _themeMode;
    final themeColor = _themeColor;
    final previewQuality = _previewQuality;
    final repositoryConfig = _repositoryConfig;
    final httpRepository = widget.repository;
    final showServerOnlyEntries = repositoryConfig is NetworkedConfig && httpRepository is HttpBunnyRepository;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsScreenTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.settingsConnectionSection, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.settingsConnectionEntry),
            subtitle: Text(switch (repositoryConfig) {
              StandaloneConfig() => l10n.settingsConnectionStandalone,
              NetworkedConfig(:final serverBaseUrl) => l10n.settingsConnectionNetworked(serverBaseUrl.toString()),
              null => '',
            }),
            trailing: const Icon(Icons.chevron_right),
            onTap: _switchConnectionMode,
          ),
          if (showServerOnlyEntries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.settingsServerLogsEntry),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ServerLogsScreen(repository: httpRepository))),
            ),
          if (showServerOnlyEntries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.settingsTaskQueueEntry),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => TaskQueueScreen(repository: httpRepository))),
            ),
          if (showServerOnlyEntries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.settingsShareConnectionQr),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ConnectionQrScreen(
                    repository: httpRepository,
                    serverUrl: repositoryConfig.serverBaseUrl,
                    bearerToken: repositoryConfig.bearerToken,
                    certSha256: repositoryConfig.certificateSha256Fingerprint,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 24),
          Text(l10n.settingsAppearanceSection, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (themeMode != null)
            SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(value: ThemeMode.light, label: Text(l10n.settingsThemeLight)),
                ButtonSegment(value: ThemeMode.dark, label: Text(l10n.settingsThemeDark)),
                ButtonSegment(value: ThemeMode.system, label: Text(l10n.settingsThemeSystem)),
              ],
              selected: {themeMode},
              onSelectionChanged: (selection) => _setThemeMode(selection.first),
            ),
          const SizedBox(height: 8),
          if (themeColor != null)
            Wrap(
              spacing: 8,
              children: ThemeColorOption.values
                  .map(
                    (color) => Tooltip(
                      message: _themeColorLabel(l10n, color),
                      child: InkWell(
                        onTap: () => _setThemeColor(color),
                        customBorder: const CircleBorder(),
                        child: CircleAvatar(
                          backgroundColor: color.seedColor,
                          child: color == themeColor ? const Icon(Icons.check, color: Colors.white) : null,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.settingsAmoledLabel),
            value: _amoled,
            onChanged: _setAmoled,
          ),
          const SizedBox(height: 24),
          Text(l10n.settingsLanguageSection, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          // Only English ships today, but the resolution order (manual
          // setting here > device language > English) is already real --
          // "System default" leaves MaterialApp's own `locale` unset, which
          // is exactly how the latter two tiers already work with zero
          // extra code (M30). Adding a language later is just one more
          // entry in AppLocalizations.supportedLocales plus a label here.
          DropdownButtonFormField<String?>(
            initialValue: _languageCode,
            decoration: InputDecoration(labelText: l10n.settingsLanguageLabel),
            items: [
              DropdownMenuItem(value: null, child: Text(l10n.settingsLanguageSystemDefault)),
              ...AppLocalizations.supportedLocales.map(
                (locale) => DropdownMenuItem(value: locale.languageCode, child: Text(_languageLabelWithCompleteness(locale))),
              ),
            ],
            onChanged: (value) => _setLanguageCode(value),
          ),
          const SizedBox(height: 24),
          Text(l10n.settingsSyncSection, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _intervalController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l10n.settingsDefaultIntervalLabel),
            onChanged: _setDefaultIntervalHours,
          ),
          const SizedBox(height: 24),
          Text(l10n.settingsDisplaySection, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (previewQuality != null)
            SegmentedButton<PreviewQuality>(
              segments: [
                ButtonSegment(value: PreviewQuality.thumbnail, label: Text(l10n.settingsPreviewQualityThumbnail)),
                ButtonSegment(value: PreviewQuality.medium, label: Text(l10n.settingsPreviewQualityMedium)),
              ],
              selected: {previewQuality},
              onSelectionChanged: (selection) => _setPreviewQuality(selection.first),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _gridColumnsController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l10n.settingsGridColumnsLabel),
            onChanged: _setGridColumns,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _preloadCountController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l10n.settingsImagePreloadCountLabel),
            onChanged: _setImagePreloadCount,
          ),
          const SizedBox(height: 24),
          Text(l10n.settingsDownloadsSection, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.settingsDownloadsFolderLabel),
            subtitle: Text(_downloadFolder ?? l10n.settingsDownloadsFolderUnset),
            trailing: TextButton(onPressed: _chooseDownloadFolder, child: Text(l10n.settingsDownloadsChooseFolderButton)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.settingsAutoFavoriteOnDownloadLabel),
            value: _autoFavoriteOnDownload,
            onChanged: _setAutoFavoriteOnDownload,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.settingsAutoUpvoteOnDownloadLabel),
            value: _autoUpvoteOnDownload,
            onChanged: _setAutoUpvoteOnDownload,
          ),
          const SizedBox(height: 24),
          Text(l10n.settingsBackupSection, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.settingsBackupExportLabel),
            trailing: TextButton(onPressed: () => _exportSearches(l10n), child: Text(l10n.settingsBackupExportButton)),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(switch (_importProgress) { (final done, final total) => l10n.settingsBackupImportProgress(done, total), null => l10n.settingsBackupImportLabel }),
            trailing: TextButton(onPressed: _importProgress == null ? () => _importSearches(l10n) : null, child: Text(l10n.settingsBackupImportButton)),
          ),
          const SizedBox(height: 24),
          Text(l10n.settingsBlacklistSection, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<BunnySite>(
            segments: const [ButtonSegment(value: BunnySite.e621, label: Text('e621')), ButtonSegment(value: BunnySite.inkbunny, label: Text('Inkbunny'))],
            selected: {_blacklistSite},
            onSelectionChanged: (selection) => _setBlacklistSite(selection.first),
          ),
          if (_blacklistSite == BunnySite.e621) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _syncingE621Blacklist ? null : () => _syncE621Blacklist(l10n),
                icon: _syncingE621Blacklist ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync),
                label: Text(l10n.settingsBlacklistSyncE621Button),
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (_blacklistTags.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(l10n.settingsBlacklistEmpty))
          else
            Wrap(spacing: 8, runSpacing: 4, children: _blacklistTags.map((tag) => Chip(label: Text(tag), onDeleted: () => _removeBlacklistTag(tag))).toList()),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  key: const Key('settingsBlacklistAddField'),
                  controller: _blacklistTagController,
                  decoration: InputDecoration(labelText: l10n.settingsBlacklistAddLabel, errorText: _blacklistQueryError != null ? l10n.tagQueryInvalidSyntax : null),
                  onSubmitted: (_) => _addBlacklistTag(),
                ),
              ),
              IconButton(icon: const Icon(Icons.add), onPressed: _blacklistQueryError != null ? null : _addBlacklistTag),
            ],
          ),
          if (_blacklistSuggestions.isNotEmpty)
            Wrap(
              spacing: 8,
              children: _blacklistSuggestions.map((stat) => ActionChip(label: Text('${stat.name} (${stat.count})'), onPressed: () => _applyBlacklistSuggestion(stat.name))).toList(),
            ),
          const SizedBox(height: 24),
          Text(l10n.settingsUpdatesSection, style: Theme.of(context).textTheme.titleMedium),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.settingsAutoCheckForUpdatesLabel),
            value: _autoCheckForUpdates,
            onChanged: _setAutoCheckForUpdates,
          ),
          const SizedBox(height: 24),
          Text(l10n.settingsAppLockSection, style: Theme.of(context).textTheme.titleMedium),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.settingsAppLockEntry),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => LockSetupScreen(lockService: widget.lockService))),
          ),
          const SizedBox(height: 24),
          Text(l10n.settingsDebugSection, style: Theme.of(context).textTheme.titleMedium),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.settingsOpenPostByIdEntry),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openPostById(l10n),
          ),
          const SizedBox(height: 24),
          Text(l10n.settingsAboutSection, style: Theme.of(context).textTheme.titleMedium),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.settingsAboutEntry),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AboutScreen())),
          ),
        ],
      ),
    );
  }
}
