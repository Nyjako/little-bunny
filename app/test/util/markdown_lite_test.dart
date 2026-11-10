import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/util/markdown_lite.dart';

void main() {
  test('parses headings, a bullet list, and a trailing paragraph with bold text', () {
    const text = '''
## What's Changed
- Fixed a bug with **downloads**
- Added dark mode

**Full Changelog**: https://github.com/Nyjako/little-bunny/compare/build-1...build-2
''';

    final blocks = parseReleaseNotes(text);

    expect(blocks, [
      isA<ReleaseNotesHeading>().having((h) => h.level, 'level', 2).having((h) => h.text, 'text', "What's Changed"),
      isA<ReleaseNotesBullet>().having((b) => b.text, 'text', 'Fixed a bug with **downloads**'),
      isA<ReleaseNotesBullet>().having((b) => b.text, 'text', 'Added dark mode'),
      isA<ReleaseNotesParagraph>().having((p) => p.text, 'text', '**Full Changelog**: https://github.com/Nyjako/little-bunny/compare/build-1...build-2'),
    ]);
  });

  test('recognizes # and ### headings alongside * bullets', () {
    final blocks = parseReleaseNotes('# Big heading\n* bullet one\n### Small heading');

    expect(blocks, [
      isA<ReleaseNotesHeading>().having((h) => h.level, 'level', 1),
      isA<ReleaseNotesBullet>().having((b) => b.text, 'text', 'bullet one'),
      isA<ReleaseNotesHeading>().having((h) => h.level, 'level', 3),
    ]);
  });

  test('blank lines are skipped, not turned into empty blocks', () {
    final blocks = parseReleaseNotes('First paragraph\n\n\nSecond paragraph');

    expect(blocks, [isA<ReleaseNotesParagraph>().having((p) => p.text, 'text', 'First paragraph'), isA<ReleaseNotesParagraph>().having((p) => p.text, 'text', 'Second paragraph')]);
  });

  test('a line starting with "**" is not mistaken for a bullet', () {
    final blocks = parseReleaseNotes('**Full Changelog**: see below');

    expect(blocks, [isA<ReleaseNotesParagraph>()]);
  });
}
