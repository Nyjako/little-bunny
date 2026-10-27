import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../settings/download_settings_store.dart';
import '../util/app_wakelock.dart';
import 'download_manager.dart';
import 'download_queue_notifier.dart';

/// Lets the user tap download (single or mass, M43) and immediately
/// navigate away -- the actual fetch+write+checksum (via [DownloadManager],
/// unchanged) runs in the background, reported through [DownloadQueueNotifier]
/// rather than blocking any screen. A [ChangeNotifier] rather than this
/// codebase's usual plain `setState`: unlike every other piece of
/// screen-owned state in this app, this service's lifetime isn't tied to
/// any single [State] object -- it's constructed once in `main()` and
/// threaded down like every other long-lived store (`downloadSettingsStore`
/// etc.), so screens that want to react to it (if any ever do) need a
/// listener, not just a field.
///
/// This pass only downloads while the app process is actually running -- no
/// attempt to keep a download going through a locked screen being
/// suspended/killed by the OS (that needs a real Android foreground service,
/// a separate, bigger follow-up -- see docs/ROADMAP.md). What this *does*
/// handle is the process being killed and relaunched for any reason: pending
/// items are persisted to a small JSON file and picked back up via
/// [restore] on the next launch, re-attempting the whole post from scratch
/// (not a byte-level resume -- the HTTP fetch itself was already a single
/// in-memory read with no partial-write risk to begin with).
class DownloadQueueService extends ChangeNotifier {
  final DownloadManager downloadManager;
  final DownloadSettingsStore downloadSettingsStore;
  final DownloadQueueNotifier notifier;

  DownloadQueueService({required this.downloadManager, required this.downloadSettingsStore, this.notifier = const NoopDownloadQueueNotifier()});

  final List<({BunnyPost post, BunnyRepository repository})> _pending = [];
  BunnyPost? _current;
  bool _processing = false;

  /// Reset to 0 once the queue fully drains, so a later, unrelated download
  /// starts its own fresh count instead of continuing some stale total.
  int _sessionDone = 0;
  int _sessionTotal = 0;
  int _succeeded = 0;
  int _mismatched = 0;
  int _failed = 0;

  int get pendingCount => _pending.length;
  int get completedCount => _sessionDone;
  int get totalCount => _sessionTotal;
  bool get isActive => _sessionTotal > 0;
  BunnyPost? get currentlyDownloading => _current;

  /// Enqueues [post] and returns immediately -- the actual download runs on
  /// its own, never awaited by the caller.
  void enqueue(BunnyPost post, BunnyRepository repository) => enqueueAll([post], repository);

  /// Same as [enqueue], for a whole mass-download selection at once.
  /// Strictly sequential processing underneath (never parallel), matching
  /// this app's existing mass-action convention.
  void enqueueAll(List<BunnyPost> posts, BunnyRepository repository) {
    if (posts.isEmpty) {
      return;
    }
    _pending.addAll(posts.map((post) => (post: post, repository: repository)));
    _sessionTotal += posts.length;
    unawaited(_persist());
    notifyListeners();
    if (!_processing) {
      unawaited(_processQueue());
    }
  }

