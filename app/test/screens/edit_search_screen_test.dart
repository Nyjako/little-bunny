import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/screens/edit_search_screen.dart';

import '../fakes/fake_bunny_repository.dart';
import '../fakes/test_app.dart';

Future<BunnySearch> _seedSearch(FakeBunnyRepository repository, {BunnySite site = BunnySite.e621}) async {
  final id = await repository.createSearch(site, 'Foxes', 'fox', intervalHours: 12, autoFavorite: true, autoFavoriteStars: 2, autoUpvote: site == BunnySite.e621);
  return repository.searches.firstWhere((search) => search.id == id);
}

void main() {
  testWidgets('pre-fills every field from the given search', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final search = await _seedSearch(repository);

    await tester.pumpWidget(wrapWithLocalization(EditSearchScreen(repository: repository, search: search)));
    await tester.pumpAndSettle();

    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Label')).controller!.text, 'Foxes');
    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Query')).controller!.text, 'fox');
    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Sync interval (hours)')).controller!.text, '12');
    expect(find.text('Site: e621'), findsOneWidget);
  });

  testWidgets('the Inkbunny star picker is shown only for Inkbunny searches', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final e621Search = await _seedSearch(repository, site: BunnySite.e621);

    await tester.pumpWidget(wrapWithLocalization(EditSearchScreen(repository: repository, search: e621Search)));
    await tester.pumpAndSettle();
    expect(find.text('Favorite level'), findsNothing);
    expect(find.widgetWithText(SwitchListTile, 'Auto-upvote new posts'), findsOneWidget);

    final inkbunnySearch = await _seedSearch(repository, site: BunnySite.inkbunny);
    await tester.pumpWidget(wrapWithLocalization(EditSearchScreen(repository: repository, search: inkbunnySearch)));
    await tester.pumpAndSettle();
    expect(find.text('Favorite level'), findsOneWidget);
    expect(find.widgetWithText(SwitchListTile, 'Auto-upvote new posts'), findsNothing);
  });

  testWidgets('saving updates the search and pops true (M9.7.2)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final search = await _seedSearch(repository);

    await tester.pumpWidget(wrapWithLocalization(EditSearchScreen(repository: repository, search: search)));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Label'), 'Renamed');
    await tester.enterText(find.widgetWithText(TextFormField, 'Query'), 'wolf');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final updated = repository.searches.single;
    expect(updated.label, 'Renamed');
    expect(updated.query, 'wolf');
  });

  testWidgets('tapping delete then confirming removes the search (M14.1)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final search = await _seedSearch(repository);

    await tester.pumpWidget(wrapWithLocalization(EditSearchScreen(repository: repository, search: search)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete));
    await tester.pumpAndSettle();
    expect(find.text('Remove search?'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(repository.searches, isEmpty);
  });

  testWidgets('tapping delete then cancelling keeps the search (M14.1)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final search = await _seedSearch(repository);

    await tester.pumpWidget(wrapWithLocalization(EditSearchScreen(repository: repository, search: search)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repository.searches, hasLength(1));
  });

  testWidgets('picking a star level for an Inkbunny search updates auto_favorite_stars', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final search = await _seedSearch(repository, site: BunnySite.inkbunny);

    await tester.pumpWidget(wrapWithLocalization(EditSearchScreen(repository: repository, search: search)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repository.searches.single.autoFavoriteStars, 3);
  });

  testWidgets('enabling "use default interval" disables the interval field and persists on save (M20)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final search = await _seedSearch(repository);
    expect(search.usesDefaultInterval, isFalse);

    await tester.pumpWidget(wrapWithLocalization(EditSearchScreen(repository: repository, search: search)));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SwitchListTile, 'Use default interval'));
    await tester.pumpAndSettle();

    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Sync interval (hours)')).enabled, isFalse);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repository.searches.single.usesDefaultInterval, isTrue);
  });
}
