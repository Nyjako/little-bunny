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

/// Where a single [DownloadQueueItem] currently sits. Terminal states
/// ([succeeded]/[checksumMismatch]/[failed]) persist in [DownloadQueueService]'s
/// own list until [DownloadQueueService.clearFinished] is called -- this is
/// what makes the queue a real, viewable history instead of an ephemeral
/// progress counter (M43 follow-up).
enum DownloadQueueItemStatus { queued, downloading, succeeded, checksumMismatch, failed }

/// One post's trip through the queue. [repository] is kept in-memory only
/// (never persisted -- it isn't JSON-serializable, and is re-resolved via
/// `repository.getPost(id)` on [DownloadQueueService.restore], same as
/// before this class existed) -- there's exactly one live [BunnyRepository]
/// instance app-wide at any moment, confirmed via every
/// enqueue/enqueueAll/restore call site. [status]/[failureReason] are
/// mutated in place as the item moves through the queue rather than this
/// object being replaced, so a `ListenableBuilder` watching
/// [DownloadQueueService] can just re-read the same item references.
class DownloadQueueItem {
  final BunnyPost post;
  final BunnyRepository repository;
  DownloadQueueItemStatus status;
  String? failureReason;

  DownloadQueueItem({required this.post, required this.repository, required this.status, this.failureReason});
}

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
/// A locked Android screen no longer kills a download mid-flight (M57 +
/// its own follow-up fix) -- what this class *also* handles is the process
/// being killed and relaunched for any other reason: every item (not just
/// still-pending ones) is persisted to a small JSON file and picked back up
/// via [restore] on the next launch. A still-queued/downloading item is
/// re-attempted from scratch (not a byte-level resume -- the HTTP fetch
/// itself was already a single in-memory read with no partial-write risk to
/// begin with); a previously-failed item is restored into view but *not*
/// auto-retried -- [retryFailed]/[retryAllFailed] are explicit, manual
/// actions, matching "restart failed downloads" rather than silently
/// hammering a site that just 403'd.
class DownloadQueueService extends ChangeNotifier {
  final DownloadManager downloadManager;
  final DownloadSettingsStore downloadSettingsStore;
  final DownloadQueueNotifier notifier;

  DownloadQueueService({required this.downloadManager, required this.downloadSettingsStore, this.notifier = const NoopDownloadQueueNotifier()});

  /// Every item the queue currently knows about, regardless of status --
  /// only [clearFinished] ever removes one. Use [queuedItems]/[currentItem]/
  /// [failedItems] below for the views a UI actually wants; this is exposed
  /// read-only mainly so [clearFinished]'s own "is there anything to clear"
  /// check and tests can inspect the full picture.
  List<DownloadQueueItem> get items => List.unmodifiable(_items);
  final List<DownloadQueueItem> _items = [];
  bool _processing = false;

  /// This run's progress, fed to [notifier] -- deliberately *not* derived
  /// from [_items] (which persists indefinitely until [clearFinished]):
  /// the notification should say "3 of 5" for the batch actually in
  /// flight right now, not a lifetime count inflated by old history still
  /// sitting in [_items]. Reset to 0 once the queue fully drains, so a
  /// later, unrelated download starts its own fresh count.
  int _sessionDone = 0;
  int _sessionTotal = 0;
  int _succeeded = 0;
  int _mismatched = 0;
  int _failed = 0;

  int get pendingCount => queuedItems.length;
  int get completedCount => _sessionDone;
  int get totalCount => _sessionTotal;
  bool get isActive => _sessionTotal > 0;
  BunnyPost? get currentlyDownloading => currentItem?.post;

  /// Items still waiting to be picked up.
  List<DownloadQueueItem> get queuedItems => _items.where((item) => item.status == DownloadQueueItemStatus.queued).toList(growable: false);

  /// The single item actively downloading right now, if any -- processing
  /// is strictly sequential, so there's never more than one.
  DownloadQueueItem? get currentItem => _items.where((item) => item.status == DownloadQueueItemStatus.downloading).firstOrNull;

