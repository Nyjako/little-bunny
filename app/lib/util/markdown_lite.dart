/// Parses GitHub-release-notes-shaped markdown -- exactly what GitHub's
/// `generate_release_notes: true` emits: `#`/`##`/`###` headings, `-`/`*`
/// bullets, `**bold**`, and bare/markdown-style links -- into a short list
/// of renderable blocks. Deliberately not a general CommonMark parser; see
/// [ReleaseNotesText] (widgets/release_notes_text.dart) for the widget that
/// actually renders these.
library;

sealed class ReleaseNotesBlock {
  const ReleaseNotesBlock();
}

class ReleaseNotesHeading extends ReleaseNotesBlock {
  final int level; // 1-3, from the number of leading '#'s
  final String text;
  const ReleaseNotesHeading(this.level, this.text);
}

class ReleaseNotesBullet extends ReleaseNotesBlock {
  final String text;
  const ReleaseNotesBullet(this.text);
}

class ReleaseNotesParagraph extends ReleaseNotesBlock {
  final String text;
  const ReleaseNotesParagraph(this.text);
}

final _headingPattern = RegExp(r'^(#{1,3})\s+(.*)$');
final _bulletPattern = RegExp(r'^[-*]\s+(.*)$');

/// Blank lines are block separators only -- they never produce their own
/// (empty) block.
List<ReleaseNotesBlock> parseReleaseNotes(String text) {
  final blocks = <ReleaseNotesBlock>[];
  for (final rawLine in text.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }
    final headingMatch = _headingPattern.firstMatch(line);
    if (headingMatch != null) {
      blocks.add(ReleaseNotesHeading(headingMatch.group(1)!.length, headingMatch.group(2)!.trim()));
      continue;
    }
    final bulletMatch = _bulletPattern.firstMatch(line);
    if (bulletMatch != null) {
      blocks.add(ReleaseNotesBullet(bulletMatch.group(1)!.trim()));
      continue;
    }
    blocks.add(ReleaseNotesParagraph(line));
  }
  return blocks;
}
