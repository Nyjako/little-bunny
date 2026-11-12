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

/// The group picker (M21) can push the Save button below the fold on the
/// test surface's default height (e.g. once the Inkbunny star picker is
/// also showing) -- scroll it into view first rather than tapping blind.
Future<void> _tapSave(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Save'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Save'));
}

void main() {
  testWidgets('pre-fills every field from the given search', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final search = await _seedSearch(repository);

    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
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

    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(wrapWithLocalization(EditSearchScreen(repository: repository, search: e621Search)));
    await tester.pumpAndSettle();
    expect(find.text('Favorite level'), findsNothing);
    expect(find.widgetWithText(SwitchListTile, 'Auto-upvote new posts'), findsOneWidget);

    final inkbunnySearch = await _seedSearch(repository, site: BunnySite.inkbunny);
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(wrapWithLocalization(EditSearchScreen(repository: repository, search: inkbunnySearch)));
    await tester.pumpAndSettle();
    expect(find.text('Favorite level'), findsOneWidget);
    expect(find.widgetWithText(SwitchListTile, 'Auto-upvote new posts'), findsNothing);
  });

  testWidgets('saving updates the search and pops true (M9.7.2)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final search = await _seedSearch(repository);

    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(wrapWithLocalization(EditSearchScreen(repository: repository, search: search)));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Label'), 'Renamed');
    await tester.enterText(find.widgetWithText(TextFormField, 'Query'), 'wolf');
    await _tapSave(tester);
    await tester.pumpAndSettle();

    final updated = repository.searches.single;
    expect(updated.label, 'Renamed');
    expect(updated.query, 'wolf');
  });

  testWidgets('tapping delete then confirming removes the search (M14.1)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final search = await _seedSearch(repository);

    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
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

    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
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

    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(wrapWithLocalization(EditSearchScreen(repository: repository, search: search)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();
    await _tapSave(tester);
    await tester.pumpAndSettle();

    expect(repository.searches.single.autoFavoriteStars, 3);
  });

  testWidgets('enabling "use default interval" disables the interval field and persists on save (M20)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final search = await _seedSearch(repository);
    expect(search.usesDefaultInterval, isFalse);

    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(wrapWithLocalization(EditSearchScreen(repository: repository, search: search)));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SwitchListTile, 'Use default interval'));
    await tester.pumpAndSettle();

    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Sync interval (hours)')).enabled, isFalse);

    await _tapSave(tester);
    await tester.pumpAndSettle();

    expect(repository.searches.single.usesDefaultInterval, isTrue);
  });

  testWidgets('an invalid query shows an error and blocks saving (M28/M54)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final search = await _seedSearch(repository);

    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(wrapWithLocalization(EditSearchScreen(repository: repository, search: search)));
    await tester.pumpAndSettle();

    repository.validateTagQueryResult = 0;
    await tester.enterText(find.widgetWithText(TextFormField, 'Query'), '( unbalanced');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('Invalid syntax'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNull);

    await _tapSave(tester);
    await tester.pumpAndSettle();
    expect(repository.searches.single.query, 'fox');

    repository.validateTagQueryResult = null;
    await tester.enterText(find.widgetWithText(TextFormField, 'Query'), 'wolf -snow');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('Invalid syntax'), findsNothing);
    await _tapSave(tester);
    await tester.pumpAndSettle();

    expect(repository.searches.single.query, 'wolf -snow');
  });

  testWidgets('typing an aliased tag shows a non-blocking hint with its canonical name (M54)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final search = await _seedSearch(repository);
    repository.tagAliasesByNameMatches['cat'] = const [BunnyTagAlias(id: 1, antecedentName: 'cat', consequentName: 'domestic_cat', status: 'active', postCount: 0)];

    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(wrapWithLocalization(EditSearchScreen(repository: repository, search: search)));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Query'), 'cat');
    await tester.pump(const Duration(seconds: 3, milliseconds: 50));

    expect(find.text('"cat" is aliased to "domestic_cat"'), findsOneWidget);
  });

  testWidgets('no alias hint for an Inkbunny search, which has no alias concept (M54)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final search = await _seedSearch(repository, site: BunnySite.inkbunny);
    repository.tagAliasesByNameMatches['cat'] = const [BunnyTagAlias(id: 1, antecedentName: 'cat', consequentName: 'domestic_cat', status: 'active', postCount: 0)];

    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(wrapWithLocalization(EditSearchScreen(repository: repository, search: search)));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Query'), 'cat');
    await tester.pump(const Duration(seconds: 3, milliseconds: 50));

    expect(find.textContaining('is aliased to'), findsNothing);
  });

  testWidgets('typing a tag with implications shows the full chain (M54)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final search = await _seedSearch(repository);
    repository.tagImplicationsByNameMatches['hyper_breasts'] = const [BunnyTagImplication(id: 1, antecedentName: 'hyper_breasts', consequentName: 'breasts', status: 'active')];

    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(wrapWithLocalization(EditSearchScreen(repository: repository, search: search)));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Query'), 'hyper_breasts');
    await tester.pump(const Duration(seconds: 3, milliseconds: 50));

    expect(find.text('hyper_breasts → breasts'), findsOneWidget);
  });

  testWidgets('no implication chain for an Inkbunny search, which has no implication concept (M54)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    final search = await _seedSearch(repository, site: BunnySite.inkbunny);
    repository.tagImplicationsByNameMatches['hyper_breasts'] = const [BunnyTagImplication(id: 1, antecedentName: 'hyper_breasts', consequentName: 'breasts', status: 'active')];

    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(wrapWithLocalization(EditSearchScreen(repository: repository, search: search)));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Query'), 'hyper_breasts');
    await tester.pump(const Duration(seconds: 3, milliseconds: 50));

    expect(find.textContaining('→'), findsNothing);
  });
}
