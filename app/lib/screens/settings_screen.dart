import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../repository/bunny_repository_factory.dart';
import '../services/search_backup_service.dart';
import '../settings/app_lock_service.dart';
import '../settings/display_settings_store.dart';
import '../settings/download_settings_store.dart';
import '../settings/repository_settings_store.dart';
import '../settings/sync_settings_store.dart';
import '../settings/theme_settings_store.dart';
import 'lock_setup_screen.dart';
import 'setup_screen.dart';

/// One place for cross-cutting app preferences -- reachable from
/// [AccountsScreen]'s app bar. Structured so adding more appearance options
/// later (or more sections entirely) doesn't need a redesign: each concern
/// (theme, app lock, sync, display, downloads, backup) is its own section
/// backed by its own settings store.
class SettingsScreen extends StatefulWidget {
  final BunnyRepository repository;
  final ThemeSettingsStore themeSettingsStore;
  final AppLockService lockService;
  final SyncSettingsStore syncSettingsStore;
  final DisplaySettingsStore displaySettingsStore;
  final DownloadSettingsStore downloadSettingsStore;
  final RepositorySettingsStore settingsStore;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<BunnyRepository> onRepositoryConfigured;

  const SettingsScreen({
    super.key,
    required this.repository,
    required this.themeSettingsStore,
    required this.lockService,
    required this.syncSettingsStore,
    required this.displaySettingsStore,
    required this.downloadSettingsStore,
    required this.settingsStore,
    required this.onThemeModeChanged,
    required this.onRepositoryConfigured,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  BunnyRepositoryConfig? _repositoryConfig;
  ThemeMode? _themeMode;
  PreviewQuality? _previewQuality;
  String? _downloadFolder;
  bool _autoFavoriteOnDownload = false;
  bool _autoUpvoteOnDownload = false;
  final _intervalController = TextEditingController();
  final _gridColumnsController = TextEditingController();

  static const _backupService = SearchBackupService();

  /// Non-null only while [_importSearches]'s create loop is running --
  /// mirrors `PostGridScreen._massDownloadProgress`'s "replace the action's
  /// own label with a running count, re-enable on completion" shape (M9.5).
  (int, int)? _importProgress;

  BunnySite _blacklistSite = BunnySite.e621;
  List<String> _blacklistTags = [];
  final _blacklistTagController = TextEditingController();

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
    _blacklistTagController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repositoryConfig = await widget.settingsStore.load();
    final mode = await widget.themeSettingsStore.load();
    final intervalHours = await widget.syncSettingsStore.loadDefaultIntervalHours();
    final previewQuality = await widget.displaySettingsStore.loadPreviewQuality();
    final gridColumns = await widget.displaySettingsStore.loadGridColumns();
    final downloadFolder = await widget.downloadSettingsStore.loadDestinationFolder();
    final autoFavoriteOnDownload = await widget.downloadSettingsStore.loadAutoFavoriteOnDownload();
    final autoUpvoteOnDownload = await widget.downloadSettingsStore.loadAutoUpvoteOnDownload();
    if (!mounted) {
      return;
    }
    setState(() {
      _repositoryConfig = repositoryConfig;
      _themeMode = mode;
      _intervalController.text = '$intervalHours';
      _previewQuality = previewQuality;
      _gridColumnsController.text = '$gridColumns';
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

  Future<void> _setDefaultIntervalHours(String value) async {
    final hours = int.tryParse(value);
    if (hours == null || hours <= 0) {
      return;
    }
    await widget.syncSettingsStore.saveDefaultIntervalHours(hours);
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

  Future<void> _exportSearches(AppLocalizations l10n) async {
    final searches = await widget.repository.listSearches();
    final json = jsonEncode(_backupService.exportSearches(searches));
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
    final defaultIntervalHours = await widget.syncSettingsStore.loadDefaultIntervalHours();
    final parsed = _backupService.parseImportFile(contents, defaultIntervalHours: defaultIntervalHours);
    if (!mounted) {
      return;
    }
    if (parsed.format == ImportFormat.unrecognized) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.settingsBackupImportUnrecognizedFormat)));
      return;
    }

    final existing = (await widget.repository.listSearches()).map((search) => (search.site, search.query)).toSet();
    var imported = 0;
    var duplicates = 0;
    setState(() => _importProgress = (0, parsed.entries.length));
    for (final entry in parsed.entries) {
      final key = (entry.site, entry.query);
      if (existing.contains(key)) {
        duplicates++;
      } else {
        await widget.repository.createSearch(entry.site, entry.label, entry.query, intervalHours: entry.intervalHours, autoFavorite: entry.autoFavorite, autoFavoriteStars: entry.autoFavoriteStars, autoUpvote: entry.autoUpvote);
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
    final previewQuality = _previewQuality;
    final repositoryConfig = _repositoryConfig;

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
        ],
      ),
    );
  }
}
