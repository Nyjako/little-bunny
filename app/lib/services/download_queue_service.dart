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

  /// This item's own byte progress (M62) -- unlike [DownloadQueueService]'s
  /// whole-batch item counts, these live on the item itself (not a single
  /// shared pair on the service) since up to [DownloadQueueService.
  /// _maxConcurrentDownloads] items can be [DownloadQueueItemStatus.downloading]
  /// at once. Reset to null the instant this item starts downloading;
  /// [bytesTotal] stays null if the response had no `Content-Length` to
  /// report one.
  int? bytesReceived;
  int? bytesTotal;

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
///
/// Up to [_maxConcurrentDownloads] items download in parallel (M62 --
/// previously strictly one at a time) via a small fixed-size worker pool:
/// [_processQueue] starts that many `worker()` loops, each repeatedly
/// claiming the next still-queued item and running it through
/// [_processItem] until none are left. Claiming an item (reading
/// [queuedItems] and flipping its status to [DownloadQueueItemStatus.downloading])
/// never has an `await` between those two steps, so two workers can never
/// claim the same item -- Dart's single-threaded, cooperative scheduling
/// means that synchronous pair always runs as one atomic step relative to
/// every other worker.
class DownloadQueueService extends ChangeNotifier {
  final DownloadManager downloadManager;
  final DownloadSettingsStore downloadSettingsStore;
  final DownloadQueueNotifier notifier;

  DownloadQueueService({required this.downloadManager, required this.downloadSettingsStore, this.notifier = const NoopDownloadQueueNotifier()});

  /// A modest cap (M62) -- meaningfully faster than one-at-a-time for a
  /// large batch without opening an unbounded number of simultaneous
  /// connections to a site's CDN.
  static const _maxConcurrentDownloads = 3;

  /// Persisting (re-serializes the whole [_items] list) and draining the
  /// favorite/upvote action queue (a blocking network/FFI round trip) both
  /// used to happen after *every single item* -- fine for a handful of
  /// items, but for a multi-thousand-item batch that's O(n) work repeated n
  /// times, and it put a full network round trip on the critical path of
  /// every single download. Throttling to once every N items divides the
  /// total cost by a constant factor (it doesn't change the shape -- pair
  /// with occasional [clearFinished] if multi-thousand-item batches become
  /// routine), and gets the favorite/upvote drain off the per-item path
  /// entirely except for this periodic catch-up plus the unconditional final
  /// flush below. Shared across every concurrent worker (M62) -- the
  /// increment-then-maybe-reset below never has an `await` in between, so
  /// this stays race-free the same way claiming an item does.
  static const _syncEveryNItems = 10;

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

  /// Set by [_processItem] whenever a download actually queues a
  /// favorite/upvote action -- lets [_processQueue] skip [_drainActionQueue]
  /// entirely (not just skip it cheaply) when auto-favorite/auto-upvote are
  /// both off, the common case, instead of firing an empty-queue network
  /// round trip every [_syncEveryNItems] items for nothing.
  bool _actionsQueuedSinceSync = false;

  int get pendingCount => queuedItems.length;

  /// Count of items that finished cleanly -- checksum-mismatch items are
  /// deliberately excluded (they stay in [failedItems], individually listed
  /// with a retry action, since the file didn't match what was published).
  int get succeededCount => _items.where((item) => item.status == DownloadQueueItemStatus.succeeded).length;
  int get completedCount => _sessionDone;
  int get totalCount => _sessionTotal;
  bool get isActive => _sessionTotal > 0;

  /// Items still waiting to be picked up.
  List<DownloadQueueItem> get queuedItems => _items.where((item) => item.status == DownloadQueueItemStatus.queued).toList(growable: false);

  /// Every item actively downloading right now (M62) -- up to
  /// [_maxConcurrentDownloads] of them, each with its own
  /// [DownloadQueueItem.bytesReceived]/[DownloadQueueItem.bytesTotal].
  List<DownloadQueueItem> get downloadingItems => _items.where((item) => item.status == DownloadQueueItemStatus.downloading).toList(growable: false);

  /// Items needing attention -- both an outright failure and a checksum
  /// mismatch (the file *was* written, just didn't match the published
  /// hash) surface here as one "needs a look" bucket, though each item's
  /// own [DownloadQueueItem.status] still distinguishes which.
  List<DownloadQueueItem> get failedItems =>
      _items.where((item) => item.status == DownloadQueueItemStatus.failed || item.status == DownloadQueueItemStatus.checksumMismatch).toList(growable: false);

  /// Enqueues [post] and returns immediately -- the actual download runs on
  /// its own, never awaited by the caller.
  void enqueue(BunnyPost post, BunnyRepository repository) => enqueueAll([post], repository);

