import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:little_bunny/screens/changelog_screen.dart';
import 'package:little_bunny/services/update_check_service.dart';

import '../fakes/test_app.dart';

void main() {
  testWidgets('renders multiple releases, newest first, with headings and bullets formatted', (WidgetTester tester) async {
    final checkService = UpdateCheckService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode([
            {'tag_name': 'build-42', 'body': '## Fixes\n- Fixed a crash', 'published_at': '2026-02-01T00:00:00Z'},
            {'tag_name': 'build-41', 'body': 'Minor tweaks', 'published_at': '2026-01-01T00:00:00Z'},
          ]),
          200,
        ),
      ),
    );

    await tester.pumpWidget(wrapWithLocalization(ChangelogScreen(checkService: checkService)));
    await tester.pumpAndSettle();

    expect(find.text('build-42'), findsOneWidget);
    expect(find.text('build-41'), findsOneWidget);
    expect(find.text('Fixes'), findsOneWidget);
    expect(find.text('Fixed a crash'), findsOneWidget);
    expect(find.text('Minor tweaks'), findsOneWidget);
    // The raw markdown syntax itself should never show up as literal text.
    expect(find.textContaining('##'), findsNothing);
  });

  testWidgets('shows an empty state when there is no release history', (WidgetTester tester) async {
    final checkService = UpdateCheckService(client: MockClient((_) async => http.Response(jsonEncode([]), 200)));

    await tester.pumpWidget(wrapWithLocalization(ChangelogScreen(checkService: checkService)));
    await tester.pumpAndSettle();

    expect(find.text('No release history available.'), findsOneWidget);
  });

  testWidgets('shows an empty state when the fetch fails (fetchRecentReleases swallows errors)', (WidgetTester tester) async {
    final checkService = UpdateCheckService(client: MockClient((_) async => http.Response('', 500)));

    await tester.pumpWidget(wrapWithLocalization(ChangelogScreen(checkService: checkService)));
    await tester.pumpAndSettle();

    expect(find.text('No release history available.'), findsOneWidget);
  });
}
