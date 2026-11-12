import 'dart:async';

import 'package:flutter/foundation.dart';

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

/// The same wire strings `download_queue.status`'s CHECK constraint uses
/// (see `libs/db/src/schema.h`) -- kept here rather than on the enum itself
/// so this persistence detail doesn't leak into every other place the enum
/// is already used for UI/business logic.
String _statusWire(DownloadQueueItemStatus status) => switch (status) {
  DownloadQueueItemStatus.queued => 'queued',
  DownloadQueueItemStatus.downloading => 'downloading',
  DownloadQueueItemStatus.succeeded => 'succeeded',
  DownloadQueueItemStatus.checksumMismatch => 'checksum_mismatch',
  DownloadQueueItemStatus.failed => 'failed',
};

/// One post's trip through the queue. [repository] is kept in-memory only
/// -- there's exactly one live [BunnyRepository] instance app-wide at any
/// moment, confirmed via every enqueue/enqueueAll/restore call site.
/// [status]/[failureReason] are mutated in place as the item moves through
/// the queue rather than this object being replaced, so a `ListenableBuilder`
/// watching [DownloadQueueService] can just re-read the same item references.
///
/// [queueRowIdFuture] is the id of this item's own persisted row (M62
/// follow-up) -- a live [BunnyRepository.downloadQueueAdd] call for a
/// freshly enqueued item, or an already-resolved [Future.value] wrapping an
/// existing row's id when reconstructed by [DownloadQueueService.restore].
/// Every status-persisting call awaits this *first*, rather than assuming
/// the insert has already landed by the time it's needed -- correctness
/// here can't depend on how quickly that Future happens to resolve.
class DownloadQueueItem {
  final BunnyPost post;
  final BunnyRepository repository;
  DownloadQueueItemStatus status;
  String? failureReason;
  final Future<int> queueRowIdFuture;

  /// This item's own byte progress (M62) -- unlike [DownloadQueueService]'s
  /// whole-batch item counts, these live on the item itself (not a single
  /// shared pair on the service) since up to [DownloadQueueService.
  /// _maxConcurrentDownloads] items can be [DownloadQueueItemStatus.downloading]
  /// at once. Reset to null the instant this item starts downloading;
  /// [bytesTotal] stays null if the response had no `Content-Length` to
  /// report one. Never persisted -- only status/failureReason survive a
  /// restart.
  int? bytesReceived;
  int? bytesTotal;

  /// M65 -- 0/null means this isn't a pool download. See
  /// [DownloadManager.downloadPost]'s own doc comment for what these drive.
  final int poolId;
  final String? poolName;
  final int poolPage;

  DownloadQueueItem({
    required this.post,
    required this.repository,
    required this.status,
    this.failureReason,
    required this.queueRowIdFuture,
    this.poolId = 0,
    this.poolName,
    this.poolPage = 0,
  });
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
/// being killed and relaunched for any other reason: every item's status is
/// persisted through [BunnyRepository]'s `downloadQueue*` methods (a real
/// SQLite table, M62 follow-up -- previously a Dart-owned JSON file, which
/// wasn't surviving a restart reliably since its writes were batched and
/// fire-and-forget) and picked back up via [restore] on the next launch. A
/// still-queued/downloading item is re-attempted from scratch (not a
/// byte-level resume -- the HTTP fetch itself was already a single
/// in-memory read with no partial-write risk to begin with); a
/// previously-failed item is restored into view but *not* auto-retried --
/// [retryFailed]/[retryAllFailed] are explicit, manual actions, matching
/// "restart failed downloads" rather than silently hammering a site that
/// just 403'd.
///
/// Up to [_maxConcurrentDownloads] items download in parallel (M62 --
/// previously strictly one at a time) via a self-topping-up worker pool:
/// [_ensureWorkersRunning] spawns [_runWorkerSlot] instances up to that
/// cap, and is called again by every site that adds new work, so a slot
/// that found nothing to claim earlier gets replaced rather than the pool
/// only ever shrinking (M62 follow-up -- see [_ensureWorkersRunning]'s own
/// doc comment for the startup race this fixes). Each slot repeatedly
/// claims the next still-queued item and runs it through [_processItem]
/// until none are left. Claiming an item (reading [queuedItems] and
/// flipping its status to [DownloadQueueItemStatus.downloading]) never has
/// an `await` between those two steps, so two slots can never claim the
/// same item -- Dart's single-threaded, cooperative scheduling means that
/// synchronous pair always runs as one atomic step relative to every other
/// slot.
class DownloadQueueService extends ChangeNotifier {
  final DownloadManager downloadManager;
  final DownloadSettingsStore downloadSettingsStore;
  final DownloadQueueNotifier notifier;

