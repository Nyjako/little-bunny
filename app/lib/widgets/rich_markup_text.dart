import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../util/rich_markup.dart';

/// Renders a post/pool/wiki description (M50/M53) with `{{author}}`,
/// `[[title]]`, `thumb #<id>`, and bare URLs linkified inline. A segment
/// whose callback wasn't supplied (e.g. [onOpenThumbnail] outside a wiki
/// page) falls back to inert, plain-styled text rather than a dead link.
class RichMarkupText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final void Function(String authorName)? onOpenAuthor;
  final void Function(String title)? onOpenWiki;
  final void Function(int postId)? onOpenThumbnail;

  const RichMarkupText({super.key, required this.text, this.style, this.onOpenAuthor, this.onOpenWiki, this.onOpenThumbnail});

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final linkColor = Theme.of(context).colorScheme.primary;
    final linkStyle = (style ?? const TextStyle()).copyWith(color: linkColor, decoration: TextDecoration.underline);

    return Text.rich(
      TextSpan(
        style: style,
        children: parseRichMarkup(text).map((segment) {
          return switch (segment) {
            RichMarkupTextSegment(text: final text) => TextSpan(text: text),
            RichMarkupUrlSegment(url: final url) => TextSpan(text: url, style: linkStyle, recognizer: TapGestureRecognizer()..onTap = () => _launchUrl(url)),
            RichMarkupAuthorSegment(authorName: final authorName, matchedText: final matchedText) => onOpenAuthor == null
                ? TextSpan(text: matchedText)
                : TextSpan(text: matchedText, style: linkStyle, recognizer: TapGestureRecognizer()..onTap = () => onOpenAuthor!(authorName)),
            RichMarkupWikiSegment(title: final title, matchedText: final matchedText) => onOpenWiki == null
                ? TextSpan(text: matchedText)
                : TextSpan(text: matchedText, style: linkStyle, recognizer: TapGestureRecognizer()..onTap = () => onOpenWiki!(title)),
            RichMarkupThumbSegment(postId: final postId, matchedText: final matchedText) => onOpenThumbnail == null
                ? TextSpan(text: matchedText)
                : TextSpan(text: matchedText, style: linkStyle, recognizer: TapGestureRecognizer()..onTap = () => onOpenThumbnail!(postId)),
          };
        }).toList(),
      ),
    );
  }
}
