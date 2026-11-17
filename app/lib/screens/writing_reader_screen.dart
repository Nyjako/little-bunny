import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../repository/bunny_models.dart';
import '../settings/writing_position_store.dart';

/// Full, parsed, paginated-by-scrolling reading view for an Inkbunny
/// Writing-Document post's story text -- distinct from the short inline
/// preview `PostDetailScreen` already renders via `RichMarkupText` (plain,
/// unparsed `post.writing`): this renders the already-parsed
/// [BunnyDocBlock] list (from `BunnyRepository.getWritingDoc` for a live
/// post, or the top-level `readWritingEpub` for a downloaded one) with
/// real paragraph/heading/list structure and bold/italic/underline/link
/// styling, and remembers where the user left off via [WritingPositionStore]
/// so reopening a long story resumes near the same spot. That resume
/// behavior is scoped to this screen only -- the inline preview on
/// `PostDetailScreen` is unaffected.
class WritingReaderScreen extends StatefulWidget {
  final int postId;
  final String title;
  final List<BunnyDocBlock> blocks;
  final WritingPositionStore positionStore;

  const WritingReaderScreen({super.key, required this.postId, required this.title, required this.blocks, this.positionStore = const WritingPositionStore()});

  @override
  State<WritingReaderScreen> createState() => _WritingReaderScreenState();
}

class _WritingReaderScreenState extends State<WritingReaderScreen> {
  final ScrollController _scrollController = ScrollController();
  Timer? _saveDebounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _restorePosition());
  }

  Future<void> _restorePosition() async {
    final fraction = await widget.positionStore.getPosition(widget.postId);
    if (fraction == null || !mounted || !_scrollController.hasClients) {
      return;
    }
    final maxExtent = _scrollController.position.maxScrollExtent;
    if (maxExtent > 0) {
      _scrollController.jumpTo(fraction * maxExtent);
    }
  }

  void _onScroll() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 2), _savePosition);
  }

  void _savePosition() {
    if (!_scrollController.hasClients) {
      return;
    }
    final maxExtent = _scrollController.position.maxScrollExtent;
    final fraction = maxExtent > 0 ? (_scrollController.offset / maxExtent).clamp(0.0, 1.0) : 0.0;
    widget.positionStore.savePosition(widget.postId, fraction);
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _savePosition();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  InlineSpan _runSpan(BuildContext context, BunnyDocRun run) {
    switch (run.kind) {
      case BunnyDocRunKind.bold:
        return TextSpan(text: run.text, style: const TextStyle(fontWeight: FontWeight.bold));
      case BunnyDocRunKind.italic:
        return TextSpan(text: run.text, style: const TextStyle(fontStyle: FontStyle.italic));
      case BunnyDocRunKind.underline:
        return TextSpan(text: run.text, style: const TextStyle(decoration: TextDecoration.underline));
      case BunnyDocRunKind.url:
        final url = run.url;
        final linkStyle = TextStyle(color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline);
        return TextSpan(text: run.text, style: linkStyle, recognizer: url == null ? null : (TapGestureRecognizer()..onTap = () => _launchUrl(url)));
      case BunnyDocRunKind.plain:
        return TextSpan(text: run.text);
    }
  }

  Widget _blockWidget(BuildContext context, BunnyDocBlock block) {
    final theme = Theme.of(context);
    final spans = block.runs.map((run) => _runSpan(context, run)).toList();

    switch (block.kind) {
      case BunnyDocBlockKind.heading:
        final headingStyle = switch (block.headingLevel) {
          1 => theme.textTheme.headlineMedium,
          2 => theme.textTheme.headlineSmall,
          3 => theme.textTheme.titleLarge,
          4 => theme.textTheme.titleMedium,
          _ => theme.textTheme.titleSmall,
        };
        return Padding(padding: const EdgeInsets.only(top: 16, bottom: 8), child: Text.rich(TextSpan(style: headingStyle, children: spans)));
      case BunnyDocBlockKind.listItem:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(padding: EdgeInsets.only(right: 8), child: Text('•')),
              Expanded(child: Text.rich(TextSpan(style: theme.textTheme.bodyLarge, children: spans))),
            ],
          ),
        );
      case BunnyDocBlockKind.paragraph:
        return Padding(padding: const EdgeInsets.only(bottom: 16), child: Text.rich(TextSpan(style: theme.textTheme.bodyLarge?.copyWith(height: 1.5), children: spans)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(20),
        itemCount: widget.blocks.length,
        itemBuilder: (context, index) => _blockWidget(context, widget.blocks[index]),
      ),
    );
  }
}