  DownloadQueueService({required this.downloadManager, required this.downloadSettingsStore, this.notifier = const NoopDownloadQueueNotifier()});

  /// A modest cap (M62) -- meaningfully faster than one-at-a-time for a
  /// large batch without opening an unbounded number of simultaneous
  /// connections to a site's CDN.
  static const _maxConcurrentDownloads = 3;

  /// Draining the favorite/upvote action queue (a blocking network/FFI
  /// round trip) used to happen after *every single item* -- fine for a
  /// handful of items, but for a multi-thousand-item batch that's a full
  /// network round trip on the critical path of every single download.
  /// Throttling to once every N items divides the total cost by a constant
  /// factor (it doesn't change the shape -- pair with occasional
  /// [clearFinished] if multi-thousand-item batches become routine), and
  /// gets the drain off the per-item path entirely except for this periodic
  /// catch-up plus the unconditional final flush below. Shared across every
  /// concurrent worker (M62) -- the increment-then-maybe-reset below never
  /// has an `await` in between, so this stays race-free the same way
  /// claiming an item does.
  static const _syncEveryNItems = 10;

  /// Every item the queue currently knows about, regardless of status --
  /// only [clearFinished] ever removes one. Use [queuedItems]/[currentItem]/
  /// [failedItems] below for the views a UI actually wants; this is exposed
  /// read-only mainly so [clearFinished]'s own "is there anything to clear"
  /// check and tests can inspect the full picture.
  List<DownloadQueueItem> get items => List.unmodifiable(_items);
  final List<DownloadQueueItem> _items = [];

  /// How many worker slots are currently live, 0..[_maxConcurrentDownloads]
  /// -- NOT the same as "a batch is in progress" (the single `bool
  /// _processing` this replaced): [restore] adds its thousands of rows into
  /// [_items] one at a time, asynchronously, as each row's post metadata
  /// resolves -- the very first row to land could trigger topping workers
  /// up while only that one item is visible, so spawning a fixed batch of
  /// [_maxConcurrentDownloads] right then would hand 1-2 of them an empty
  /// [queuedItems] and lose them for the rest of the session (a `bool`
  /// has no way to tell "0 running, top up" apart from "1 or 2 running,
  /// already topped up as far as it'll ever go"). [_ensureWorkersRunning]
  /// is the only place this grows, spawning exactly as many workers as
  /// [queuedItems] can currently feed, up to the cap -- called again by
  /// every site that adds new work, so a worker that found nothing earlier
  /// gets replaced the moment there's something for it again, rather than
  /// the pool only ever shrinking.
  int _activeWorkers = 0;

  /// The current session's "acquire the wake lock, tell the notifier a
  /// batch is starting" setup -- created once, by whichever worker slot
  /// takes [_activeWorkers] from 0 to 1, and awaited by *every* slot
  /// (including that first one) before it claims its own first item, not
  /// just the one that happened to create it. Without that, a second/third
  /// slot spawned in the same [_ensureWorkersRunning] burst would start
  /// fetching immediately while the first slot is still mid-setup -- the
  /// Android foreground service (M57) needs a chance to call
  /// startForeground() before *any* HTTP fetch starts, not just the first
  /// slot's. Reset to null once the session ends (`_activeWorkers` back to
  /// 0) so the next one creates its own fresh setup.
  Future<void>? _sessionStartFuture;
  Stopwatch? _sessionStopwatch;
  int _itemsSinceSync = 0;

  /// Set by [pause], cleared by [resume] -- lets the user hold off on new
  /// downloads starting (e.g. right before disconnecting from wifi, to
  /// avoid burning mobile data) without losing anything already queued.
  /// Only gates *claiming a new item*: a worker already mid-download when
  /// this flips keeps running that one fetch to completion rather than
  /// aborting it outright, since the native fetch layer has no cancellation
  /// hook to abort through, and letting one already-started file finish is
  /// a small, bounded cost compared to the plumbing a hard cancel would need.
  bool _paused = false;
  bool get isPaused => _paused;

