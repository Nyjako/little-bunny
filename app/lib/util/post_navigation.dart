import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../screens/post_detail_screen.dart';
import '../services/download_queue_service.dart';
import '../settings/display_settings_store.dart';
import '../settings/download_settings_store.dart';

/// Opens a post by its external (site-native) id -- a parent/child (M13.3),
/// pool, or wiki `thumb #<id>` (M50/M53) cross-reference, i.e. any link that
/// names a post outside the current (possibly blacklist-filtered) search
/// result set, so unlike the normal grid a blacklisted post can actually
/// surface here and needs its own confirmation. Shared by [PostDetailScreen]
/// and the wiki page viewer rather than duplicated in each.
Future<void> openExternalPost({
  required BuildContext context,
  required AppLocalizations l10n,
  required BunnyRepository repository,
  required BunnySite site,
  required int externalId,
  required DisplaySettingsStore displaySettingsStore,
  required DownloadSettingsStore downloadSettingsStore,
  required DownloadQueueService downloadQueueService,
}) async {
  try {
    final postId = await repository.fetchPost(site, externalId);
    final post = await repository.getPost(postId);
    if (!context.mounted) {
      return;
    }
    final tags = await repository.getPostTagsByCategory(post.id);
    final blacklist = await repository.getBlacklist(post.site);
    final matched = tags.map((tag) => tag.name).where(blacklist.contains).toList();
    if (matched.isNotEmpty) {
      if (!context.mounted) {
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.postDetailBlacklistedDialogTitle),
          content: Text(l10n.postDetailBlacklistedDialogContent(matched.join(', '))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.commonCancel)),
            TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.postDetailBlacklistedViewAnyway)),
          ],
        ),
      );
      if (confirmed != true) {
        return;
      }
    }
    if (!context.mounted) {
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PostDetailScreen(
          post: post,
          repository: repository,
          displaySettingsStore: displaySettingsStore,
          downloadSettingsStore: downloadSettingsStore,
          downloadQueueService: downloadQueueService,
        ),
      ),
    );
  } catch (_) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.postDetailOpenPostFailed)));
  }
}
