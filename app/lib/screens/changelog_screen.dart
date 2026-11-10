import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../services/update_check_service.dart';
import '../widgets/release_notes_text.dart';

/// Shows the last ~20 GitHub releases (no pagination), reachable from
/// [AboutScreen]'s "View changelog" entry -- unlike the update dialog
/// (which only ever shows the latest release's notes), this is the one
/// place to see anything further back.
class ChangelogScreen extends StatefulWidget {
  /// Injectable for tests; defaults to a real instance.
  final UpdateCheckService checkService;

  const ChangelogScreen({super.key, this.checkService = const UpdateCheckService()});

  @override
  State<ChangelogScreen> createState() => _ChangelogScreenState();
}

class _ChangelogScreenState extends State<ChangelogScreen> {
  late Future<List<ReleaseInfo>> _releasesFuture;

  @override
  void initState() {
    super.initState();
    _releasesFuture = widget.checkService.fetchRecentReleases();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.changelogScreenTitle)),
      body: FutureBuilder<List<ReleaseInfo>>(
        future: _releasesFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(l10n.changelogLoadError('${snapshot.error}')));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final releases = snapshot.data!;
          if (releases.isEmpty) {
            return Center(child: Text(l10n.changelogEmptyState));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: releases.length,
            separatorBuilder: (context, index) => const Divider(height: 32),
            itemBuilder: (context, index) {
              final release = releases[index];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(release.tagName, style: Theme.of(context).textTheme.titleLarge),
                      if (release.publishedAt != null) ...[
                        const SizedBox(width: 8),
                        Text(DateFormat.yMMMd().format(release.publishedAt!.toLocal()), style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  if ((release.body ?? '').isNotEmpty) ReleaseNotesText(text: release.body!),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
