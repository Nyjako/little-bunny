import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/widgets/post_grid_tile.dart';

import '../fakes/test_app.dart';

BunnyPost _post({String? fileExt}) => BunnyPost(
  id: 1,
  site: BunnySite.e621,
  externalId: 1,
  score: 0,
  favCount: 0,
  commentCount: 0,
  fileExt: fileExt,
  width: 100,
  height: 100,
  cachedAt: '2026-01-01T00:00:00Z',
  isSeen: true,
  isFavorited: false,
);

void main() {
  Widget wrap(BunnyPost post) => wrapWithLocalization(Material(child: PostGridTile(post: post, imageUrl: null, onTap: () {})));

  testWidgets('shows a play icon for a video post', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(_post(fileExt: 'webm')));

    expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);
    expect(find.text('GIF'), findsNothing);
  });

  testWidgets('shows a GIF chip for a gif post', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(_post(fileExt: 'gif')));

    expect(find.text('GIF'), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_fill), findsNothing);
  });

  testWidgets('shows no media-type badge for a plain image post', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(_post(fileExt: 'jpg')));

    expect(find.byIcon(Icons.play_circle_fill), findsNothing);
    expect(find.text('GIF'), findsNothing);
  });
}
