import 'dart:io';
import 'dart:typed_data';

import 'package:saf_stream/saf_stream.dart';

/// Reads raw bytes from a local media path that's either a plain filesystem
/// path or an Android SAF `content://` uri -- exactly what
/// `DownloadManager.localFilePathFor`/`batchLocalFilePathFor` return once the
/// user's chosen destination folder requires SAF (M51 v2's slideshow
/// playback is the first feature to ever read a downloaded file back for
/// display, rather than just writing one). `dart:io`'s `File` has no
/// understanding of a `content://` uri at all -- opening/reading one as a
/// plain `File` silently fails (caught by every caller's own best-effort
/// handling), which is why a slideshow's image/gif/video all rendered
/// nothing (a black screen) on Android.
Future<Uint8List> readLocalMediaBytes(String path) {
  return path.startsWith('content://') ? SafStream().readFileBytes(path) : File(path).readAsBytes();
}
