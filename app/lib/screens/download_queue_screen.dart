import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

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
/// them. Only "currently downloading" (always at most one item) and
/// "failed" (usually a small, bounded set needing an actual retry action)
/// render real rows; failed rows go through a lazy [SliverList] rather than
/// a plain `ListView(children: ...)` so even a pathological "everything
/// failed" batch only builds what's actually scrolled into view. Before this
/// (M43-follow-up), the queued/failed sections were built as eager
/// `.map().toList()` lists fed straight into a non-lazy `ListView`, which,
/// combined with this screen rebuilding on every single item's progress
/// tick while a batch is active, made opening this screen with a few
/// thousand pending items effectively unusable.
class DownloadQueueScreen extends StatelessWidget {
  final DownloadQueueService downloadQueueService;

  const DownloadQueueScreen({super.key, required this.downloadQueueService});

  String _postLabel(BunnyPost post) {
    final title = post.title;
    return title != null && title.isNotEmpty ? title : '#${post.externalId}';
  }

  Widget _sectionHeader(BuildContext context, String title) =>
      Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text(title, style: Theme.of(context).textTheme.titleMedium));

  Widget _downloadingSection(BuildContext context, AppLocalizations l10n, DownloadQueueItem current) {
    final total = downloadQueueService.totalCount;
    final done = downloadQueueService.completedCount;
    final bytesReceived = downloadQueueService.currentBytesReceived;
    final bytesTotal = downloadQueueService.currentBytesTotal;
    final previewUrl = current.post.previewUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, l10n.downloadQueueDownloadingLabel),
        ListTile(
          leading: SizedBox(
            width: 40,
            height: 40,
            child: previewUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: CachedNetworkImage(imageUrl: previewUrl, httpHeaders: imageHeadersFor(current.post.site), fit: BoxFit.cover),
                  )
                : const Icon(Icons.image_outlined),
          ),
          title: Text(_postLabel(current.post)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Batch-level progress (done/total of the whole run).
              LinearProgressIndicator(key: const Key('downloadQueueBatchProgressBar'), value: total > 0 ? done / total : null),
              const SizedBox(height: 6),
              // This one file's own byte progress (M62) -- indeterminate
              // until the first chunk arrives, or whenever the response had
              // no Content-Length to compute a fraction from.
              LinearProgressIndicator(
                key: const Key('downloadQueueCurrentFileProgressBar'),
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
        ),
      ],
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
          final current = downloadQueueService.currentItem;
          final pending = downloadQueueService.pendingCount;
          final done = downloadQueueService.succeededCount;
          final failed = downloadQueueService.failedItems;
          if (current == null && pending == 0 && done == 0 && failed.isEmpty) {
            return Center(child: Text(l10n.downloadQueueEmptyState));
          }
          return CustomScrollView(
            slivers: [
              if (current != null) SliverToBoxAdapter(child: _downloadingSection(context, l10n, current)),
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
