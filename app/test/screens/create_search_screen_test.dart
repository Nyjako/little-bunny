import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/screens/create_search_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_bunny_repository.dart';
import '../fakes/test_app.dart';

Widget _wrap(FakeBunnyRepository repository) => wrapWithLocalization(CreateSearchScreen(repository: repository));

/// The group picker (M21) pushed the Create button below the fold on the
/// test surface's default height -- scroll it into view first rather than
/// tapping blind, same fix needed at every call site below.
Future<void> _tapCreate(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Create'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Create'));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('validates required fields before submitting', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await _tapCreate(tester);
    await tester.pumpAndSettle();

    expect(find.text('Required'), findsNWidgets(2));
    expect(repository.searches, isEmpty);
  });

  testWidgets('submitting a filled form creates the search and pops true', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Label'), 'Foxes');
    await tester.enterText(find.widgetWithText(TextFormField, 'Query'), 'fox');
    await _tapCreate(tester);
    await tester.pumpAndSettle();

    expect(repository.searches, hasLength(1));
    expect(repository.searches.single.label, 'Foxes');
    expect(repository.searches.single.query, 'fox');
    expect(repository.searches.single.site, BunnySite.e621);
    expect(repository.searches.single.intervalHours, 24);
    expect(repository.searches.single.autoFavorite, isFalse);
  });

  testWidgets('toggling auto-favorite creates the search with it set (M9.6.8)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Label'), 'Foxes');
    await tester.enterText(find.widgetWithText(TextFormField, 'Query'), 'fox');
    await tester.tap(find.widgetWithText(SwitchListTile, 'Auto-favorite new posts'));
    await tester.pumpAndSettle();
    await _tapCreate(tester);
    await tester.pumpAndSettle();

    expect(repository.searches.single.autoFavorite, isTrue);
  });

  testWidgets('toggling auto-upvote creates the search with it set, hidden for Inkbunny (M9.7.2)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(SwitchListTile, 'Auto-upvote new posts'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Label'), 'Foxes');
    await tester.enterText(find.widgetWithText(TextFormField, 'Query'), 'fox');
    await tester.tap(find.widgetWithText(SwitchListTile, 'Auto-upvote new posts'));
    await tester.pumpAndSettle();
    await _tapCreate(tester);
    await tester.pumpAndSettle();

    expect(repository.searches.single.autoUpvote, isTrue);
  });

  testWidgets('auto-upvote switch is hidden for Inkbunny searches (M9.7.2)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inkbunny'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(SwitchListTile, 'Auto-upvote new posts'), findsNothing);
  });

  testWidgets('typing a query word shows debounced tag suggestions for that word only', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.tagStats.addAll(const [BunnyTagStat(name: 'foxtail', count: 10), BunnyTagStat(name: 'wolfpack', count: 5)]);

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Query'), 'canine foxta');
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('foxtail (10)'), findsOneWidget);
    expect(find.text('wolfpack (5)'), findsNothing);

    await tester.tap(find.text('foxtail (10)'));
    await tester.pump();

    final field = tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Query'));
    expect(field.controller!.text, 'canine foxtail ');
  });

  testWidgets('a tag shorter than the minimum autocomplete prefix (M39) shows no suggestions', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.tagStats.addAll(const [BunnyTagStat(name: 'fox', count: 10)]);

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Query'), 'canine fo');
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('fox (10)'), findsNothing);
  });

  testWidgets('negated tags still autocomplete and keep their - prefix (M9.6.7)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.tagStats.addAll(const [BunnyTagStat(name: 'dogsled', count: 7)]);

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Query'), 'cat -dogsl');
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('dogsled (7)'), findsOneWidget);

    await tester.tap(find.text('dogsled (7)'));
    await tester.pump();

    final field = tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Query'));
    expect(field.controller!.text, 'cat -dogsled ');
  });

  testWidgets('a wildcard token skips autocomplete entirely (M9.6.7)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.tagStats.addAll(const [BunnyTagStat(name: 'african_wild_dog', count: 3)]);

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Query'), 'african_*');
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('african_wild_dog (3)'), findsNothing);
  });

  testWidgets('picking a site changes which site the search is created for', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inkbunny'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Label'), 'Foxes');
    await tester.enterText(find.widgetWithText(TextFormField, 'Query'), 'fox');
    await _tapCreate(tester);
    await tester.pumpAndSettle();

    expect(repository.searches.single.site, BunnySite.inkbunny);
  });

  testWidgets('label mirrors the query until the user edits the label directly', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Query'), 'cat -dog standing');
    await tester.pump();
    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Label')).controller!.text, 'cat -dog standing');

    // Further query edits still mirror...
    await tester.enterText(find.widgetWithText(TextFormField, 'Query'), 'cat -dog standing rating:s');
    await tester.pump();
    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Label')).controller!.text, 'cat -dog standing rating:s');

    // ...until the user types into the label directly, after which it stops.
    await tester.enterText(find.widgetWithText(TextFormField, 'Label'), 'My custom label');
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextFormField, 'Query'), 'cat -dog standing rating:s score:>10');
    await tester.pump();
    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Label')).controller!.text, 'My custom label');
  });

  testWidgets('interval field pre-fills from the server-side default (M20)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository()..defaultSyncIntervalHours = 12;

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Sync interval (hours)')).controller!.text, '12');
  });

  testWidgets('initialSite/initialQuery pre-fill the site and query (and mirror into the label)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();

    await tester.pumpWidget(wrapWithLocalization(CreateSearchScreen(repository: repository, initialSite: BunnySite.inkbunny, initialQuery: 'someartist')));
    await tester.pumpAndSettle();

    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Query')).controller!.text, 'someartist');
    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Label')).controller!.text, 'someartist');

    await _tapCreate(tester);
    await tester.pumpAndSettle();

    expect(repository.searches, hasLength(1));
    expect(repository.searches.single.site, BunnySite.inkbunny);
    expect(repository.searches.single.query, 'someartist');
  });

  testWidgets('typing a raw pool query mirrors the fetched pool name into the label (M13.1)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.poolInfoById[12345] = const BunnyPoolInfo(id: 12345, name: 'Some Comic', postCount: 10);

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Query'), 'pool:12345');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Label')).controller!.text, 'Some Comic');
  });

  testWidgets('a raw pool query falls back to the literal text when the pool lookup fails (M13.1)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Query'), 'pool:99999');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Label')).controller!.text, 'pool:99999');
  });

  testWidgets('the pool-name fetch is skipped when initialLabel is already set (M13.1)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.poolInfoById[12345] = const BunnyPoolInfo(id: 12345, name: 'Some Comic', postCount: 10);

    await tester.pumpWidget(
      wrapWithLocalization(CreateSearchScreen(repository: repository, initialSite: BunnySite.e621, initialQuery: 'pool:12345', initialLabel: 'My Own Label')),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Label')).controller!.text, 'My Own Label');
  });

  testWidgets('"use default interval" starts checked and submits it with no further action (M30)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository()..defaultSyncIntervalHours = 24;

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Use default interval')).value, isTrue);
    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Sync interval (hours)')).enabled, isFalse);

    await tester.enterText(find.widgetWithText(TextFormField, 'Label'), 'Foxes');
    await tester.enterText(find.widgetWithText(TextFormField, 'Query'), 'fox');
    await _tapCreate(tester);
    await tester.pumpAndSettle();

    expect(repository.searches.single.usesDefaultInterval, isTrue);
  });

  testWidgets('disabling "use default interval" re-enables the interval field and submits a fixed one', (WidgetTester tester) async {
    final repository = FakeBunnyRepository()..defaultSyncIntervalHours = 24;

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SwitchListTile, 'Use default interval'));
    await tester.pumpAndSettle();

    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Sync interval (hours)')).enabled, isTrue);

    await tester.enterText(find.widgetWithText(TextFormField, 'Label'), 'Foxes');
    await tester.enterText(find.widgetWithText(TextFormField, 'Query'), 'fox');
    await tester.enterText(find.widgetWithText(TextFormField, 'Sync interval (hours)'), '12');
    await _tapCreate(tester);
    await tester.pumpAndSettle();

    expect(repository.searches.single.usesDefaultInterval, isFalse);
    expect(repository.searches.single.intervalHours, 12);
  });
}
