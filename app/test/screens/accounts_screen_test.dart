import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/screens/accounts_screen.dart';
import 'package:little_bunny/services/download_manager.dart';
import 'package:little_bunny/services/download_queue_service.dart';
import 'package:little_bunny/settings/display_settings_store.dart';
import 'package:little_bunny/settings/download_settings_store.dart';

import '../fakes/fake_bunny_repository.dart';
import '../fakes/test_app.dart';

Widget _wrap(FakeBunnyRepository repository) => wrapWithLocalization(
  AccountsScreen(
    repository: repository,
    displaySettingsStore: const DisplaySettingsStore(),
    downloadSettingsStore: const DownloadSettingsStore(),
    downloadQueueService: DownloadQueueService(downloadManager: const DownloadManager(), downloadSettingsStore: const DownloadSettingsStore()),
  ),
);

void main() {
  testWidgets('shows "Not connected" for both sites when nothing is configured', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(FakeBunnyRepository()));
    await tester.pumpAndSettle();

    expect(find.text('e621'), findsOneWidget);
    expect(find.text('inkbunny'), findsOneWidget);
    expect(find.text('Not connected'), findsNWidgets(2));
  });

  testWidgets('shows the username and a remove action for a configured account', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    await repository.setAccount(BunnySite.e621, 'someuser', 'somesecret');

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    expect(find.text('Logged in as someuser · 0 favorites'), findsOneWidget);
    expect(find.byIcon(Icons.delete), findsOneWidget);
  });

  group('favorites count + sync (M30)', () {
    testWidgets('auto-creates a favorites search per configured account and shows its count', (WidgetTester tester) async {
      final repository = FakeBunnyRepository();
      await repository.setAccount(BunnySite.e621, 'someuser', 'apikey');
      await repository.setAccount(BunnySite.inkbunny, 'someinkbunnyuser', 'password');

      await tester.pumpWidget(_wrap(repository));
      await tester.pumpAndSettle();

      expect(repository.searches.where((s) => s.isFavorites && s.site == BunnySite.e621).single.query, 'fav:someuser');
      expect(repository.searches.where((s) => s.isFavorites && s.site == BunnySite.inkbunny).single.query, 'favorited_by:me');
      expect(find.text('Logged in as someuser · 0 favorites'), findsOneWidget);
      expect(find.text('Logged in as someinkbunnyuser · 0 favorites'), findsOneWidget);
      // No per-search editing/pinning UI for the sentinel search -- just the
      // count (above) and a sync button (below).
      expect(find.byIcon(Icons.sync), findsNWidgets(2));
    });

    testWidgets('tapping sync triggers syncSearch and refreshes the shown count', (WidgetTester tester) async {
      final repository = FakeBunnyRepository();
      await repository.setAccount(BunnySite.e621, 'someuser', 'apikey');

      await tester.pumpWidget(_wrap(repository));
      await tester.pumpAndSettle();

      final favoritesSearch = repository.searches.where((s) => s.isFavorites).single;
      repository.syncSearchNewPosts[favoritesSearch.id] = [
        BunnyPost(
          id: 1,
          site: BunnySite.e621,
          externalId: 1,
          score: 0,
          favCount: 0,
          commentCount: 0,
          width: 1,
          height: 1,
          cachedAt: '2024-01-01T00:00:00Z',
          isSeen: false,
          isFavorited: false,
        ),
      ];

      await tester.tap(find.byIcon(Icons.sync));
      await tester.pumpAndSettle();

      expect(repository.syncSearchCalls, contains(favoritesSearch.id));
      expect(find.text('Logged in as someuser · 1 favorites'), findsOneWidget);
    });
  });

  testWidgets('tapping remove then confirming deletes the account', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    await repository.setAccount(BunnySite.e621, 'someuser', 'somesecret');

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete));
    await tester.pumpAndSettle();
    expect(find.text('Remove account?'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(repository.accounts.containsKey(BunnySite.e621), isFalse);
    expect(find.text('Not connected'), findsNWidgets(2));
  });

  testWidgets('tapping cancel in the remove dialog keeps the account', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    await repository.setAccount(BunnySite.e621, 'someuser', 'somesecret');

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repository.accounts.containsKey(BunnySite.e621), isTrue);
  });

  testWidgets('tapping an unconfigured site opens its login form', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(FakeBunnyRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('e621'));
    await tester.pumpAndSettle();

    expect(find.text('Log in to e621'), findsOneWidget);
  });

  group('view my favorites (M10.3)', () {
    testWidgets('the heart icon is absent for an unconfigured site', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(FakeBunnyRepository()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.favorite), findsNothing);
    });

    testWidgets('tapping the e621 heart opens a fav:username TagBrowseScreen', (WidgetTester tester) async {
      final repository = FakeBunnyRepository();
      await repository.setAccount(BunnySite.e621, 'someuser', 'somesecret');
      repository.previewSearchResults['e621:fav:someuser:1'] = [];

      await tester.pumpWidget(_wrap(repository));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.favorite));
      await tester.pumpAndSettle();

      expect(find.text('My favorites'), findsOneWidget);
      expect(repository.previewSearchCalls, contains((BunnySite.e621, 'fav:someuser', 1)));
    });

    testWidgets('tapping the Inkbunny heart opens TagBrowseScreen via myInkbunnyFavorites', (WidgetTester tester) async {
      final repository = FakeBunnyRepository();
      await repository.setAccount(BunnySite.inkbunny, 'someuser', 'somesecret');

      await tester.pumpWidget(_wrap(repository));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.favorite));
      await tester.pumpAndSettle();

      expect(find.text('My favorites'), findsOneWidget);
      expect(repository.myInkbunnyFavoritesCalls, [1]);
      expect(repository.previewSearchCalls, isEmpty);
    });
  });
}