  /// Items needing attention -- both an outright failure and a checksum
  /// mismatch (the file *was* written, just didn't match the published
  /// hash) surface here as one "needs a look" bucket, though each item's
  /// own [DownloadQueueItem.status] still distinguishes which.
  List<DownloadQueueItem> get failedItems =>
      _items.where((item) => item.status == DownloadQueueItemStatus.failed || item.status == DownloadQueueItemStatus.checksumMismatch).toList(growable: false);

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
    _items.addAll(posts.map((post) => DownloadQueueItem(post: post, repository: repository, status: DownloadQueueItemStatus.queued)));
    _sessionTotal += posts.length;
    unawaited(_persist());
    notifyListeners();
    if (!_processing) {
      unawaited(_processQueue());
    }
  }

  /// Moves [item] back to [DownloadQueueItemStatus.queued] and kicks off
  /// processing if the queue is currently idle -- a no-op for anything not
  /// currently in a failed/mismatched state (e.g. double-tapping a retry
  /// button before the first tap's rebuild lands).
  void retryFailed(DownloadQueueItem item) {
    if (item.status != DownloadQueueItemStatus.failed && item.status != DownloadQueueItemStatus.checksumMismatch) {
      return;
    }
    item.status = DownloadQueueItemStatus.queued;
    item.failureReason = null;
    _sessionTotal += 1;
    unawaited(_persist());
    notifyListeners();
    if (!_processing) {
      unawaited(_processQueue());
    }
  }

  /// Same as [retryFailed], batched over every currently-failed/mismatched
  /// item in one go.
  void retryAllFailed() {
    final toRetry = failedItems;
    if (toRetry.isEmpty) {
      return;
    }
    for (final item in toRetry) {
      item.status = DownloadQueueItemStatus.queued;
      item.failureReason = null;
    }
    _sessionTotal += toRetry.length;
    unawaited(_persist());
    notifyListeners();
    if (!_processing) {
      unawaited(_processQueue());
    }
  }

  /// Drops every item in a terminal state (succeeded/mismatched/failed),
  /// leaving queued/downloading ones untouched -- the "persist until
  /// cleared" half of the queue being a real, viewable history rather than
  /// an auto-resetting counter.
  void clearFinished() {
    final before = _items.length;
    _items.removeWhere(
      (item) => item.status == DownloadQueueItemStatus.succeeded || item.status == DownloadQueueItemStatus.checksumMismatch || item.status == DownloadQueueItemStatus.failed,
    );
    if (_items.length == before) {
      return;
    }
    unawaited(_persist());
    notifyListeners();
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
      while (true) {
        final item = queuedItems.firstOrNull;
        if (item == null) {
          break;
        }
        item.status = DownloadQueueItemStatus.downloading;
        notifyListeners();
        try {
          await _processItem(item);
        } catch (_) {
          // One item throwing (e.g. a settings read failing) must not stop
          // every subsequent queued item from being attempted.
          item.status = DownloadQueueItemStatus.failed;
          item.failureReason ??= 'Unexpected error';
          _failed++;
        }
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

  Future<void> _processItem(DownloadQueueItem item) async {
    final folder = await downloadSettingsStore.loadDestinationFolder();
    if (folder == null) {
      _failed++;
      item.status = DownloadQueueItemStatus.failed;
      item.failureReason = 'No download folder configured';
      return;
    }
    final autoFavorite = await downloadSettingsStore.loadAutoFavoriteOnDownload();
    final autoUpvote = await downloadSettingsStore.loadAutoUpvoteOnDownload();
    final result = await downloadManager.downloadPost(item.post, item.repository, folder, autoFavorite: autoFavorite, autoUpvote: autoUpvote);
    switch (result.outcome) {
      case DownloadOutcome.verified:
        _succeeded++;
        item.status = DownloadQueueItemStatus.succeeded;
      case DownloadOutcome.checksumMismatch:
        _mismatched++;
        item.status = DownloadQueueItemStatus.checksumMismatch;
      case DownloadOutcome.noFileUrl:
        _failed++;
        item.status = DownloadQueueItemStatus.failed;
        item.failureReason = 'This post has no file to download';
      case DownloadOutcome.failed:
        _failed++;
        item.status = DownloadQueueItemStatus.failed;
        item.failureReason = result.errorMessage;
    }
    final downloaded = result.outcome == DownloadOutcome.verified || result.outcome == DownloadOutcome.checksumMismatch;
    // After every single item, not once per batch (M43) -- there's no
    // well-defined "last item in the batch" once the queue is open-ended
    // (enqueueAll can be called again mid-flight), so per-item draining is
    // the only option that doesn't need artificial batch-boundary tracking.
    if ((autoFavorite || autoUpvote) && downloaded) {
      await item.repository.processQueue();
    }
  }

  Future<File> _persistenceFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/pending_downloads.json');
  }

  /// Rewritten on every change to [_items] -- always the whole list, never
  /// appended to, since it's always small. Best-effort: a write failure
  /// here doesn't stop the queue itself from processing, it just means a
  /// crash right after would lose the resume/history information for
  /// whatever changed since the last successful write.
  Future<void> _persist() async {
    try {
      final file = await _persistenceFile();
      final json = _items
          .map(
            (item) => {'id': item.post.id, 'status': item.status.name, if (item.failureReason != null) 'failureReason': item.failureReason},
          )
          .toList();
      await file.writeAsString(jsonEncode(json));
    } catch (_) {
      // Best-effort.
    }
  }

  /// Re-populates the queue from a previous run (M43, extended to cover
  /// every status, not just pending, as part of the queue-visibility
  /// follow-up) -- call once from `main()`, after [repository] is available.
  /// A `queued`/`downloading` entry re-enqueues from scratch (nothing is
  /// actually still in flight after a process restart); a `failed`/
  /// `checksumMismatch` entry is restored into view with its reason intact
  /// but is *not* auto-retried. A post that's no longer resolvable (e.g.
  /// somehow uncached) is skipped rather than failing the whole restore.
  Future<void> restore(BunnyRepository repository) async {
    try {
      final file = await _persistenceFile();
      if (!await file.exists()) {
        return;
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) {
        return;
      }
      final toEnqueue = <BunnyPost>[];
      final restoredTerminal = <DownloadQueueItem>[];
      if (decoded.isNotEmpty && decoded.first is Map) {
        for (final raw in decoded) {
          final entry = raw as Map<String, dynamic>;
          try {
            final post = await repository.getPost(entry['id'] as int);
            final statusName = entry['status'] as String?;
            if (statusName == DownloadQueueItemStatus.failed.name || statusName == DownloadQueueItemStatus.checksumMismatch.name) {
              restoredTerminal.add(
                DownloadQueueItem(
                  post: post,
                  repository: repository,
                  status: statusName == DownloadQueueItemStatus.failed.name ? DownloadQueueItemStatus.failed : DownloadQueueItemStatus.checksumMismatch,
                  failureReason: entry['failureReason'] as String?,
                ),
              );
            } else {
              toEnqueue.add(post);
            }
          } catch (_) {
            // No longer resolvable -- skip it.
          }
        }
      } else {
        // Backward-compat with the pre-queue-visibility format (a flat
        // array of bare post ids, all implicitly "pending") -- temporary
        // migration support, safe to remove once no realistic install base
        // predates this richer format.
        for (final id in decoded) {
          try {
            toEnqueue.add(await repository.getPost(id as int));
          } catch (_) {
            // No longer resolvable -- skip it.
          }
        }
      }
      if (restoredTerminal.isNotEmpty) {
        _items.addAll(restoredTerminal);
        notifyListeners();
      }
      if (toEnqueue.isNotEmpty) {
        enqueueAll(toEnqueue, repository);
      }
    } catch (_) {
      // Best-effort.
    }
  }
}
