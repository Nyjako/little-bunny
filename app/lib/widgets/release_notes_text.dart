import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../util/markdown_lite.dart';

/// Renders a GitHub-release-notes-shaped markdown string (see
/// [parseReleaseNotes]'s doc comment for exactly what that covers) with
/// real headings/bullets/bold, plus clickable bare URLs -- shared by the
/// update dialog and [ChangelogScreen] so both render identically from one
/// implementation.
class ReleaseNotesText extends StatefulWidget {
  final String text;

  const ReleaseNotesText({super.key, required this.text});

  @override
  State<ReleaseNotesText> createState() => _ReleaseNotesTextState();
}

class _ReleaseNotesTextState extends State<ReleaseNotesText> {
  /// GitHub's auto-generated release notes (release.yml's
  /// `generate_release_notes: true`) have bare PR/compare URLs, not
  /// markdown links -- these recognizers make those URLs tappable. Built
  /// once per block rather than per-build, since recreating a
  /// [TapGestureRecognizer] on every rebuild without disposing the old one
  /// leaks them.
  final List<TapGestureRecognizer> _linkRecognizers = [];
  static final _inlinePattern = RegExp(r'\*\*(.+?)\*\*|(https?://\S+)');

  @override
  void dispose() {
    for (final recognizer in _linkRecognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  List<InlineSpan> _inlineSpans(BuildContext context, String text) {
    final linkStyle = TextStyle(color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline);
    final spans = <InlineSpan>[];
    var last = 0;
    for (final match in _inlinePattern.allMatches(text)) {
      if (match.start > last) {
        spans.add(TextSpan(text: text.substring(last, match.start)));
      }
      final boldText = match.group(1);
      final url = match.group(2);
      if (boldText != null) {
        spans.add(TextSpan(text: boldText, style: const TextStyle(fontWeight: FontWeight.bold)));
      } else if (url != null) {
        final recognizer = TapGestureRecognizer()..onTap = () => _openLink(url);
        _linkRecognizers.add(recognizer);
        spans.add(TextSpan(text: url, style: linkStyle, recognizer: recognizer));
      }
      last = match.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }
    return spans;
  }

  Widget _blockWidget(BuildContext context, ReleaseNotesBlock block) {
    final theme = Theme.of(context);
    switch (block) {
      case ReleaseNotesHeading(level: final level, text: final text):
        final style = switch (level) {
          1 => theme.textTheme.titleLarge,
          2 => theme.textTheme.titleMedium,
          _ => theme.textTheme.titleSmall,
        };
        return SelectableText.rich(TextSpan(style: style, children: _inlineSpans(context, text)));
      case ReleaseNotesBullet(text: final text):
        return Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [const Text('•  '), Expanded(child: SelectableText.rich(TextSpan(children: _inlineSpans(context, text))))],
          ),
        );
      case ReleaseNotesParagraph(text: final text):
        return SelectableText.rich(TextSpan(children: _inlineSpans(context, text)));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Not pre-parsed/cached in initState -- parseReleaseNotes is a cheap,
    // pure line-scan, and widget.text never changes after construction (a
    // new release notes string means a new ReleaseNotesText instance, not
    // an update to this one).
    final blocks = parseReleaseNotes(widget.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [for (final block in blocks) Padding(padding: const EdgeInsets.only(bottom: 8), child: _blockWidget(context, block))],
    );
  }
}
