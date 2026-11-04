import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:little_bunny/widgets/text_document_viewer.dart';

void main() {
  testWidgets('renders the fetched text, sending the given headers', (WidgetTester tester) async {
    Map<String, String>? sentHeaders;
    final client = MockClient((request) async {
      sentHeaders = request.headers;
      return http.Response('hello from the document', 200);
    });

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: TextDocumentViewer(url: 'https://example.invalid/story.txt', httpHeaders: const {'User-Agent': 'test-agent'}, client: client))),
    );
    await tester.pumpAndSettle();

    expect(find.text('hello from the document'), findsOneWidget);
    expect(sentHeaders?['User-Agent'], 'test-agent');
  });

  testWidgets('shows an error instead of crashing on a non-200 response', (WidgetTester tester) async {
    final client = MockClient((_) async => http.Response('not found', 404));

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TextDocumentViewer(url: 'https://example.invalid/missing.txt', client: client))));
    await tester.pumpAndSettle();

    expect(find.textContaining('404'), findsOneWidget);
  });
}
