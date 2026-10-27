import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/screens/custom_search_screen.dart';
import 'package:little_bunny/screens/tag_browse_screen.dart';
import 'package:little_bunny/services/download_manager.dart';
import 'package:little_bunny/services/download_queue_service.dart';
import 'package:little_bunny/settings/display_settings_store.dart';
import 'package:little_bunny/settings/download_settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_bunny_repository.dart';
import '../fakes/test_app.dart';

DownloadQueueService _downloadQueueService() => DownloadQueueService(downloadManager: const DownloadManager(), downloadSettingsStore: const DownloadSettingsStore());

Widget _wrap(FakeBunnyRepository repository) => wrapWithLocalization(
  CustomSearchScreen(
    repository: repository,
    displaySettingsStore: const DisplaySettingsStore(),
    downloadSettingsStore: const DownloadSettingsStore(),
    downloadQueueService: _downloadQueueService(),
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('the Search button is disabled for an empty query', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Search')).onPressed, isNull);
  });

  testWidgets('typing a query enables the Search button, which pushes a live preview', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.previewSearchResults['e621:fox:1'] = [];

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Query'), 'fox');
    await tester.pumpAndSettle();

    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Search')).onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Search'));
    await tester.pumpAndSettle();

    expect(find.byType(TagBrowseScreen), findsOneWidget);
    expect(repository.previewSearchCalls, contains((BunnySite.e621, 'fox', 1)));
  });

  testWidgets('switching site pushes the preview against Inkbunny instead', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.previewSearchResults['inkbunny:fox:1'] = [];

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inkbunny'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Query'), 'fox');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Search'));
    await tester.pumpAndSettle();

    expect(repository.previewSearchCalls, contains((BunnySite.inkbunny, 'fox', 1)));
  });

  testWidgets('autocomplete strips and reattaches a leading - prefix (M9.6.7 pattern)', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.tagStats.addAll(const [BunnyTagStat(name: 'dogsled', count: 7)]);

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Query'), 'cat -dogsl');
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('dogsled (7)'), findsOneWidget);

    await tester.tap(find.text('dogsled (7)'));
    await tester.pump();

    final field = tester.widget<TextField>(find.widgetWithText(TextField, 'Query'));
    expect(field.controller!.text, 'cat -dogsled ');
  });
}