  /// Persisted row ids already pulled into [_items] by [restore] -- lets
  /// [resume] call [restore] again safely (e.g. from a button or
  /// notification action) without re-adding the same row as a duplicate
  /// item. Never cleared -- a row that's since gone terminal or been
  /// cleared from [_items] has no reason to be considered for restoring
  /// again either.
  final Set<int> _restoredRowIds = {};

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
  /// favorite/upvote action -- lets [_runWorkerSlot] skip [_drainActionQueue]
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

  /// Fast, session-only progress signal for [postIds] against this queue's
  /// live [items] -- counts how many of them currently sit in a terminal
  /// state ([DownloadQueueItemStatus.succeeded]/[DownloadQueueItemStatus.
  /// checksumMismatch]/[DownloadQueueItemStatus.failed]) versus the total
  /// asked about. Meant for a cheap progress bar while a batch (e.g. a
  /// slideshow's prepare pass, M51 v2) is actively downloading -- *not* the
  /// authoritative "is this post ready" check, since a [DownloadQueueItemStatus
  /// .succeeded] item can later be dropped from [items] via [clearFinished]
  /// while the file it already wrote still correctly sits on disk; that
  /// check is always [DownloadManager.isDownloaded] instead. A [postIds]
  /// entry with no matching item at all (never enqueued this session) isn't
  /// counted as done.
  (int done, int total) progressFor(Set<int> postIds) {
    if (postIds.isEmpty) {
      return (0, 0);
    }
    final done = _items.where(
      (item) =>
          postIds.contains(item.post.id) &&
          (item.status == DownloadQueueItemStatus.succeeded || item.status == DownloadQueueItemStatus.checksumMismatch || item.status == DownloadQueueItemStatus.failed),
    ).length;
    return (done, postIds.length);
  }

  /// Enqueues [post] -- see [enqueueAll] for why the returned future matters.
  Future<void> enqueue(BunnyPost post, BunnyRepository repository) => enqueueAll([post], repository);

  /// Same as [enqueue], for a whole mass-download selection at once. Up to
  /// [_maxConcurrentDownloads] items download in parallel underneath (M62).
  ///
  /// Silently drops any post already [DownloadQueueItemStatus.queued] or
  /// [DownloadQueueItemStatus.downloading] -- a double-tap on a download
  /// button (or the same post appearing in two overlapping mass-download
  /// selections) must not queue it twice, which would otherwise race two
  /// workers against the identical destination file. A post that's already
  /// in a *terminal* state (succeeded/failed/checksumMismatch) is still
  /// re-queueable, same as [retryFailed] already allows -- this only guards
  /// against genuinely duplicating in-flight work, not against a
  /// deliberate re-download later.
  ///
  /// Returns once every new item's own `download_queue` row is durably
  /// persisted -- *not* once the downloads themselves finish (those keep
  /// running in the background regardless of whether the caller awaits
  /// this). This used to return immediately, before any of those inserts
  /// had actually landed, on the theory that [restore] would just pick
  /// everything back up on the next launch anyway. That reasoning missed
  /// the actual failure mode: a mass-download of ~100 posts followed by the
  /// user closing the app (or Android killing it) right after the "N queued"
  /// confirmation landed could outrun the inserts -- a row that was never
  /// written isn't something [restore] has anything to find on relaunch, so
  /// it isn't "still queued but forgotten," it's gone. Awaiting this before
  /// showing that confirmation (or before returning at all) closes that
  /// window; the dedup/persist logic below already runs synchronously up to
  /// that point, so this adds latency to the caller, not to when downloading
  /// actually starts.
  Future<void> enqueueAll(List<BunnyPost> posts, BunnyRepository repository) => _enqueueAll(posts, repository);

  /// Same as [enqueueAll], but every item is marked as part of pool
  /// [poolId]/[poolName] (M65). [pageByPostId] gives each post's *true*
  /// position in the pool (1-indexed) -- a caller that only selected some
  /// of a pool's posts (not every one currently loaded) must still pass
  /// each selected post's real page, not its position within just the
  /// selection, so this takes an explicit lookup rather than inferring page
  /// from [posts]'s own order. A post missing from [pageByPostId] falls
  /// back to page 0 (treated as "not a pool download" by [DownloadManager],
  /// same as omitting pool context entirely) rather than guessing.
  /// [DownloadManager.downloadPost] files each item under a pool-named
  /// folder with a page-numbered filename instead of the regular
  /// per-artist scheme.
  Future<void> enqueuePool(List<BunnyPost> posts, BunnyRepository repository, {required int poolId, required String poolName, required Map<int, int> pageByPostId}) =>
      _enqueueAll(posts, repository, poolId: poolId, poolName: poolName, pageByPostId: pageByPostId);

