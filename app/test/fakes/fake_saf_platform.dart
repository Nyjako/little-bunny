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

  /// Child paths (as `treeUri/joined-names`) that [child] should resolve to
  /// an existing file for -- everything else returns null, matching
  /// [DownloadManager.isDownloaded]'s "not found" case for a SAF tree. Maps
  /// to the bytes [FakeSafStreamPlatform.readFileBytes] should hand back for
  /// that same path (M62's "already downloaded, verify its checksum"
  /// path) -- empty bytes for a test that only cares about existence, not
  /// content.
  final Map<String, Uint8List> existingChildPaths = {};

  @override
  Future<SafDocumentFile> mkdirp(String uri, List<String> names) async {
    mkdirpCalls.add((uri, names.join('/')));
    return SafDocumentFile(uri: '$uri/${names.join('/')}', name: names.last, isDir: true, length: 0, lastModified: 0);
  }

  @override
  Future<SafDocumentFile?> child(String uri, List<String> names) async {
    final path = '$uri/${names.join('/')}';
    if (!existingChildPaths.containsKey(path)) {
      return null;
    }
    return SafDocumentFile(uri: path, name: names.last, isDir: false, length: 0, lastModified: 0);
  }

  /// Each entry is `folderUri: [filenames in that folder]` -- what [list]
  /// should return for a folder resolved via [child] (`isDir: true`
  /// entries only; [DownloadManager.batchIsDownloaded] never lists a plain
  /// file). A folder not present here (including one [child] itself
  /// resolved, e.g. via a real [mkdirp] call) just means "empty," not an
  /// error -- matches a real freshly-created SAF folder with nothing in it
  /// yet.
  final Map<String, List<String>> listResultsByFolderUri = {};

  @override
  Future<List<SafDocumentFile>> list(String uri) async =>
      (listResultsByFolderUri[uri] ?? const []).map((name) => SafDocumentFile(uri: '$uri/$name', name: name, isDir: false, length: 0, lastModified: 0)).toList();
}

class FakeSafStreamPlatform extends SafStreamPlatform {
  /// Each entry is the `(treeUri, fileName, mime)` passed to [writeFileBytes]
  /// (the actual bytes aren't recorded -- no existing test needs to assert on
  /// their content, only that a write happened with the right destination).
  final List<(String, String, String)> writeFileBytesCalls = [];

  /// Backing store [readFileBytes] reads from -- a test sets
  /// [FakeSafUtilPlatform.existingChildPaths] (keyed the same way, by the
  /// resolved `uri`) and this hands those same bytes back, matching
  /// [DownloadManager]'s own "resolve the child, then read it" two-step.
  final FakeSafUtilPlatform safUtil;

  FakeSafStreamPlatform(this.safUtil);

  @override
  Future<SafNewFile> writeFileBytes(String treeUri, String fileName, String mime, Uint8List data, {bool? overwrite, bool? append}) async {
    writeFileBytesCalls.add((treeUri, fileName, mime));
    return SafNewFile(Uri.parse('$treeUri/$fileName'), fileName);
  }

  @override
  Future<Uint8List> readFileBytes(String uri, {int? start, int? count}) async => safUtil.existingChildPaths[uri] ?? Uint8List(0);
}
