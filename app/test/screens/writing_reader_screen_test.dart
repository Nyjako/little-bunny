import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/screens/writing_reader_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

BunnyDocRun _plain(String text) => BunnyDocRun(kind: BunnyDocRunKind.plain, text: text);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget wrap(List<BunnyDocBlock> blocks) => MaterialApp(home: WritingReaderScreen(postId: 1, title: 'A Short Story', blocks: blocks));

  testWidgets('renders the reader title and a plain paragraph', (tester) async {
    await tester.pumpWidget(wrap([BunnyDocBlock(kind: BunnyDocBlockKind.paragraph, runs: [_plain('Once upon a time.')])]));

    expect(find.text('A Short Story'), findsOneWidget);
    expect(find.textContaining('Once upon a time.'), findsOneWidget);
  });

  testWidgets('renders a heading and a list item distinctly from a paragraph', (tester) async {
    await tester.pumpWidget(
      wrap([
        BunnyDocBlock(kind: BunnyDocBlockKind.heading, headingLevel: 2, runs: [_plain('Chapter One')]),
        BunnyDocBlock(kind: BunnyDocBlockKind.listItem, runs: [_plain('first item')]),
        BunnyDocBlock(kind: BunnyDocBlockKind.paragraph, runs: [_plain('Body text.')]),
      ]),
    );

    expect(find.textContaining('Chapter One'), findsOneWidget);
    expect(find.textContaining('first item'), findsOneWidget);
    expect(find.textContaining('Body text.'), findsOneWidget);
    // The list item gets a bullet marker, distinguishing it visually from
    // the plain paragraph/heading blocks.
    expect(find.text('•'), findsOneWidget);
  });

  testWidgets('renders bold/italic/underline/url runs within one paragraph', (tester) async {
    await tester.pumpWidget(
      wrap([
        BunnyDocBlock(
          kind: BunnyDocBlockKind.paragraph,
          runs: [
            _plain('plain '),
            BunnyDocRun(kind: BunnyDocRunKind.bold, text: 'bold'),
            _plain(' '),
            BunnyDocRun(kind: BunnyDocRunKind.italic, text: 'italic'),
            _plain(' '),
            BunnyDocRun(kind: BunnyDocRunKind.underline, text: 'underline'),
            _plain(' '),
            BunnyDocRun(kind: BunnyDocRunKind.url, text: 'a link', url: 'https://example.com'),
          ],
        ),
      ]),
    );

    expect(find.textContaining('plain'), findsOneWidget);
    expect(find.textContaining('bold'), findsOneWidget);
    expect(find.textContaining('italic'), findsOneWidget);
    expect(find.textContaining('underline'), findsOneWidget);
    expect(find.textContaining('a link'), findsOneWidget);
  });

  testWidgets('renders an empty block list without crashing', (tester) async {
    await tester.pumpWidget(wrap(const []));

    expect(find.text('A Short Story'), findsOneWidget);
  });
}