  /// Same as [enqueue], for a whole mass-download selection at once. Up to
  /// [_maxConcurrentDownloads] items download in parallel underneath (M62).
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
    // in this method -- but called *before* the workers below start, not
    // just after each item, so the Android foreground service (M57) gets a
    // chance to call startForeground() before the first HTTP fetch starts,
    // not after it finishes. Without this ordering, locking the screen right
    // after enqueueing could let Android kill the process before anything
    // ever told the service to start. (A much smaller residual race -- the
    // gap between enqueueAll() returning to its caller and this method's
    // first await actually running -- is a single event-loop tick and not
    // worth chasing further.) AppWakelock is reference-counted (see its own
    // doc comment) so this can't turn off a wakelock PostDetailScreen (M47)
    // is still holding for an unrelated reason.
    await AppWakelock.acquire();
    try {
      await notifier.showStarting(total: _sessionTotal);
    } catch (_) {
      // Best-effort.
    }
    // Started after showStarting, not before -- an item-level average (the
    // per-item ETA below is intentionally batch-granularity, not derived
    // from any one item's own byte progress, since a single slow or
    // unusually large file shouldn't skew the whole batch's estimate), used
    // to estimate an ETA once at least one item has actually finished.
    // Shared across every worker (M62) -- same race-free reasoning as
    // _syncEveryNItems itself.
    final sessionStopwatch = Stopwatch()..start();
    var itemsSinceSync = 0;

    // One worker loop, up to _maxConcurrentDownloads of these run at once
    // (see this class's own doc comment for why claiming an item below is
    // race-free). Declared inside _processQueue (a closure, not a separate
    // method) so it can freely read/write sessionStopwatch/itemsSinceSync
    // without needing to thread them through as parameters.
    Future<void> worker() async {
      while (true) {
        final item = queuedItems.firstOrNull;
        if (item == null) {
          return;
        }
        item.status = DownloadQueueItemStatus.downloading;
        item.bytesReceived = null;
        item.bytesTotal = null;
        notifyListeners();
        try {
          await _processItem(item);
        } catch (_) {
          // One item throwing (e.g. a settings read failing) must not stop
          // every other item (this worker's next one, or another worker's
          // current one) from being attempted.
          item.status = DownloadQueueItemStatus.failed;
          item.failureReason ??= 'Unexpected error';
          _failed++;
        }
        _sessionDone++;
        itemsSinceSync++;
        // The reset happens in the same synchronous step as the check
        // (nothing awaited in between), so two workers finishing an item
        // around the same time can never both see the threshold crossed
        // and both trigger a sync.
        final shouldSync = itemsSinceSync >= _syncEveryNItems;
        if (shouldSync) {
          itemsSinceSync = 0;
        }
        if (shouldSync) {
          await _persist();
          if (_actionsQueuedSinceSync) {
            await _drainActionQueue(item.repository);
            _actionsQueuedSinceSync = false;
          }
        }
        // A broken notifier (any implementation, not just the real one, which
        // already swallows its own exceptions -- this is the queue's own
        // backstop) must never stop subsequent items from being processed.
        // Unlike persist/drain above, this keeps firing every item -- it's
        // neither an expensive disk write nor a network round trip, so there's
        // no reason to reduce how often the UI/notification sees progress.
        // _sessionDone > 1 (not > 0): on the very first completed item
        // there's only one data point, not a rate yet -- eta stays null for
        // that call, non-null from the second call onward.
        Duration? eta;
        if (_sessionDone > 1) {
          final avgPerItem = sessionStopwatch.elapsed ~/ _sessionDone;
          eta = avgPerItem * (_sessionTotal - _sessionDone);
        }
        try {
          await notifier.showProgress(done: _sessionDone, total: _sessionTotal, failed: _failed, eta: eta);
        } catch (_) {
          // Best-effort.
        }
        notifyListeners();
      }
    }

