import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';

const _imageExtensions = {'jpg', 'jpeg', 'png', 'gif', 'webp'};
const _videoExtensions = {'webm', 'mp4'};

/// Full read-only metadata + media viewer for a single post (M8.4). No
/// favorite/vote/comment actions yet -- that's M9's scope. Marks the post
/// seen once, on open, same as tapping it used to in `PostGridScreen` before
/// this screen existed.
class PostDetailScreen extends StatefulWidget {
  final BunnyPost post;
  final BunnyRepository repository;

  const PostDetailScreen({super.key, required this.post, required this.repository});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  VideoPlayerController? _videoController;
  Future<void>? _videoInitFuture;

  @override
  void initState() {
    super.initState();
    widget.repository.markPostSeen(widget.post.id);

    final ext = widget.post.fileExt?.toLowerCase();
    final url = widget.post.fileUrl;
    if (ext != null && _videoExtensions.contains(ext) && url != null) {
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      _videoController = controller;
      _videoInitFuture = controller.initialize().then((_) {
        if (!mounted) {
          return;
        }
        controller.setLooping(true);
        controller.play();
        setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  void _toggleVideoPlayback() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    setState(() {
      controller.value.isPlaying ? controller.pause() : controller.play();
    });
  }

  Widget _buildMedia(AppLocalizations l10n) {
    final post = widget.post;
    final ext = post.fileExt?.toLowerCase();
    if (ext == null || post.fileUrl == null) {
      return const SizedBox(height: 200);
    }
    if (_imageExtensions.contains(ext)) {
      return SizedBox(height: 400, child: CachedNetworkImage(imageUrl: post.fileUrl!, fit: BoxFit.contain));
    }
    if (_videoExtensions.contains(ext)) {
      return FutureBuilder<void>(
        future: _videoInitFuture,
        builder: (context, snapshot) {
          final controller = _videoController!;
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(height: 300, child: Center(child: CircularProgressIndicator()));
          }
          return GestureDetector(onTap: _toggleVideoPlayback, child: AspectRatio(aspectRatio: controller.value.aspectRatio, child: VideoPlayer(controller)));
        },
      );
    }
    return SizedBox(height: 200, child: Center(child: Text(l10n.postDetailUnsupportedFormat(ext))));
  }

  Widget _metadataRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 100, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold))), Expanded(child: Text(value))]),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final post = widget.post;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.postDetailScreenTitle)),
      body: ListView(
        children: [
          _buildMedia(l10n),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (post.title != null && post.title!.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(post.title!, style: Theme.of(context).textTheme.titleLarge)),
                _metadataRow(l10n.postDetailArtistLabel, post.artist ?? l10n.postDetailUnknownValue),
                if (post.description != null && post.description!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8, bottom: 8), child: Text(post.description!)),
                const Divider(),
                _metadataRow(l10n.postDetailRatingLabel, post.rating ?? l10n.postDetailUnknownValue),
                _metadataRow(l10n.postDetailScoreLabel, '${post.score}'),
                _metadataRow(l10n.postDetailFavoritesLabel, '${post.favCount}'),
                _metadataRow(l10n.postDetailCommentsLabel, '${post.commentCount}'),
                _metadataRow(l10n.postDetailDimensionsLabel, '${post.width}x${post.height}'),
                _metadataRow(l10n.postDetailCreatedLabel, post.createdAtSite ?? l10n.postDetailUnknownValue),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
