import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../services/download_manager.dart';
import '../services/download_queue_service.dart';
import '../settings/download_settings_store.dart';
import 'slideshow_edit_screen.dart';

/// The Slideshows tab's own body (M51 v2) -- a plain list of persisted
/// [BunnySlideshow]s, embedded directly as one of [SearchesScreen]'s
/// `TabBarView` pages rather than pushed via `Navigator`, so it can own its
/// own [Scaffold]/[FloatingActionButton] independently of the Searches/
/// Pools tabs' FAB (which creates a search/pool, not a slideshow).
class SlideshowsScreen extends StatefulWidget {
  final BunnyRepository repository;
  final DownloadManager downloadManager;
  final DownloadSettingsStore downloadSettingsStore;
  final DownloadQueueService downloadQueueService;

  const SlideshowsScreen({super.key, required this.repository, required this.downloadManager, required this.downloadSettingsStore, required this.downloadQueueService});

  @override
  State<SlideshowsScreen> createState() => _SlideshowsScreenState();
}

class _SlideshowsScreenState extends State<SlideshowsScreen> {
  Future<List<BunnySlideshow>>? _future;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _future = widget.repository.slideshowList();
    });
  }

  /// Always refreshes on return, regardless of what (if anything) the edit
  /// screen changed -- same reasoning `SearchesScreen._openSettings` already
  /// gives for its own unconditional refresh: there's no "nothing changed"
  /// case worth threading a pop result through for.
  Future<void> _create() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SlideshowEditScreen(repository: widget.repository, downloadManager: widget.downloadManager, downloadSettingsStore: widget.downloadSettingsStore, downloadQueueService: widget.downloadQueueService),
      ),
    );
    _refresh();
  }

  Future<void> _open(BunnySlideshow slideshow) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SlideshowEditScreen(
          repository: widget.repository,
          downloadManager: widget.downloadManager,
          downloadSettingsStore: widget.downloadSettingsStore,
          downloadQueueService: widget.downloadQueueService,
          slideshow: slideshow,
        ),
      ),
    );
    _refresh();
  }

  /// Best-effort (same tolerance as every other local-filesystem cleanup in
  /// this app) -- a file that fails to delete (e.g. a `content://` SAF uri,
  /// which [File] can't touch at all, or one already gone) is simply left
  /// alone rather than blocking the slideshow's own removal below.
  Future<void> _deleteLocalFiles(int slideshowId) async {
    try {
      final folder = await widget.downloadSettingsStore.loadDestinationFolder();
      if (folder == null) {
        return;
      }
      final posts = await widget.repository.slideshowPostsList(slideshowId);
      for (final entry in posts) {
        final path = await widget.downloadManager.localFilePathFor(entry.post, folder);
        if (path == null || path.startsWith('content://')) {
          continue;
        }
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (_) {
      // Best-effort.
    }
  }

  Future<void> _delete(BunnySlideshow slideshow) async {
    final l10n = AppLocalizations.of(context)!;
    var deleteFiles = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(l10n.slideshowsDeleteDialogTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.slideshowsDeleteDialogContent(slideshow.label)),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: deleteFiles,
                onChanged: (value) => setDialogState(() => deleteFiles = value ?? false),
                title: Text(l10n.slideshowsDeleteAlsoFilesLabel),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.commonCancel)),
            TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.commonRemove)),
          ],
        ),
      ),
    );
    if (confirmed != true) {
      return;
    }
    if (deleteFiles) {
      await _deleteLocalFiles(slideshow.id);
    }
    await widget.repository.slideshowDelete(slideshow.id);
    _refresh();
  }

  String _subtitle(AppLocalizations l10n, BunnySlideshow slideshow) =>
      slideshow.maxTotalPosts == null ? l10n.slideshowsNoLimitSubtitle : l10n.slideshowsMaxPostsSubtitle(slideshow.maxTotalPosts!);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: FutureBuilder<List<BunnySlideshow>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final slideshows = snapshot.data!;
          if (slideshows.isEmpty) {
            return Center(child: Text(l10n.slideshowsScreenEmptyState));
          }
          return ListView(
            children: slideshows
                .map(
                  (slideshow) => ListTile(
                    title: Text(slideshow.label),
                    subtitle: Text(_subtitle(l10n, slideshow)),
                    onTap: () => _open(slideshow),
                    trailing: IconButton(icon: const Icon(Icons.delete_outline), tooltip: l10n.commonRemove, onPressed: () => _delete(slideshow)),
                  ),
                )
                .toList(),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(onPressed: _create, tooltip: l10n.slideshowsNewTooltip, child: const Icon(Icons.add)),
    );
  }
}
