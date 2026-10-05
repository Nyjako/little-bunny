import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../settings/display_settings_store.dart';
import '../settings/download_settings_store.dart';
import '../settings/sync_settings_store.dart';
import '../widgets/post_grid_tile.dart';
import 'create_search_screen.dart';
import 'post_detail_screen.dart';

/// Click-through browsing for a tag or artist name tapped elsewhere in the
/// app (M8.5.10): runs a one-page, stateless live search
/// (`BunnyRepository.previewSearch`) and shows the results as a grid,
/// without creating a saved search. An app bar action offers to save the
/// query as a real search via [CreateSearchScreen], pre-filled.
class TagBrowseScreen extends StatefulWidget {
  final BunnySite site;
  final String query;
  final BunnyRepository repository;
  final DisplaySettingsStore displaySettingsStore;
  final SyncSettingsStore syncSettingsStore;
  final DownloadSettingsStore downloadSettingsStore;

  const TagBrowseScreen({
    super.key,
    required this.site,
    required this.query,
    required this.repository,
    required this.displaySettingsStore,
    required this.syncSettingsStore,
    required this.downloadSettingsStore,
  });

  @override
  State<TagBrowseScreen> createState() => _TagBrowseScreenState();
}

class _TagBrowseScreenState extends State<TagBrowseScreen> {
  late final Future<List<BunnyPost>> _postsFuture;
  PreviewQuality _previewQuality = PreviewQuality.thumbnail;
  int _gridColumns = 3;

  @override
  void initState() {
    super.initState();
    _postsFuture = widget.repository.previewSearch(widget.site, widget.query);
    _loadDisplaySettings();
  }

  Future<void> _loadDisplaySettings() async {
    final quality = await widget.displaySettingsStore.loadPreviewQuality();
    final columns = await widget.displaySettingsStore.loadGridColumns();
    if (!mounted) {
      return;
    }
    setState(() {
      _previewQuality = quality;
      _gridColumns = columns;
    });
  }

  String? _imageUrlFor(BunnyPost post) {
    if (_previewQuality == PreviewQuality.medium && post.sampleUrl != null) {
      return post.sampleUrl;
    }
    return post.previewUrl;
  }

  Future<void> _openPost(List<BunnyPost> posts, BunnyPost post) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PostDetailScreen(
          post: post,
          repository: widget.repository,
          displaySettingsStore: widget.displaySettingsStore,
          syncSettingsStore: widget.syncSettingsStore,
          downloadSettingsStore: widget.downloadSettingsStore,
          siblingPosts: posts,
        ),
      ),
    );
  }

  Future<void> _addToSearches() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => CreateSearchScreen(repository: widget.repository, syncSettingsStore: widget.syncSettingsStore, initialSite: widget.site, initialQuery: widget.query)),
    );
    if (created == true && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.query),
        actions: [IconButton(icon: const Icon(Icons.add), tooltip: l10n.tagBrowseAddToSearchesTooltip, onPressed: _addToSearches)],
      ),
      body: FutureBuilder<List<BunnyPost>>(
        future: _postsFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final posts = snapshot.data!;
          if (posts.isEmpty) {
            return Center(child: Text(l10n.tagBrowseEmptyState));
          }
          return GridView.builder(
            padding: const EdgeInsets.all(4),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: _gridColumns, crossAxisSpacing: 4, mainAxisSpacing: 4),
            itemCount: posts.length,
            itemBuilder: (context, index) {
              final post = posts[index];
              return PostGridTile(key: ValueKey(post.id), post: post, imageUrl: _imageUrlFor(post), onTap: () => _openPost(posts, post));
            },
          );
        },
      ),
    );
  }
}
