import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:little_bunny/repository/http_bunny_repository.dart';
import 'package:little_bunny/screens/task_queue_screen.dart';

import '../fakes/test_app.dart';

void main() {
  Widget wrap(http.Client client) => wrapWithLocalization(
    TaskQueueScreen(repository: HttpBunnyRepository.withClient(baseUrl: Uri.parse('https://bunny.example:9443'), bearerToken: 'test-token', client: client)),
  );

  String taskJson({required String label, String priority = 'high', String status = 'pending'}) =>
      jsonEncode({'id': 1, 'type': 'sync_search', 'priority': priority, 'status': status, 'label': label, 'enqueued_at': '2026-01-01T00:00:00Z'});

  String historyJson({required String label, String priority = 'high', bool succeeded = true, String finishedAt = '2026-01-01T00:00:00Z'}) =>
      jsonEncode({'id': 1, 'type': 'sync_search', 'priority': priority, 'label': label, 'enqueued_at': '2026-01-01T00:00:00Z', 'finished_at': finishedAt, 'succeeded': succeeded});

  String tasksResponse({List<String> tasks = const [], List<String> history = const []}) => '{"tasks":[${tasks.join(',')}],"history":[${history.join(',')}]}';

  /// Every test here starts a Timer.periodic (TaskQueueScreen's poll loop)
  /// that flutter_test refuses to let outlive the test -- replacing the
  /// tree with an empty widget disposes it (and cancels the timer) before
  /// the test ends, same cleanup every such test needs.
  Future<void> disposeScreen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets('shows fetched tasks with their priority and status', (WidgetTester tester) async {
    final client = MockClient((_) async => http.Response(tasksResponse(tasks: [taskJson(label: "Sync: wolves", priority: "high", status: "running")]), 200));

    await tester.pumpWidget(wrap(client));
    // Not pumpAndSettle -- a "running" task renders an indeterminate
    // CircularProgressIndicator (by design, see TaskQueueScreen.build),
    // which animates forever and pumpAndSettle treats as "never settles".
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(find.text('Sync: wolves'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);

    await disposeScreen(tester);
  });

  testWidgets('shows the empty state when nothing is queued and nothing has finished', (WidgetTester tester) async {
    final client = MockClient((_) async => http.Response(tasksResponse(), 200));

    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();

    expect(find.text('Nothing queued right now.'), findsOneWidget);

    await disposeScreen(tester);
  });

  testWidgets('shows an error state when the fetch fails', (WidgetTester tester) async {
    final client = MockClient((_) async => http.Response(jsonEncode({'error': 'missing or invalid bearer token'}), 401));

    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();

    expect(find.textContaining('missing or invalid bearer token'), findsOneWidget);

    await disposeScreen(tester);
  });

  testWidgets('polls for updated tasks while the screen is open', (WidgetTester tester) async {
    // Each refresh makes two requests (getTasks then getTaskHistory,
    // against the same GET /tasks endpoint) -- both calls within one
    // refresh must see the same poll number.
    var requestCount = 0;
    final client = MockClient((_) async {
      final pollNumber = (requestCount ~/ 2) + 1;
      requestCount++;
      return http.Response(tasksResponse(tasks: [taskJson(label: "poll $pollNumber")]), 200);
    });

    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();
    expect(find.text('poll 1'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('poll 2'), findsOneWidget);

    await disposeScreen(tester);
  });

  testWidgets('shows a "Recent" section below the live list with succeeded/failed history entries', (WidgetTester tester) async {
    final client = MockClient(
      (_) async => http.Response(
        tasksResponse(
          tasks: [taskJson(label: "Sync: wolves", status: "running")],
          history: [historyJson(label: "Sync: foxes", succeeded: true), historyJson(label: "Build tag-stats report", succeeded: false)],
        ),
        200,
      ),
    );

    await tester.pumpWidget(wrap(client));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(find.text('Sync: wolves'), findsOneWidget);
    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('Sync: foxes'), findsOneWidget);
    expect(find.text('Build tag-stats report'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);

    await disposeScreen(tester);
  });

  testWidgets('hides the "Recent" section entirely when there is no history', (WidgetTester tester) async {
    final client = MockClient((_) async => http.Response(tasksResponse(tasks: [taskJson(label: "Sync: wolves", status: "running")]), 200));

    await tester.pumpWidget(wrap(client));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(find.text('Sync: wolves'), findsOneWidget);
    expect(find.text('Recent'), findsNothing);

    await disposeScreen(tester);
  });
}