    try {
      await Future.wait(List.generate(_maxConcurrentDownloads, (_) => worker()));
      // Unconditional final flush -- covers both a batch smaller than the
      // threshold above (today's common case: a single download, or a small
      // mass-selection, which never reaches _syncEveryNItems) and the tail of
      // a large batch that didn't land exactly on a multiple of it. Any
      // item's own repository works here -- there's exactly one live
      // BunnyRepository instance app-wide at any moment (this class's own
      // doc comment), and _items is guaranteed non-empty here (everything
      // that was ever enqueued this run is still sitting in it, just no
      // longer queued/downloading).
      if (_sessionDone > 0) {
        await _persist();
        if (_actionsQueuedSinceSync) {
          await _drainActionQueue(_items.first.repository);
          _actionsQueuedSinceSync = false;
        }
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
    final result = await downloadManager.downloadPost(
      item.post,
      item.repository,
      folder,
      autoFavorite: autoFavorite,
      autoUpvote: autoUpvote,
      onProgress: (received, total) {
        item.bytesReceived = received;
        item.bytesTotal = total;
        notifyListeners();
      },
    );
    switch (result.outcome) {
      case DownloadOutcome.verified:
        _succeeded++;
        item.status = DownloadQueueItemStatus.succeeded;
        if (autoFavorite || autoUpvote) {
          _actionsQueuedSinceSync = true;
        }
      case DownloadOutcome.checksumMismatch:
        _mismatched++;
        item.status = DownloadQueueItemStatus.checksumMismatch;
        if (autoFavorite || autoUpvote) {
          _actionsQueuedSinceSync = true;
        }
      case DownloadOutcome.noFileUrl:
        _failed++;
        item.status = DownloadQueueItemStatus.failed;
        item.failureReason = 'This post has no file to download';
      case DownloadOutcome.failed:
        _failed++;
        item.status = DownloadQueueItemStatus.failed;
        item.failureReason = result.errorMessage;
    }
  }

  /// Best-effort drain of the action queue for whichever [BunnyRepository]
  /// is passed in -- called periodically from each worker (see
  /// [_syncEveryNItems]) and once more unconditionally after every worker
  /// finishes, never per-item: `processQueue()` is a blocking network/FFI
  /// round trip, and putting it on every single item's critical path (the
  /// old M43 behavior) made a whole batch's wall-clock time include one
  /// such round trip per item for no benefit -- [DownloadManager.
  /// downloadPost]'s own doc comment already says draining "is left to the
  /// caller," which decides its own batching needs. Takes a bare
  /// [BunnyRepository] rather than a [DownloadQueueItem] since any item's
  /// repository is equally valid (this class's own doc comment) and the
  /// unconditional final flush (M62) no longer has one single "last item"
  /// once several can finish at once.
  Future<void> _drainActionQueue(BunnyRepository repository) async {
    try {
      await repository.processQueue();
    } catch (_) {
      // Best-effort, same as every other notifier/drain call in this class.
    }
  }

  Future<File> _persistenceFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/pending_downloads.json');
  }

  /// Public, awaitable wrapper around [_persist] -- every other call site
  /// uses `unawaited(_persist())` since none of them have a reason to block
  /// on the write finishing, but `main.dart`'s desktop exit hook (M61) does:
  /// without an explicit flush awaited *before* the app is allowed to
  /// actually exit, a normal window close on Linux/Windows/macOS can tear
  /// the process down mid-write (or before the next periodic sync even
  /// fires), silently losing whatever changed since the last successful
  /// persist -- unlike a mobile "swipe to kill," which the OS doesn't ask
  /// this app's permission for at all.
  Future<void> flush() => _persist();

  /// Rewritten on every change to [_items] -- always the whole list, never
  /// appended to. Best-effort: a write failure here doesn't stop the queue
  /// itself from processing, it just means a crash right after would lose
  /// the resume/history information for whatever changed since the last
  /// successful write.
  ///
  /// Written to a temp file first, then renamed into place (same pattern as
  /// [DownloadManager.downloadPost]'s own atomic write) -- a kill mid-write
  /// must never leave `pending_downloads.json` truncated/corrupt, since
  /// [restore]'s `jsonDecode` would then silently fail and nothing would
  /// resume on next launch. The temp filename is unique per call (not a
  /// fixed name) because this method can be called from several places
  /// without any of them awaiting each other (`unawaited()` from
  /// `enqueueAll`/`retryFailed`/`retryAllFailed`/`clearFinished`, plus from
  /// inside `_processQueue`'s own loop) -- two calls' temp-file lifecycles
  /// can overlap, and a fixed name would let them race on the same path.
  Future<void> _persist() async {
    try {
      final file = await _persistenceFile();
      final json = _items
          .map(
            (item) => {'id': item.post.id, 'status': item.status.name, if (item.failureReason != null) 'failureReason': item.failureReason},
          )
          .toList();
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/pending_downloads_${DateTime.now().microsecondsSinceEpoch}.json.tmp');
      await tempFile.writeAsString(jsonEncode(json));
      try {
        await tempFile.rename(file.path);
      } catch (_) {
        await tempFile.copy(file.path);
        await tempFile.delete();
      }
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
    } catch (e) {
      // Best-effort, but not silent -- a parse failure here means nothing
      // resumes on this launch at all, worth a trace during development.
      debugPrint('DownloadQueueService.restore failed: $e');
    }
  }
}
