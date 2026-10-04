import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/widgets/rating_badge.dart';

import '../fakes/test_app.dart';

void main() {
  group('ratingBadgeFor', () {
    test('maps every e621 rating letter to its color and label', () {
      expect(ratingBadgeFor(BunnySite.e621, 's'), (Colors.green, 'S'));
      expect(ratingBadgeFor(BunnySite.e621, 'q'), (Colors.amber, 'Q'));
      expect(ratingBadgeFor(BunnySite.e621, 'e'), (Colors.red, 'E'));
    });

    test('is case-insensitive for e621 ratings', () {
      expect(ratingBadgeFor(BunnySite.e621, 'S'), (Colors.green, 'S'));
    });

    test('falls back to a grey badge showing the raw string for an unrecognized e621 rating', () {
      expect(ratingBadgeFor(BunnySite.e621, 'x'), (Colors.grey, 'x'));
    });

    test('best-effort keyword-matches common Inkbunny rating_name strings', () {
      expect(ratingBadgeFor(BunnySite.inkbunny, 'General'), (Colors.green, 'General'));
      expect(ratingBadgeFor(BunnySite.inkbunny, 'Mature'), (Colors.amber, 'Mature'));
      expect(ratingBadgeFor(BunnySite.inkbunny, 'Adult'), (Colors.red, 'Adult'));
    });

    test('falls back to a grey badge showing the raw string for an unrecognized Inkbunny rating', () {
      expect(ratingBadgeFor(BunnySite.inkbunny, 'Somethingelse'), (Colors.grey, 'Somethingelse'));
    });

    test('falls back to a grey "?" badge when rating is null or empty', () {
      expect(ratingBadgeFor(BunnySite.e621, null), (Colors.grey, '?'));
      expect(ratingBadgeFor(BunnySite.inkbunny, ''), (Colors.grey, '?'));
    });
  });

  group('RatingBadge', () {
    testWidgets('renders the mapped label', (WidgetTester tester) async {
      await tester.pumpWidget(wrapWithLocalization(const RatingBadge(site: BunnySite.e621, rating: 'e')));

      expect(find.text('E'), findsOneWidget);
    });
  });
}
