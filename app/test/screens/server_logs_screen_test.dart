import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:little_bunny/repository/http_bunny_repository.dart';
import 'package:little_bunny/screens/server_logs_screen.dart';

import '../fakes/test_app.dart';

void main() {
  Widget wrap(http.Client client) => wrapWithLocalization(
    ServerLogsScreen(repository: HttpBunnyRepository.withClient(baseUrl: Uri.parse('https://bunny.example:9443'), bearerToken: 'test-token', client: client)),
  );

  testWidgets('shows fetched log lines', (WidgetTester tester) async {
    final client = MockClient((_) async => http.Response(jsonEncode(['first line', 'second line']), 200));

    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();

    expect(find.text('first line'), findsOneWidget);
    expect(find.text('second line'), findsOneWidget);
  });

  testWidgets('shows the empty state when there are no log lines', (WidgetTester tester) async {
    final client = MockClient((_) async => http.Response(jsonEncode([]), 200));

    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();

    expect(find.text('No log lines yet.'), findsOneWidget);
  });

  testWidgets('shows an error state when the fetch fails', (WidgetTester tester) async {
    final client = MockClient((_) async => http.Response(jsonEncode({'error': 'missing or invalid bearer token'}), 401));

    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();

    expect(find.textContaining('missing or invalid bearer token'), findsOneWidget);
  });

  testWidgets('refresh action re-fetches', (WidgetTester tester) async {
    var callCount = 0;
    final client = MockClient((_) async {
      callCount++;
      return http.Response(jsonEncode(['line $callCount']), 200);
    });

    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();
    expect(find.text('line 1'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();

    expect(find.text('line 2'), findsOneWidget);
  });
}
