import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../settings/app_lock_service.dart';
import '../settings/display_settings_store.dart';
import '../settings/download_settings_store.dart';
import '../settings/sync_settings_store.dart';
import '../settings/theme_settings_store.dart';
import 'lock_setup_screen.dart';

/// One place for cross-cutting app preferences -- reachable from
/// [AccountsScreen]'s app bar. Structured so adding more appearance options
/// later (or more sections entirely) doesn't need a redesign: each concern
/// (theme, app lock, sync, display, downloads) is its own section backed by
/// its own settings store.
class SettingsScreen extends StatefulWidget {
  final ThemeSettingsStore themeSettingsStore;
  final AppLockService lockService;
  final SyncSettingsStore syncSettingsStore;
  final DisplaySettingsStore displaySettingsStore;
  final DownloadSettingsStore downloadSettingsStore;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  const SettingsScreen({
    super.key,
    required this.themeSettingsStore,
    required this.lockService,
    required this.syncSettingsStore,
    required this.displaySettingsStore,
    required this.downloadSettingsStore,
    required this.onThemeModeChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  ThemeMode? _themeMode;
  PreviewQuality? _previewQuality;
  String? _downloadFolder;
  final _intervalController = TextEditingController();
  final _gridColumnsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _intervalController.dispose();
    _gridColumnsController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final mode = await widget.themeSettingsStore.load();
    final intervalHours = await widget.syncSettingsStore.loadDefaultIntervalHours();
    final previewQuality = await widget.displaySettingsStore.loadPreviewQuality();
    final gridColumns = await widget.displaySettingsStore.loadGridColumns();
    final downloadFolder = await widget.downloadSettingsStore.loadDestinationFolder();
    if (!mounted) {
      return;
    }
    setState(() {
      _themeMode = mode;
      _intervalController.text = '$intervalHours';
      _previewQuality = previewQuality;
      _gridColumnsController.text = '$gridColumns';
      _downloadFolder = downloadFolder;
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final themeMode = _themeMode;
    final previewQuality = _previewQuality;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsScreenTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
