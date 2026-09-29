import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/screens/create_search_screen.dart';

import '../fakes/fake_bunny_repository.dart';
import '../fakes/test_app.dart';

void main() {
  testWidgets('validates required fields before submitting', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    await tester.pumpWidget(wrapWithLocalization(CreateSearchScreen(repository: repository)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('Required'), findsNWidgets(2));
    expect(repository.searches, isEmpty);
  });

  testWidgets('submitting a filled form creates the search and pops true', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    await tester.pumpWidget(wrapWithLocalization(CreateSearchScreen(repository: repository)));
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
  });

  testWidgets('typing a query word shows debounced tag suggestions for that word only', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.tagStats.addAll(const [BunnyTagStat(name: 'fox', count: 10), BunnyTagStat(name: 'wolf', count: 5)]);

    await tester.pumpWidget(wrapWithLocalization(CreateSearchScreen(repository: repository)));
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

  testWidgets('picking a site changes which site the search is created for', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    await tester.pumpWidget(wrapWithLocalization(CreateSearchScreen(repository: repository)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inkbunny'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Label'), 'Foxes');
    await tester.enterText(find.widgetWithText(TextFormField, 'Query'), 'fox');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(repository.searches.single.site, BunnySite.inkbunny);
  });
}
