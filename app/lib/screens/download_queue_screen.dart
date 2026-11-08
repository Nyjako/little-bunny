import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../bunny_repository_scope.dart';
import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../services/download_queue_service.dart';
import '../util/byte_format.dart';
import '../util/image_headers.dart';

/// Shows the client-side download queue (M43) as a real, viewable list
/// rather than just a passing notification -- what's currently downloading,
/// what's still queued, what's done, and what failed (with a reason, and a
/// way to retry it). Listens directly to [DownloadQueueService] (already a
/// `ChangeNotifier`) rather than polling, unlike [TaskQueueScreen] (which
/// has to poll since its data lives server-side).
///
/// Queued/done are shown as a single count each, not a per-item list --
/// [DownloadQueueService.pendingCount]/[succeededCount] are already O(n)
/// counts, not lists, so this never has to materialize thousands of rows for
/// them. "Currently downloading" (up to [DownloadQueueService._maxConcurrentDownloads]
/// items at once, M62) and "failed" (usually a small, bounded set needing an
/// actual retry action) render real rows; failed rows go through a lazy
/// [SliverList] rather than a plain `ListView(children: ...)` so even a
/// pathological "everything failed" batch only builds what's actually
/// scrolled into view. Before this (M43-follow-up), the queued/failed
/// sections were built as eager `.map().toList()` lists fed straight into a
/// non-lazy `ListView`, which, combined with this screen rebuilding on every
/// single item's progress tick while a batch is active, made opening this
/// screen with a few thousand pending items effectively unusable.
class DownloadQueueScreen extends StatelessWidget {
  final DownloadQueueService downloadQueueService;

  const DownloadQueueScreen({super.key, required this.downloadQueueService});

  String _postLabel(BunnyPost post) {
    final title = post.title;
    return title != null && title.isNotEmpty ? title : '#${post.externalId}';
  }

  Widget _sectionHeader(BuildContext context, String title) =>
      Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text(title, style: Theme.of(context).textTheme.titleMedium));

  /// A handful of rows (at most [DownloadQueueService._maxConcurrentDownloads],
  /// M62), each with its own byte-progress bar -- unlike the single bar this
  /// used to be, up to that many files can be [DownloadQueueItemStatus.downloading]
  /// at once now, so there's no single "the current file" to show.
  Widget _downloadingSection(BuildContext context, AppLocalizations l10n, List<DownloadQueueItem> downloading) {
    final total = downloadQueueService.totalCount;
    final done = downloadQueueService.completedCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, l10n.downloadQueueDownloadingLabel),
        // Batch-level progress (done/total of the whole run) -- shown once
        // here, above the per-file rows below, since it covers the whole
        // batch rather than any one file.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: LinearProgressIndicator(key: const Key('downloadQueueBatchProgressBar'), value: total > 0 ? done / total : null),
        ),
        const SizedBox(height: 4),
        ...downloading.map((item) => _downloadingItemRow(context, item)),
      ],
    );
  }

  Widget _downloadingItemRow(BuildContext context, DownloadQueueItem item) {
    final bytesReceived = item.bytesReceived;
    final bytesTotal = item.bytesTotal;
    final previewUrl = item.post.previewUrl;
    return ListTile(
      leading: SizedBox(
        width: 40,
        height: 40,
        child: previewUrl != null
            ? ClipRRect(borderRadius: BorderRadius.circular(4), child: CachedNetworkImage(imageUrl: previewUrl, httpHeaders: imageHeadersFor(item.post.site), fit: BoxFit.cover))
            : const Icon(Icons.image_outlined),
      ),
      title: Text(_postLabel(item.post)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // This one file's own byte progress (M62) -- indeterminate until
          // the first chunk arrives, or whenever the response had no
          // Content-Length to compute a fraction from. Keyed per post (not
          // a single static key) since several of these can coexist now.
          LinearProgressIndicator(
            key: ValueKey('downloadQueueFileProgressBar_${item.post.id}'),
            value: (bytesReceived != null && bytesTotal != null && bytesTotal > 0) ? bytesReceived / bytesTotal : null,
          ),
          if (bytesReceived != null) ...[
            const SizedBox(height: 2),
            Text(
              bytesTotal != null ? '${formatBytesCompact(bytesReceived)} / ${formatBytesCompact(bytesTotal)}' : formatBytesCompact(bytesReceived),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _countRow(IconData icon, String text) => ListTile(leading: Icon(icon), title: Text(text));

  Widget _failedRow(BuildContext context, AppLocalizations l10n, DownloadQueueItem item) => ListTile(
    leading: Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
    title: Text(_postLabel(item.post)),
    subtitle: Text(item.status == DownloadQueueItemStatus.checksumMismatch ? l10n.downloadQueueChecksumMismatchReason : (item.failureReason ?? '')),
    trailing: IconButton(icon: const Icon(Icons.replay), tooltip: l10n.downloadQueueRetryTooltip, onPressed: () => downloadQueueService.retryFailed(item)),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.downloadQueueScreenTitle),
        actions: [
          // Always visible, not conditional on anything -- cheap to call
          // even when there's nothing to resume (M65). The main reason this
          // exists: restore()'s own automatic retries at launch are
          // best-effort, not a guarantee -- a networked-mode server/network
          // that's still not reachable after those few retries leaves rows
          // persisted but unresolved, with nothing else that would ever
          // retry them again without the user asking.
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: l10n.downloadQueueResumeTooltip,
            onPressed: () => downloadQueueService.resume(BunnyRepositoryScope.of(context)),
          ),
          AnimatedBuilder(
            animation: downloadQueueService,
            builder: (context, child) => downloadQueueService.failedItems.isEmpty
                ? const SizedBox.shrink()
                : IconButton(icon: const Icon(Icons.replay), tooltip: l10n.downloadQueueRetryAllTooltip, onPressed: downloadQueueService.retryAllFailed),
          ),
          AnimatedBuilder(
            animation: downloadQueueService,
            builder: (context, child) => downloadQueueService.items.every((item) => item.status == DownloadQueueItemStatus.queued || item.status == DownloadQueueItemStatus.downloading)
                ? const SizedBox.shrink()
                : IconButton(icon: const Icon(Icons.clear_all), tooltip: l10n.downloadQueueClearFinishedTooltip, onPressed: downloadQueueService.clearFinished),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: downloadQueueService,
        builder: (context, child) {
          final downloading = downloadQueueService.downloadingItems;
          final pending = downloadQueueService.pendingCount;
          final done = downloadQueueService.succeededCount;
          final failed = downloadQueueService.failedItems;
          if (downloading.isEmpty && pending == 0 && done == 0 && failed.isEmpty) {
            return Center(child: Text(l10n.downloadQueueEmptyState));
          }
          return CustomScrollView(
            slivers: [
              if (downloading.isNotEmpty) SliverToBoxAdapter(child: _downloadingSection(context, l10n, downloading)),
              if (pending > 0) SliverToBoxAdapter(child: _countRow(Icons.schedule, l10n.downloadQueueQueuedCount(pending))),
              if (done > 0) SliverToBoxAdapter(child: _countRow(Icons.check_circle_outline, l10n.downloadQueueDoneCount(done))),
              if (failed.isNotEmpty) ...[
                SliverToBoxAdapter(child: _sectionHeader(context, l10n.downloadQueueFailedLabel)),
                SliverList.builder(itemCount: failed.length, itemBuilder: (context, index) => _failedRow(context, l10n, failed[index])),
              ],
            ],
          );
        },
      ),
    );
  }
}
