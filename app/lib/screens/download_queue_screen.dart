import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../services/download_queue_service.dart';

/// Shows the client-side download queue (M43) as a real, viewable list
/// rather than just a passing notification -- what's currently downloading,
/// what's still queued, and what failed (with a reason, and a way to retry
/// it). Listens directly to [DownloadQueueService] (already a
/// `ChangeNotifier`) rather than polling, unlike [TaskQueueScreen] (which
/// has to poll since its data lives server-side).
class DownloadQueueScreen extends StatelessWidget {
  final DownloadQueueService downloadQueueService;

  const DownloadQueueScreen({super.key, required this.downloadQueueService});

  String _postLabel(BunnyPost post) {
    final title = post.title;
    return title != null && title.isNotEmpty ? title : '#${post.externalId}';
  }

  Widget _section(BuildContext context, AppLocalizations l10n, String title, List<Widget> children) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text(title, style: Theme.of(context).textTheme.titleMedium)), ...children],
    );
  }

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
          final queued = downloadQueueService.queuedItems;
          final failed = downloadQueueService.failedItems;
          if (current == null && queued.isEmpty && failed.isEmpty) {
            return Center(child: Text(l10n.downloadQueueEmptyState));
          }
          return ListView(
            children: [
              _section(context, l10n, l10n.downloadQueueDownloadingLabel, [
                if (current != null)
                  ListTile(leading: const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)), title: Text(_postLabel(current.post))),
              ]),
              _section(
                context,
                l10n,
                l10n.downloadQueueQueuedLabel,
                queued.map((item) => ListTile(leading: const Icon(Icons.schedule), title: Text(_postLabel(item.post)))).toList(),
              ),
              _section(
                context,
                l10n,
                l10n.downloadQueueFailedLabel,
                failed
                    .map(
                      (item) => ListTile(
                        leading: Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
                        title: Text(_postLabel(item.post)),
                        subtitle: Text(
                          item.status == DownloadQueueItemStatus.checksumMismatch ? l10n.downloadQueueChecksumMismatchReason : (item.failureReason ?? ''),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.replay),
                          tooltip: l10n.downloadQueueRetryTooltip,
                          onPressed: () => downloadQueueService.retryFailed(item),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          );
        },
      ),
    );
  }
}