  Future<void> _processQueue() async {
    _processing = true;
    // Both best-effort, same reasoning as every other notifier/wakelock call
    // in this method -- but called *before* the loop below, not just after
    // each item, so the Android foreground service (M57) gets a chance to
    // call startForeground() before the first HTTP fetch starts, not after
    // it finishes. Without this ordering, locking the screen right after
    // enqueueing could let Android kill the process before anything ever
    // told the service to start. (A much smaller residual race -- the gap
    // between enqueueAll() returning to its caller and this method's first
    // await actually running -- is a single event-loop tick and not worth
    // chasing further.) AppWakelock is reference-counted (see its own doc
    // comment) so this can't turn off a wakelock PostDetailScreen (M47) is
    // still holding for an unrelated reason.
    await AppWakelock.acquire();
    try {
      await notifier.showStarting(total: _sessionTotal);
    } catch (_) {
      // Best-effort.
    }
    try {
      while (_pending.isNotEmpty) {
        final item = _pending.removeAt(0);
        _current = item.post;
        notifyListeners();
        try {
          await _processItem(item.post, item.repository);
        } catch (_) {
          // One item throwing (e.g. a settings read failing) must not stop
          // every subsequent queued item from being attempted.
          _failed++;
        }
        _current = null;
        _sessionDone++;
        await _persist();
        // A broken notifier (any implementation, not just the real one, which
        // already swallows its own exceptions -- this is the queue's own
        // backstop) must never stop subsequent items from being processed.
        try {
          await notifier.showProgress(done: _sessionDone, total: _sessionTotal);
        } catch (_) {
          // Best-effort.
        }
        notifyListeners();
      }
      try {
        await notifier.showSummary(succeeded: _succeeded, mismatched: _mismatched, failed: _failed);
      } catch (_) {
        // Best-effort.
      }
    } finally {
      await AppWakelock.release();
    }
    _sessionDone = 0;
    _sessionTotal = 0;
    _succeeded = 0;
    _mismatched = 0;
    _failed = 0;
    _processing = false;
    notifyListeners();
  }

  Future<void> _processItem(BunnyPost post, BunnyRepository repository) async {
    final folder = await downloadSettingsStore.loadDestinationFolder();
    if (folder == null) {
      _failed++;
      return;
    }
    final autoFavorite = await downloadSettingsStore.loadAutoFavoriteOnDownload();
    final autoUpvote = await downloadSettingsStore.loadAutoUpvoteOnDownload();
    final result = await downloadManager.downloadPost(post, repository, folder, autoFavorite: autoFavorite, autoUpvote: autoUpvote);
    switch (result.outcome) {
      case DownloadOutcome.verified:
        _succeeded++;
      case DownloadOutcome.checksumMismatch:
        _mismatched++;
      case DownloadOutcome.noFileUrl || DownloadOutcome.failed:
        _failed++;
    }
    final downloaded = result.outcome == DownloadOutcome.verified || result.outcome == DownloadOutcome.checksumMismatch;
    // After every single item, not once per batch (M43) -- there's no
    // well-defined "last item in the batch" once the queue is open-ended
    // (enqueueAll can be called again mid-flight), so per-item draining is
    // the only option that doesn't need artificial batch-boundary tracking.
    if ((autoFavorite || autoUpvote) && downloaded) {
      await repository.processQueue();
    }
  }

  Future<File> _persistenceFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/pending_downloads.json');
  }

  /// Rewritten on every change to the set of posts still owed a download
  /// (enqueued or mid-flight) -- always the whole list, never appended to,
  /// since it's always tiny. Best-effort: a write failure here doesn't stop
  /// the queue itself from processing, it just means a crash right after
  /// would lose the resume information for whatever changed since the last
  /// successful write.
  Future<void> _persist() async {
    try {
      final file = await _persistenceFile();
      final ids = [..._pending.map((item) => item.post.id), if (_current != null) _current!.id];
      await file.writeAsString(jsonEncode(ids));
    } catch (_) {
      // Best-effort.
    }
  }

  /// Re-enqueues whatever was still pending from a previous run (M43) --
  /// call once from `main()`, after [repository] is available. Doesn't
  /// resume a partial download, just re-attempts each post from scratch;
  /// a post that's no longer resolvable (e.g. somehow uncached) is skipped
  /// rather than failing the whole restore.
  Future<void> restore(BunnyRepository repository) async {
    try {
      final file = await _persistenceFile();
      if (!await file.exists()) {
        return;
      }
      final ids = (jsonDecode(await file.readAsString()) as List).cast<int>();
      final posts = <BunnyPost>[];
      for (final id in ids) {
        try {
          posts.add(await repository.getPost(id));
        } catch (_) {
          // No longer resolvable -- skip it.
        }
      }
      if (posts.isNotEmpty) {
        enqueueAll(posts, repository);
      }
    } catch (_) {
      // Best-effort.
    }
  }
}
