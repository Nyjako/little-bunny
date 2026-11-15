import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../util/local_media_bytes.dart';

/// Renders an already-downloaded image sitting at [path] -- a plain
/// filesystem path or an Android SAF `content://` uri, same two shapes
/// [DownloadManager.localFilePathFor]/[readLocalMediaBytes] already handle.
/// Shared by [PostMediaPage] (the slideshow) and `PostDetailScreen` (M78 --
/// view an already-downloaded post from disk instead of refetching it over
/// the network) so both read a local file exactly the same way.
Widget buildLocalImageContent(String path, {BoxFit fit = BoxFit.contain}) => path.startsWith('content://') ? _LocalContentUriImage(path: path, fit: fit) : Image.file(File(path), fit: fit);

/// Reads a `content://` SAF uri's bytes before handing them to [Image.memory]
/// -- [Image.file] (the plain-path case above) can't open one directly.
class _LocalContentUriImage extends StatefulWidget {
  final String path;
  final BoxFit fit;

  const _LocalContentUriImage({required this.path, required this.fit});

  @override
  State<_LocalContentUriImage> createState() => _LocalContentUriImageState();
}

class _LocalContentUriImageState extends State<_LocalContentUriImage> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await readLocalMediaBytes(widget.path);
      if (mounted) {
        setState(() => _bytes = bytes);
      }
    } catch (_) {
      // Best-effort, same tolerance as GifPlayer's own local-read failure.
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return bytes == null ? const Center(child: CircularProgressIndicator()) : Image.memory(bytes, fit: widget.fit);
  }
}
