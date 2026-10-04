import 'package:flutter/material.dart';

import '../repository/bunny_models.dart';

/// Pure mapping from a post's (site, rating) to a badge color + short label,
/// for [PostGridScreen]'s tile overlay. e621's rating is a fixed 3-value
/// encoding (`"s"`/`"q"`/`"e"`, see `e621_rating_to_text` in `sync.c`), so it
/// maps cleanly to a single letter. Inkbunny's `rating_name` is free text
/// (e.g. `"General"`, `"Mature"`, `"Explicit"`) with no fixed set of values,
/// so it's best-effort keyword-matched; anything unrecognized (on either
/// site) falls back to a neutral grey badge showing the raw string rather
/// than hiding it or crashing.
(Color, String) ratingBadgeFor(BunnySite site, String? rating) {
  if (rating == null || rating.isEmpty) {
    return (Colors.grey, '?');
  }

  if (site == BunnySite.e621) {
    switch (rating.toLowerCase()) {
      case 's':
        return (Colors.green, 'S');
      case 'q':
        return (Colors.amber, 'Q');
      case 'e':
        return (Colors.red, 'E');
      default:
        return (Colors.grey, rating);
    }
  }

  final normalized = rating.toLowerCase();
  if (normalized.contains('general') || normalized.contains('safe')) {
    return (Colors.green, rating);
  }
  if (normalized.contains('mature') || normalized.contains('moderate') || normalized.contains('questionable')) {
    return (Colors.amber, rating);
  }
  if (normalized.contains('explicit') || normalized.contains('adult')) {
    return (Colors.red, rating);
  }
  return (Colors.grey, rating);
}

/// A small colored chip showing [ratingBadgeFor]'s result, meant to be
/// overlaid on a post grid tile.
class RatingBadge extends StatelessWidget {
  final BunnySite site;
  final String? rating;

  const RatingBadge({super.key, required this.site, this.rating});

  @override
  Widget build(BuildContext context) {
    final (color, label) = ratingBadgeFor(site, rating);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}
