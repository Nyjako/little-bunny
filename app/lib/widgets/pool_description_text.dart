import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../util/pool_description.dart';

/// Renders a pool's description (M26) with any `pool #<id>` cross-references
/// in it as inline, tappable links (M44) -- replaces the earlier layout of
/// plain description text followed by a separate row of chips, one per
/// reference, below it. [onOpenPool] is called with the referenced pool's
/// id when one of those inline links is tapped.
class PoolDescriptionText extends StatelessWidget {
  final String description;
  final void Function(int poolId) onOpenPool;

  const PoolDescriptionText({super.key, required this.description, required this.onOpenPool});

  @override
  Widget build(BuildContext context) {
    final linkColor = Theme.of(context).colorScheme.primary;
    return Text.rich(
      TextSpan(
        children: parsePoolDescriptionSegments(description).map((segment) {
          return switch (segment) {
            PoolDescriptionTextSegment(text: final text) => TextSpan(text: text),
            PoolDescriptionReferenceSegment(poolId: final poolId, matchedText: final matchedText) => TextSpan(
              text: matchedText,
              style: TextStyle(color: linkColor, decoration: TextDecoration.underline),
              recognizer: TapGestureRecognizer()..onTap = () => onOpenPool(poolId),
            ),
          };
        }).toList(),
      ),
    );
  }
}
