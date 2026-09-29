import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/bunny_repository_scope.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/screens/searches_screen.dart';
import 'package:little_bunny/settings/app_lock_service.dart';
import 'package:little_bunny/settings/theme_settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_bunny_repository.dart';
import '../fakes/fake_secret_store.dart';
import '../fakes/test_app.dart';

Widget _wrap(FakeBunnyRepository repository) => wrapWithLocalization(
  BunnyRepositoryScope(
    repository: repository,
    child: SearchesScreen(lockService: AppLockService(FakeSecretStore()), themeSettingsStore: const ThemeSettingsStore(), onThemeModeChanged: (_) {}),
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows the empty state when there are no saved searches', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(FakeBunnyRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No saved searches yet. Tap + to add one.'), findsOneWidget);
  });

  testWidgets('lists saved searches with their site and interval', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    await repository.createSearch(BunnySite.e621, 'Foxes', 'fox', intervalHours: 6);

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    expect(find.text('Foxes'), findsOneWidget);
    expect(find.text('e621 • every 6h'), findsOneWidget);
  });

  testWidgets('tapping remove then confirming deletes the search', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    await repository.createSearch(BunnySite.e621, 'Foxes', 'fox');

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete));
    await tester.pumpAndSettle();
    expect(find.text('Remove search?'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(repository.searches, isEmpty);
    expect(find.text('No saved searches yet. Tap + to add one.'), findsOneWidget);
  });

  testWidgets('tapping the accounts icon opens AccountsScreen', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(FakeBunnyRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();

    expect(find.text('Accounts'), findsOneWidget);
  });

  testWidgets('tapping the settings icon opens SettingsScreen', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(FakeBunnyRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('tapping the FAB opens CreateSearchScreen and refreshes on success', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('New search'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Label'), 'Foxes');
    await tester.enterText(find.widgetWithText(TextFormField, 'Query'), 'fox');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('Foxes'), findsOneWidget);
    expect(repository.searches, hasLength(1));
  });
}