  Future<void> _enqueueAll(List<BunnyPost> posts, BunnyRepository repository, {int poolId = 0, String? poolName, Map<int, int> pageByPostId = const {}}) async {
    if (posts.isEmpty) {
      return;
    }
    final activeIds = _items.where((item) => item.status == DownloadQueueItemStatus.queued || item.status == DownloadQueueItemStatus.downloading).map((item) => item.post.id).toSet();
    // activeIds.add returns false for anything already present -- this
    // dedupes both against what's already active in the queue and against
    // [posts] repeating the same post more than once in this very call.
    final newPosts = posts.where((post) => activeIds.add(post.id)).toList(growable: false);
    if (newPosts.isEmpty) {
      return;
    }
    // A post genuinely already on disk (e.g. from a previous run, after
    // restore() hasn't reloaded a since-cleared succeeded row) still gets a
    // queue row/item here -- deliberately so, kept synchronous with no new
    // await before _sessionTotal/notifyListeners below (every caller of
    // enqueue/enqueueAll relies on this becoming "active" without an
    // intervening await). The existing skip-fetch fast path inside
    // DownloadManager.downloadPost (checks the file exists AND its checksum
    // still matches before ever touching the network) is what actually
    // avoids re-downloading it -- that already runs at execution time, so
    // there's no real work wasted, just a queue row that resolves to
    // "verified" almost instantly instead of a real fetch.
    final newItems = newPosts.map((post) {
      final page = poolId > 0 ? (pageByPostId[post.id] ?? 0) : 0;
      return DownloadQueueItem(
        post: post,
        repository: repository,
        status: DownloadQueueItemStatus.queued,
        queueRowIdFuture: repository.downloadQueueAdd(post.id, poolId: poolId, poolName: poolName, poolPage: page),
        poolId: poolId,
        poolName: poolName,
        poolPage: page,
      );
    }).toList(growable: false);
    _items.addAll(newItems);
    _sessionTotal += newPosts.length;
    notifyListeners();
    _ensureWorkersRunning();
    // See this method's own doc comment -- the actual durability guarantee.
    // Best-effort, same as every other persistence call in this class: a
    // single insert failing here doesn't invalidate the rest of the batch,
    // and whatever ends up unresolved is still visible in [_items]/the UI,
    // with every later persisting call against it (e.g. [_persistStatus])
    // already tolerating the same failure on its own.
    try {
      await Future.wait(newItems.map((item) => item.queueRowIdFuture));
    } catch (_) {
      // Ignored -- see above.
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
    unawaited(_persistStatus(item));
    notifyListeners();
    _ensureWorkersRunning();
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
      unawaited(_persistStatus(item));
    }
    _sessionTotal += toRetry.length;
    notifyListeners();
    _ensureWorkersRunning();
  }

  /// Drops every item in a terminal state (succeeded/mismatched/failed),
  /// leaving queued/downloading ones untouched -- the "persist until
  /// cleared" half of the queue being a real, viewable history rather than
  /// an auto-resetting counter.
  void clearFinished() {
    final before = _items.length;
    // Grabbed before removing anything -- any item's repository is equally
    // valid (there's exactly one live BunnyRepository instance app-wide at
    // any moment), and this needs one even when every single item here is
    // about to be removed.
    final repository = _items.isEmpty ? null : _items.first.repository;
    _items.removeWhere(
      (item) => item.status == DownloadQueueItemStatus.succeeded || item.status == DownloadQueueItemStatus.checksumMismatch || item.status == DownloadQueueItemStatus.failed,
    );
    if (_items.length == before) {
      return;
    }
    if (repository != null) {
      unawaited(repository.downloadQueueClearFinished());
    }
    notifyListeners();
  }

