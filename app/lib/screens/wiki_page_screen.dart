import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../services/download_queue_service.dart';
import '../settings/display_settings_store.dart';
import '../settings/download_settings_store.dart';
import '../util/post_navigation.dart';
import '../widgets/rich_markup_text.dart';
import 'tag_browse_screen.dart';

/// Shows a single e621 tag's wiki page body (M52/M53) -- e621-only, same
/// reasoning as [BunnyWikiPage] itself (Inkbunny has no equivalent).
/// `{{author}}`/`[[title]]`/`thumb #<id>` cross-references in the body are
/// rendered live via [RichMarkupText]: an author reference opens that
/// artist's posts, a wiki reference opens another [WikiPageScreen] for that
/// title, and a thumb reference opens the referenced post directly.
class WikiPageScreen extends StatefulWidget {
  final String title;
  final BunnyRepository repository;
  final DisplaySettingsStore displaySettingsStore;
  final DownloadSettingsStore downloadSettingsStore;
  final DownloadQueueService downloadQueueService;

  const WikiPageScreen({
    super.key,
    required this.title,
    required this.repository,
    required this.displaySettingsStore,
    required this.downloadSettingsStore,
    required this.downloadQueueService,
  });

  @override
  State<WikiPageScreen> createState() => _WikiPageScreenState();
}

class _WikiPageScreenState extends State<WikiPageScreen> {
  late Future<BunnyWikiPage?> _pageFuture;

  @override
  void initState() {
    super.initState();
    _pageFuture = widget.repository.getWikiPage(widget.title);
  }

  void _openAuthor(String authorName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TagBrowseScreen(
          site: BunnySite.e621,
          query: authorName,
          repository: widget.repository,
          displaySettingsStore: widget.displaySettingsStore,
          downloadSettingsStore: widget.downloadSettingsStore,
          downloadQueueService: widget.downloadQueueService,
        ),
      ),
    );
  }

  void _openWiki(String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WikiPageScreen(
          title: title,
          repository: widget.repository,
          displaySettingsStore: widget.displaySettingsStore,
          downloadSettingsStore: widget.downloadSettingsStore,
          downloadQueueService: widget.downloadQueueService,
        ),
      ),
    );
  }

  void _openPost(AppLocalizations l10n, BunnySite site, int postId) {
    openExternalPost(
      context: context,
      l10n: l10n,
      repository: widget.repository,
      site: site,
      externalId: postId,
      displaySettingsStore: widget.displaySettingsStore,
      downloadSettingsStore: widget.downloadSettingsStore,
      downloadQueueService: widget.downloadQueueService,
    );
  }

  void _openPool(int poolId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TagBrowseScreen(
          site: BunnySite.e621,
          query: 'pool:$poolId',
          repository: widget.repository,
          displaySettingsStore: widget.displaySettingsStore,
          downloadSettingsStore: widget.downloadSettingsStore,
          downloadQueueService: widget.downloadQueueService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: FutureBuilder<BunnyWikiPage?>(
        future: _pageFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(l10n.wikiPageLoadFailedMessage));
          }
          final page = snapshot.data;
          if (page == null || page.body == null || page.body!.isEmpty) {
            return Center(child: Text(l10n.wikiPageNotFoundMessage));
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (page.otherNames.isNotEmpty) ...[
                  Text(l10n.wikiPageOtherNamesLabel(page.otherNames.join(', ')), style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 12),
                ],
                RichMarkupText(
                  text: page.body!,
                  onOpenAuthor: _openAuthor,
                  onOpenWiki: _openWiki,
                  onOpenPost: (site, postId) => _openPost(l10n, site, postId),
                  onOpenPool: _openPool,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
