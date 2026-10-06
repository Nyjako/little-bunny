import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/screens/create_search_screen.dart';
import 'package:little_bunny/settings/sync_settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_bunny_repository.dart';
import '../fakes/test_app.dart';

Widget _wrap(FakeBunnyRepository repository) => wrapWithLocalization(CreateSearchScreen(repository: repository, syncSettingsStore: const SyncSettingsStore()));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('validates required fields before submitting', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create'));
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
    await tester.tap(find.text('Create'));
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
    await tester.tap(find.text('Create'));
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
    await tester.tap(find.text('Create'));
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
    repository.tagStats.addAll(const [BunnyTagStat(name: 'fox', count: 10), BunnyTagStat(name: 'wolf', count: 5)]);

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Query'), 'canine fo');
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('fox (10)'), findsOneWidget);
    expect(find.text('wolf (5)'), findsNothing);

    await tester.tap(find.text('fox (10)'));
    await tester.pump();

    final field = tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Query'));
    expect(field.controller!.text, 'canine fox ');
  });

  testWidgets('negated tags still autocomplete and keep their - prefix (M9.6.7)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.tagStats.addAll(const [BunnyTagStat(name: 'dog', count: 7)]);

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Query'), 'cat -do');
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('dog (7)'), findsOneWidget);

    await tester.tap(find.text('dog (7)'));
    await tester.pump();

    final field = tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Query'));
    expect(field.controller!.text, 'cat -dog ');
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
    await tester.tap(find.text('Create'));
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

  testWidgets('interval field pre-fills from the stored default', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'default_sync_interval_hours': 12});
    final repository = FakeBunnyRepository();

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Sync interval (hours)')).controller!.text, '12');
  });

  testWidgets('initialSite/initialQuery pre-fill the site and query (and mirror into the label)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();

    await tester.pumpWidget(wrapWithLocalization(CreateSearchScreen(repository: repository, syncSettingsStore: const SyncSettingsStore(), initialSite: BunnySite.inkbunny, initialQuery: 'someartist')));
    await tester.pumpAndSettle();

    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Query')).controller!.text, 'someartist');
    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Label')).controller!.text, 'someartist');

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(repository.searches, hasLength(1));
    expect(repository.searches.single.site, BunnySite.inkbunny);
    expect(repository.searches.single.query, 'someartist');
  });
}