  /// Tops [_activeWorkers] up to [_maxConcurrentDownloads], spawning exactly
  /// as many new worker slots as [queuedItems] can feed right now -- never
  /// more than that, so a worker never starts just to immediately find
  /// nothing and exit (the original bug this replaced). Called by every
  /// site that adds new work ([_enqueueAll]/[retryFailed]/[retryAllFailed]/
  /// each row [restore] adds/[resume]), so a worker slot that exited
  /// earlier for lack of anything to claim gets replaced the moment there's
  /// something for it again, rather than the pool only ever shrinking.
  /// Incrementing [_activeWorkers] then calling [_runWorkerSlot] has no
  /// `await` in between (same race-free reasoning as claiming an item
  /// itself, see this class's own doc comment), so two calls to this
  /// method can never both decide there's room for the same slot.
  void _ensureWorkersRunning() {
    if (_paused) {
      return;
    }
    while (_activeWorkers < _maxConcurrentDownloads && queuedItems.isNotEmpty) {
      _activeWorkers++;
      if (_activeWorkers == 1) {
        _sessionStartFuture = _startSession();
      }
      unawaited(_runWorkerSlot());
    }
  }

  /// Runs once per session, started by whichever slot takes
  /// [_activeWorkers] from 0 to 1 -- see [_sessionStartFuture]'s own doc
  /// comment for why every slot (that one included) awaits this same
  /// Future rather than just the first slot doing it inline.
  Future<void> _startSession() async {
    // Both best-effort, same reasoning as every other notifier/wakelock
    // call in this method -- but run before any item below starts, not
    // just after each one, so the Android foreground service (M57) gets a
    // chance to call startForeground() before the first HTTP fetch starts,
    // not after it finishes. AppWakelock is reference-counted (see its own
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
    _sessionStopwatch = Stopwatch()..start();
  }

  /// One worker slot's lifetime: claims and runs items until there's
  /// nothing left for it (or it's paused), then exits -- [_ensureWorkersRunning]
  /// is what starts a replacement later, this never loops back on its own.
  /// Bookets the whole *session* (not just this one slot) in the two edge
  /// transitions: every slot awaits [_sessionStartFuture] before actually
  /// fetching its own first item; the slot that takes [_activeWorkers] back
  /// down to 0 runs the "the whole batch just finished" teardown after its
  /// own loop ends. That second check reads [_activeWorkers] right after it
  /// was changed with no `await` in between, so it's exactly as race-free
  /// as every other check in this class.
  Future<void> _runWorkerSlot() async {
    // Claiming (below) happens on *every* iteration before this slot's
    // first real `await`; [_sessionStartFuture] is only awaited once, right
    // after that first claim -- awaiting it *before* claiming would let
    // [_ensureWorkersRunning]'s spawn loop run ahead of this slot without
    // seeing [queuedItems] shrink yet, so it could spawn more slots than
    // there's actually work for (the same bug this class's doc comment
    // describes, just reintroduced one level up).
    var awaitedSessionStart = false;

    while (true) {
      // Checked before claiming, not instead of draining what's already in
      // flight -- pause() only stops *new* items from starting (see its
      // own doc comment); an item already past this check keeps running to
      // completion.
      if (_paused) {
        break;
      }
      final item = queuedItems.firstOrNull;
      if (item == null) {
        break;
      }
      item.status = DownloadQueueItemStatus.downloading;
      item.bytesReceived = null;
      item.bytesTotal = null;
      // Fire-and-forget -- restore() already resets a still-"downloading"
      // row back to "queued" unconditionally, so losing this specific
      // write to a kill lands exactly where restore() would've put it
      // anyway. Nothing here is worth blocking the actual fetch on.
      unawaited(_persistStatus(item));
      notifyListeners();
      if (!awaitedSessionStart) {
        awaitedSessionStart = true;
        await _sessionStartFuture;
      }
      try {
        await _processItem(item);
      } catch (_) {
        // One item throwing (e.g. a settings read failing) must not stop
        // every other item (this slot's next one, or another slot's
        // current one) from being attempted.
        item.status = DownloadQueueItemStatus.failed;
        item.failureReason ??= 'Unexpected error';
        _failed++;
        await _persistStatus(item);
      }
      _sessionDone++;
      _itemsSinceSync++;
      // The reset happens in the same synchronous step as the check
      // (nothing awaited in between), so two slots finishing an item
      // around the same time can never both see the threshold crossed and
      // both trigger a sync.
      final shouldSync = _itemsSinceSync >= _syncEveryNItems;
      if (shouldSync) {
        _itemsSinceSync = 0;
      }
      if (shouldSync && _actionsQueuedSinceSync) {
        await _drainActionQueue(item.repository);
        _actionsQueuedSinceSync = false;
      }
      // A broken notifier (any implementation, not just the real one, which
      // already swallows its own exceptions -- this is the queue's own
      // backstop) must never stop subsequent items from being processed.
      // This keeps firing every item -- it's neither an expensive disk
      // write nor a network round trip, so there's no reason to reduce how
      // often the UI/notification sees progress.
      // _sessionDone > 1 (not > 0): on the very first completed item
      // there's only one data point, not a rate yet -- eta stays null for
      // that call, non-null from the second call onward.
      Duration? eta;
      if (_sessionDone > 1) {
        final avgPerItem = _sessionStopwatch!.elapsed ~/ _sessionDone;
        eta = avgPerItem * (_sessionTotal - _sessionDone);
      }
      try {
        await notifier.showProgress(done: _sessionDone, total: _sessionTotal, failed: _failed, eta: eta);
      } catch (_) {
        // Best-effort.
      }
      notifyListeners();
    }

    _activeWorkers--;
    if (_activeWorkers == 0) {
      // Unconditional final drain -- covers both a batch smaller than the
      // threshold above (today's common case: a single download, or a
      // small mass-selection, which never reaches _syncEveryNItems) and the
      // tail of a large batch that didn't land exactly on a multiple of
      // it. Any item's own repository works here -- there's exactly one
      // live BunnyRepository instance app-wide at any moment (this class's
      // own doc comment), and _items is guaranteed non-empty here
      // (everything that was ever enqueued this run is still sitting in
      // it, just no longer queued/downloading).
      if (_sessionDone > 0 && _actionsQueuedSinceSync) {
        await _drainActionQueue(_items.first.repository);
        _actionsQueuedSinceSync = false;
      }
      try {
        await notifier.showSummary(succeeded: _succeeded, mismatched: _mismatched, failed: _failed);
      } catch (_) {
        // Best-effort.
      }
      await AppWakelock.release();
      _sessionDone = 0;
      _sessionTotal = 0;
      _succeeded = 0;
      _mismatched = 0;
      _failed = 0;
      _sessionStopwatch = null;
      _sessionStartFuture = null;
    }
    notifyListeners();
  }

