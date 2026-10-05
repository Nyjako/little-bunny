import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../repository/bunny_models.dart';
import '../util/image_headers.dart';
import 'rating_badge.dart';

/// A single thumbnail tile for a post grid -- the rating badge/unseen-dot/
/// score-favCount overlay [PostGridScreen] originally built inline (M8.3,
/// badges added M8.5.7), factored out here (M8.5.10) so [TagBrowseScreen]
/// can reuse it instead of duplicating the whole `Stack`. [selected]/
/// [onLongPress]/[selectionMode] (M9.2, [selectionMode] split out in M9.6.1)
/// all default to not-selectable, so [TagBrowseScreen] (which has no
/// selection mode) is unaffected. [selectionMode] is deliberately separate
/// from [onLongPress] being non-null: [PostGridScreen] always wires up
/// [onLongPress] (so long-pressing any tile can *enter* selection mode from
/// normal browsing), but the selection checkmark/circle overlay itself must
/// only render once selection mode is actually active.
class PostGridTile extends StatelessWidget {
  final BunnyPost post;
  final String? imageUrl;
  final VoidCallback onTap;
  final bool selected;
  final VoidCallback? onLongPress;
  final bool selectionMode;

  const PostGridTile({super.key, required this.post, required this.imageUrl, required this.onTap, this.selected = false, this.onLongPress, this.selectionMode = false});

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url != null) CachedNetworkImage(imageUrl: url, httpHeaders: imageHeadersFor(post.site), fit: BoxFit.cover) else const ColoredBox(color: Colors.black12),
          if (selected) Container(color: Colors.black45),
          if (!post.isSeen && !selectionMode) Positioned(top: 4, right: 4, child: Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle))),
          Positioned(top: 4, left: 4, child: RatingBadge(site: post.site, rating: post.rating)),
          // Selection mode replaces the unseen dot in this corner with a
          // (de)selected checkmark -- both are small status markers for the
          // same corner, and which one matters more depends on whether
          // selection mode is active.
          if (selectionMode)
            Positioned(
              top: 4,
              right: 4,
              child: Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked, color: selected ? Colors.lightBlueAccent : Colors.white70),
            ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              color: Colors.black54,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.arrow_upward, size: 10, color: Colors.white),
                      Text('${post.score}', style: const TextStyle(color: Colors.white, fontSize: 10)),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.favorite, size: 10, color: Colors.white),
                      Text('${post.favCount}', style: const TextStyle(color: Colors.white, fontSize: 10)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
