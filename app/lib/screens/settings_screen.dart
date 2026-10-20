import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../repository/bunny_repository_factory.dart';
import '../repository/http_bunny_repository.dart';
import '../services/search_backup_service.dart';
import '../settings/app_lock_service.dart';
import '../settings/display_settings_store.dart';
import '../settings/download_settings_store.dart';
import '../settings/repository_settings_store.dart';
import '../settings/theme_settings_store.dart';
import 'about_screen.dart';
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
  final RepositorySettingsStore settingsStore;
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
    required this.settingsStore,
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
  PreviewQuality? _previewQuality;
  String? _downloadFolder;
  bool _autoFavoriteOnDownload = false;
  bool _autoUpvoteOnDownload = false;
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

  @override
  void initState() {
    super.initState();
    _load();
    _loadBlacklist();
  }

  @override
  void dispose() {
    _intervalController.dispose();
    _gridColumnsController.dispose();
    _preloadCountController.dispose();
    _blacklistTagController.dispose();
    super.dispose();
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
    });
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
    _ => locale.languageCode,
  };

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

  Future<void> _chooseDownloadFolder() async {
    final chosen = await FilePicker.getDirectoryPath();
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

  Future<void> _loadBlacklist() async {
    final tags = await widget.repository.getBlacklist(_blacklistSite);
    if (mounted) {
      setState(() => _blacklistTags = tags);
    }
  }

  Future<void> _setBlacklistSite(BunnySite site) async {
    setState(() => _blacklistSite = site);
    await _loadBlacklist();
  }

  Future<void> _addBlacklistTag() async {
    final tag = _blacklistTagController.text.trim();
    if (tag.isEmpty) {
      return;
    }
    await widget.repository.addBlacklistTag(_blacklistSite, tag);
    _blacklistTagController.clear();
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
      ).showSnackBar(SnackBar(content: Text(l10n.settingsBlacklistSyncE621Result(stats.added, stats.alreadyPresent, stats.skippedMultiTag))));
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
                (locale) => DropdownMenuItem(value: locale.languageCode, child: Text(_languageLabel(locale))),
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
            children: [
              Expanded(child: TextField(controller: _blacklistTagController, decoration: InputDecoration(labelText: l10n.settingsBlacklistAddLabel), onSubmitted: (_) => _addBlacklistTag())),
              IconButton(icon: const Icon(Icons.add), onPressed: _addBlacklistTag),
            ],
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