  Future<void> _processItem(DownloadQueueItem item) async {
    final folder = await downloadSettingsStore.loadDestinationFolder();
    if (folder == null) {
      _failed++;
      item.status = DownloadQueueItemStatus.failed;
      item.failureReason = 'No download folder configured';
      await _persistStatus(item);
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
      poolId: item.poolId,
      poolName: item.poolName,
      poolPage: item.poolPage,
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
    // Awaited, unlike the "claimed -> downloading" transition above -- this
    // is the actual outcome, the one piece of information a restart must
    // not lose, so it's durable before this method (and the worker loop
    // awaiting it) moves on to the next item.
    await _persistStatus(item);
  }

  /// Persists [item]'s current [DownloadQueueItem.status]/
  /// [DownloadQueueItem.failureReason] -- awaits [DownloadQueueItem.
  /// queueRowIdFuture] first rather than assuming the row already exists,
  /// since [enqueueAll] fires that insert off without waiting for it either.
  Future<void> _persistStatus(DownloadQueueItem item) async {
    try {
      final id = await item.queueRowIdFuture;
      await item.repository.downloadQueueSetStatus(id, _statusWire(item.status), failureReason: item.failureReason);
    } catch (_) {
      // Best-effort, same as every other persistence call in this class --
      // a write failure here doesn't stop the queue itself from processing,
      // it just means a crash right after would show this one item's
      // previous status on the next launch instead of its latest.
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

  /// [repository.getPost] can be a real network call (networked mode --
  /// standalone's is a pure local SQLite lookup that essentially never
  /// fails transiently), so [restore] retrying it a few times here is what
  /// actually matters: a cold app launch racing the OS/network not being up
  /// yet is a completely ordinary thing to hit, and previously a single
  /// failure there meant that row was silently never shown again this
  /// session (M65 -- reported as "downloads got forgotten", not because
  /// anything was actually deleted, but because restore() gave up on the
  /// very first transient failure with no retry at all). 3 attempts, half a
  /// second apart, covers "network not up yet" without meaningfully
  /// delaying the common case where it just works the first time.
  static const _getPostRetries = 3;
  static const _getPostRetryDelay = Duration(milliseconds: 500);

  Future<BunnyPost> _getPostWithRetry(BunnyRepository repository, int postId) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await repository.getPost(postId);
      } catch (_) {
        if (attempt >= _getPostRetries) {
          rethrow;
        }
        await Future<void>.delayed(_getPostRetryDelay);
      }
    }
  }

