import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Fetches and renders a plain-text file inline (Inkbunny "Writing -
/// Document" submissions, M28 submission-type coverage follow-up) --
/// `PostDetailScreen` only reaches for this when the extension is a known
/// text type (`isTextDocumentExt`); anything else (.pdf/.doc/etc.) stays on
/// the generic "unsupported format" fallback with an "open externally" link
/// instead, since those aren't plain UTF-8 text this widget could decode.
/// [httpHeaders] matches every other network-fetched media widget on this
/// screen (`AudioPlayerWidget`/`GifPlayer`) -- Inkbunny's CDN 403s a bare
/// request with no `User-Agent`/`Referer`.
class TextDocumentViewer extends StatefulWidget {
  final String url;
  final Map<String, String>? httpHeaders;
  final http.Client? client;

  const TextDocumentViewer({super.key, required this.url, this.httpHeaders, this.client});

  @override
  State<TextDocumentViewer> createState() => _TextDocumentViewerState();
}

class _TextDocumentViewerState extends State<TextDocumentViewer> {
  late final Future<String> _textFuture;

  @override
  void initState() {
    super.initState();
    _textFuture = _fetch();
  }

  Future<String> _fetch() async {
    final client = widget.client ?? http.Client();
    try {
      final response = await client.get(Uri.parse(widget.url), headers: widget.httpHeaders ?? const {});
      if (response.statusCode != 200) {
        throw http.ClientException('HTTP ${response.statusCode}');
      }
      return response.body;
    } finally {
      if (widget.client == null) {
        client.close();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _textFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(padding: const EdgeInsets.all(16), child: Center(child: Text('${snapshot.error}')));
        }
        if (!snapshot.hasData) {
          return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
        }
        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 400),
          child: SingleChildScrollView(padding: const EdgeInsets.all(12), child: Text(snapshot.data!, style: const TextStyle(fontFamily: 'monospace'))),
        );
      },
    );
  }
}
