import 'dart:typed_data';

import 'package:saf_stream/saf_stream_platform_interface.dart';
import 'package:saf_util/saf_util_platform_interface.dart';

/// Fakes for `saf_util`/`saf_stream`'s platform interfaces -- there's no real
/// platform channel implementation for either under `flutter test` (both are
/// Android-only plugins), so anything under test that calls through `SafUtil()`/
/// `SafStream()` needs these registered first. Lets `DownloadManager`'s own
/// SAF-branch glue code (which method gets called, with which arguments, what
/// it does with the result) be verified without a real Android device -- the
/// actual native plugin behavior still needs on-device verification, this
/// only covers this app's own Dart-side logic.
class FakeSafUtilPlatform extends SafUtilPlatform {
  /// Each entry is the `(treeUri, names)` passed to [mkdirp] -- `names`
  /// joined with `/` rather than kept as a `List<String>`, since a plain
  /// `List` has no content equality, making it awkward to assert on directly
  /// in a test.
  final List<(String, String)> mkdirpCalls = [];

  @override
  Future<SafDocumentFile> mkdirp(String uri, List<String> names) async {
    mkdirpCalls.add((uri, names.join('/')));
    return SafDocumentFile(uri: '$uri/${names.join('/')}', name: names.last, isDir: true, length: 0, lastModified: 0);
  }
}

class FakeSafStreamPlatform extends SafStreamPlatform {
  /// Each entry is the `(treeUri, fileName, mime)` passed to [writeFileBytes]
  /// (the actual bytes aren't recorded -- no existing test needs to assert on
  /// their content, only that a write happened with the right destination).
  final List<(String, String, String)> writeFileBytesCalls = [];

  @override
  Future<SafNewFile> writeFileBytes(String treeUri, String fileName, String mime, Uint8List data, {bool? overwrite, bool? append}) async {
    writeFileBytesCalls.add((treeUri, fileName, mime));
    return SafNewFile(Uri.parse('$treeUri/$fileName'), fileName);
  }
}