  /// Rows are resolved this many at a time (M67) -- same bounded-worker-pool
  /// shape as [_runWorkerSlot]'s download workers, just for [_getPostWithRetry]
  /// calls instead of fetches. [restore] used to walk every row strictly
  /// one at a time and only touch [_items]/[notifyListeners] once the
  /// *entire* list had finished -- for a large backlog in networked mode,
  /// where each row costs a real HTTP round trip, that meant the download
  /// queue screen showed nothing at all for however long the whole backlog
  /// took to resolve (minutes, for a few hundred rows), which read as "my
  /// downloads are gone" even though every row was still sitting there,
  /// just not drawn yet (M67 -- the actual explanation for reports like
  /// that, once the separate durability race above was already fixed and
  /// the symptom persisted). Resolving several rows concurrently rather
  /// than strictly sequentially also just finishes the whole backlog
  /// faster.
  static const _restoreConcurrency = 5;

  /// Re-populates the queue from a previous run (M43, extended to cover
  /// every status, not just pending, as part of the queue-visibility
  /// follow-up; moved off a Dart-owned JSON file onto [BunnyRepository]'s
  /// `downloadQueue*` methods -- a real SQLite table -- as part of the M62
  /// follow-up, since the JSON file's batched, fire-and-forget writes
  /// weren't surviving a restart reliably) -- call once from `main()`,
  /// after [repository] is available (also callable again later via
  /// [resume], e.g. from a button or notification action, since a row
  /// already pulled into [_items] is tracked in [_restoredRowIds] and never
  /// added twice). A `queued`/`downloading` row re-enqueues from scratch
  /// (nothing is actually still in flight after a process restart); a
  /// `failed`/`checksum_mismatch`/`succeeded` row is restored into view
  /// as-is and is *not* auto-retried/re-enqueued -- `succeeded` used to
  /// re-enqueue too (on the assumption that re-running one is cheap, since
  /// [DownloadManager.downloadPost]'s own checksum-skip resolves it without
  /// a real fetch), but that assumption doesn't hold once there are
  /// thousands of already-finished rows (a large slideshow's worth, say):
  /// re-verifying every one's checksum on every single app restart is real,
  /// non-free I/O (under SAF, each check is also its own platform-channel
  /// round trip -- the same per-item cost [DownloadManager.
  /// batchIsDownloaded]'s own doc comment already describes), and the queue
  /// screen would briefly show the whole history flipping back to "queued"
  /// on every restart besides. A post that's no
  /// longer resolvable after [_getPostWithRetry]'s retries (e.g. somehow
  /// uncached, or a genuinely unreachable server) is skipped rather than
  /// failing the whole restore -- a later [resume] call gets another chance
  /// at it, since it's never added to [_restoredRowIds] unless it actually
  /// succeeds. Reuses each row's own existing id (never [enqueueAll], which
  /// would insert a *new* row) -- this is resuming the same persisted
  /// attempt, not starting a fresh one.
  ///
  /// Each row is added to [_items] (and [notifyListeners] called) the
  /// moment *that row's own* fetch resolves (see [_restoreConcurrency]'s
  /// own doc comment for why this matters) -- not batched up and applied
  /// once every row in this call has finished.
  Future<void> restore(BunnyRepository repository) async {
    try {
      final rows = await repository.downloadQueueList();
      final pending = rows.where((row) => !_restoredRowIds.contains(row.id)).toList(growable: false);
      if (pending.isEmpty) {
        return;
      }
      var nextIndex = 0;
      // Seeded from whatever's already in _items (an earlier restore()/
      // enqueue call this session) -- a DB row for a post_id already
      // represented in memory is a duplicate row, not a new item. row.postId
      // is known synchronously straight off the DB row, with no await
      // needed, so claiming it happens in the same race-free spot as
      // nextIndex++ below -- two DB rows for the same post_id can't both
      // slip past this on separate workers.
      final claimedPostIds = _items.map((item) => item.post.id).toSet();
      // Claiming the next row (reading nextIndex, then incrementing) never
      // has an await between those two steps, so this is race-free the
      // same way claiming a queued item in _runWorkerSlot's own workers is
      // (see that method's doc comment) -- two restore workers can never
      // claim the same row.
      Future<void> worker() async {
        while (true) {
          if (nextIndex >= pending.length) {
            return;
          }
          final row = pending[nextIndex++];
          if (!claimedPostIds.add(row.postId)) {
            // A duplicate row for a post_id already represented in _items --
            // mark it processed so a later resume() doesn't keep retrying
            // it forever, but don't create a second in-memory item for the
            // same post. The orphaned duplicate row itself is left in the
            // DB -- cleaning that up is a separate concern from "don't show
            // duplicates in memory."
            _restoredRowIds.add(row.id);
            continue;
          }
          try {
            final post = await _getPostWithRetry(repository, row.postId);
            _restoredRowIds.add(row.id);
            // 'succeeded' is a terminal state same as the other two here --
            // restored as-is, never requeued. Treating it like
            // 'downloading'/'queued' below (the only other branch) used to
            // force it back to 'queued' and re-download an already-finished
            // post on every app restart, since a succeeded row stays in the
            // table as history until clearFinished() is called (see this
            // class's own doc comment on DownloadQueueItemStatus) rather
            // than being deleted the moment the download completes.
            if (row.status == 'failed' || row.status == 'checksum_mismatch' || row.status == 'succeeded') {
              _items.add(
                DownloadQueueItem(
                  post: post,
                  repository: repository,
                  status: switch (row.status) {
                    'failed' => DownloadQueueItemStatus.failed,
                    'checksum_mismatch' => DownloadQueueItemStatus.checksumMismatch,
                    _ => DownloadQueueItemStatus.succeeded,
                  },
                  failureReason: row.failureReason,
                  queueRowIdFuture: Future.value(row.id),
                  poolId: row.poolId,
                  poolName: row.poolName,
                  poolPage: row.poolPage,
                ),
              );
              notifyListeners();
            } else {
              if (row.status != 'queued') {
                unawaited(repository.downloadQueueSetStatus(row.id, 'queued'));
              }
              _items.add(
                DownloadQueueItem(
                  post: post,
                  repository: repository,
                  status: DownloadQueueItemStatus.queued,
                  queueRowIdFuture: Future.value(row.id),
                  poolId: row.poolId,
                  poolName: row.poolName,
                  poolPage: row.poolPage,
                ),
              );
              _sessionTotal += 1;
              notifyListeners();
              _ensureWorkersRunning();
            }
          } catch (_) {
            // Still not resolvable after retrying -- leave it out of
            // _restoredRowIds so a later resume() call gets another chance.
          }
        }
      }

      await Future.wait(List.generate(_restoreConcurrency, (_) => worker()));
    } catch (e) {
      // Best-effort, but not silent -- a failure here means nothing resumes
      // on this launch at all, worth a trace during development.
      debugPrint('DownloadQueueService.restore failed: $e');
    }
  }

  /// Stops new items from being claimed (see [_paused]'s own doc comment)
  /// -- a no-op if already paused. The download queue screen's
  /// pause/resume button (replacing the old always-"check for pending
  /// downloads" button, M67) calls this, for e.g. pausing right before
  /// disconnecting from wifi to avoid burning mobile data on whatever's
  /// still queued.
  void pause() {
    if (_paused) {
      return;
    }
    _paused = true;
    notifyListeners();
  }

  /// Un-pauses (a no-op if not currently paused) and re-checks for pending
  /// downloads (M65) -- a button on the download queue screen and a
  /// notification action both call this, for whenever [restore]'s own
  /// automatic retries at launch still weren't enough (e.g. the network
  /// took longer than that to come up in networked mode), *and* for
  /// whenever [pause] left queued items sitting idle: [restore] alone
  /// wouldn't restart those (every row still persisted from this session is
  /// already in [_restoredRowIds], so [restore] finds nothing new to add),
  /// so this also tops workers back up directly whenever there's anything
  /// left in [queuedItems].
  Future<void> resume(BunnyRepository repository) async {
    _paused = false;
    await restore(repository);
    _ensureWorkersRunning();
    notifyListeners();
  }
}
