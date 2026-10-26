import 'package:flutter/material.dart';

/// A loading spinner that shows a percentage in its center once the total
/// download size is known (M48) -- used both by still images
/// (`CachedNetworkImage`'s `progressIndicatorBuilder`) and [GifPlayer]'s own
/// pre-decode loading state, so both share one visual. Falls back to a plain
/// indeterminate spinner when [progress] is null (total size unknown, or not
/// downloading at all yet).
class DownloadProgressIndicator extends StatelessWidget {
  final double? progress;

  const DownloadProgressIndicator({super.key, this.progress});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(value: progress),
          if (progress != null) Text('${(progress! * 100).round()}%', style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}
