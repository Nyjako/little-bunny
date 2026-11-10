import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../settings/download_settings_store.dart';
import 'download_manager.dart';
import 'download_queue_service.dart';

/// Thrown by [SlideshowPrepareService.prepare] when there's no destination
/// folder configured yet -- same failure mode a regular per-item download
/// already reports (`'No download folder configured'`, see
/// [DownloadQueueService]'s own processing), just surfaced up front rather
/// than discovered one post at a time.
class SlideshowPrepareException implements Exception {
  final String message;

  const SlideshowPrepareException(this.message);

  @override
  String toString() => 'SlideshowPrepareException: $message';
}

/// Where a single committed post currently stands after a
/// [SlideshowPrepareService.prepare] pass.
enum SlideshowPostReadiness {
  /// Already verified on disk -- part of the "ready to watch now" subset.
  ready,

  /// Queued/downloading right now -- either freshly enqueued by this pass
  /// (no prior attempt, or a stale one this session never picked back up),
  /// or already in flight from an earlier one.
  inProgress,

  /// Was stuck (a persistently failed/checksum-mismatched download --
  /// usually meaning the post was deleted or became unavailable at the
  /// site) -- healed by picking a fresh post from the same search and
  /// enqueuing it. [SlideshowPostStatus.post] is the *new* post here, not
  /// the dead one that triggered the swap.
  replaced,

  /// Was stuck, but its search had no other post left to pick as a
  /// replacement. The dead post stays committed (never silently dropped)
  /// -- a later [SlideshowPrepareService.prepare] call tries again.
  unreplaceable,
}

/// One committed post's outcome from a single [SlideshowPrepareService.prepare]
/// call.
class SlideshowPostStatus {
  final int searchId;
  final BunnyPost post;
  final SlideshowPostReadiness readiness;

  /// The dead download's own failure reason -- only set for
  /// [SlideshowPostReadiness.unreplaceable], so the caller can show *why*
  /// a post couldn't be replaced, not just that it couldn't.
  final String? reason;

  const SlideshowPostStatus({required this.searchId, required this.post, required this.readiness, this.reason});
}

/// The result of one [SlideshowPrepareService.prepare] call -- every post
/// currently committed to the slideshow, classified. A snapshot, not a
/// live view -- call [SlideshowPrepareService.prepare] again (e.g. once
/// downloads progress further) for an updated one.
class SlideshowPrepareReport {
  final List<SlideshowPostStatus> posts;

  const SlideshowPrepareReport(this.posts);

  int get readyCount => posts.where((p) => p.readiness == SlideshowPostReadiness.ready).length;
  int get inProgressCount => posts.where((p) => p.readiness == SlideshowPostReadiness.inProgress).length;
  int get replacedCount => posts.where((p) => p.readiness == SlideshowPostReadiness.replaced).length;
  int get unreplaceableCount => posts.where((p) => p.readiness == SlideshowPostReadiness.unreplaceable).length;

  /// Posts that can actually be watched right now (M51 v2 -- watching
  /// never waits for every post to be ready; it just skips whatever isn't
  /// yet, using whatever this already lists).
  List<BunnyPost> get readyPosts => posts.where((p) => p.readiness == SlideshowPostReadiness.ready).map((p) => p.post).toList(growable: false);
}

/// Resolves a persisted slideshow's committed posts down to "what can
/// actually be watched right now," and self-heals the rest (M51 v2): a
/// post with no live download attempt gets (re-)enqueued through the exact
/// same [DownloadQueueService] path every other download already uses; a
/// post whose download has persistently failed gets swapped for a fresh
/// pick from the same search via [BunnyRepository.slideshowReplacePost],
/// with the replacement enqueued too; a post whose search has nothing left
/// to replace it with is reported as [SlideshowPostReadiness.unreplaceable],
/// not silently dropped, so a review screen (PR4) can show it and let the
/// user retry later.
///
/// [prepare] can be called repeatedly (e.g. after the queue finishes a
/// batch, or on a periodic timer while a review screen is open) -- it
/// always re-derives its report from scratch rather than tracking state of
/// its own between calls.
class SlideshowPrepareService {
  final BunnyRepository repository;
  final DownloadQueueService downloadQueueService;
  final DownloadManager downloadManager;
  final DownloadSettingsStore downloadSettingsStore;

  SlideshowPrepareService({required this.repository, required this.downloadQueueService, required this.downloadManager, required this.downloadSettingsStore});

  Future<SlideshowPrepareReport> prepare(int slideshowId) async {
    final folder = await downloadSettingsStore.loadDestinationFolder();
    if (folder == null) {
      throw const SlideshowPrepareException('No download folder configured');
    }

    final committed = await repository.slideshowPostsList(slideshowId);
    final latestRowByPostId = <int, DownloadQueueRecord>{};
    for (final row in await repository.downloadQueueList()) {
      latestRowByPostId[row.postId] = row;
    }
    final activePostIds = downloadQueueService.items
        .where((item) => item.status == DownloadQueueItemStatus.queued || item.status == DownloadQueueItemStatus.downloading)
        .map((item) => item.post.id)
        .toSet();

    final results = <SlideshowPostStatus>[];
    final toEnqueue = <BunnyPost>[];
    // Snapshotted before any replacement happens below -- lets the
    // post-replacement pass (further down) tell a search's fresh pick
    // apart from a post that was already committed to it.
    final originalIdsBySearch = <int, Set<int>>{};
    final searchesToRefetch = <int>{};

    for (final entry in committed) {
      originalIdsBySearch.putIfAbsent(entry.searchId, () => {}).add(entry.post.id);

      if (await downloadManager.isDownloaded(entry.post, folder)) {
        results.add(SlideshowPostStatus(searchId: entry.searchId, post: entry.post, readiness: SlideshowPostReadiness.ready));
        continue;
      }
      if (activePostIds.contains(entry.post.id)) {
        results.add(SlideshowPostStatus(searchId: entry.searchId, post: entry.post, readiness: SlideshowPostReadiness.inProgress));
        continue;
      }

      final row = latestRowByPostId[entry.post.id];
      final isStuck = row != null && (row.status == 'failed' || row.status == 'checksum_mismatch');
      if (!isStuck) {
        toEnqueue.add(entry.post);
        results.add(SlideshowPostStatus(searchId: entry.searchId, post: entry.post, readiness: SlideshowPostReadiness.inProgress));
        continue;
      }

      try {
        await repository.slideshowReplacePost(slideshowId, entry.searchId, entry.post.id);
        searchesToRefetch.add(entry.searchId);
      } catch (_) {
        results.add(SlideshowPostStatus(searchId: entry.searchId, post: entry.post, readiness: SlideshowPostReadiness.unreplaceable, reason: row.failureReason));
      }
    }

    for (final searchId in searchesToRefetch) {
      final originalIds = originalIdsBySearch[searchId] ?? const <int>{};
      final current = await repository.slideshowPostsList(slideshowId, searchId: searchId);
      for (final entry in current) {
        if (!originalIds.contains(entry.post.id)) {
          results.add(SlideshowPostStatus(searchId: searchId, post: entry.post, readiness: SlideshowPostReadiness.replaced));
          toEnqueue.add(entry.post);
        }
      }
    }

    if (toEnqueue.isNotEmpty) {
      await downloadQueueService.enqueueAll(toEnqueue, repository);
    }

    return SlideshowPrepareReport(results);
  }
}
