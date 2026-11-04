import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';

import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../util/image_headers.dart';

/// Top-level (not a method) because [compute] requires that -- it spawns a
/// real worker isolate to run this on, so a multi-megabyte checksum hash
/// (M62: now potentially several of these running at once, one per
/// concurrently-downloading file) never blocks the main isolate's event
/// loop, which is also where every other in-flight download's own HTTP
/// stream and UI updates are being processed.
String _computeMd5(Uint8List bytes) => md5.convert(bytes).toString();

/// Best-effort extension-to-MIME-type mapping, only needed for the SAF write
/// path below (`saf_stream`'s `writeFileBytes` requires one; `dart:io`'s
/// plain `File.writeAsBytes` needs no such thing). Falls back to a generic
/// binary type for anything not covered -- SAF doesn't refuse an unknown
/// MIME type, it just can't give the resulting file a more specific one.
const _mimeTypesByExt = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'mp4': 'video/mp4',
  'webm': 'video/webm',
};

String _mimeTypeFor(String ext) => _mimeTypesByExt[ext.toLowerCase()] ?? 'application/octet-stream';

/// The result of a single [DownloadManager.downloadPost] call. [noFileUrl]
/// covers an Inkbunny post that was only ever synced via a search (M8.5.6's
/// already-documented gap -- `fileUrl` is only populated by a full
/// `inkbunny_get_submission` fetch); callers should gate the download button
/// on `post.fileUrl != null` instead of relying on this, but a direct call
/// still handles it gracefully rather than throwing. [checksumMismatch] only
/// fires when the post actually carries a `fileMd5` to compare against and it
/// doesn't match -- a post with no published checksum at all is treated as
/// [verified] (nothing to contradict).
enum DownloadOutcome { noFileUrl, verified, checksumMismatch, failed }

class DownloadResult {
  final DownloadOutcome outcome;
  final String? filePath;

  /// Populated for [DownloadOutcome.failed] (an HTTP status string or the
  /// caught exception's own message) so the queue screen can show *why* an
  /// item failed, not just that it did. Always `null` for every other
  /// outcome.
  final String? errorMessage;

  const DownloadResult(this.outcome, {this.filePath, this.errorMessage});
}

/// Pure logic, no widget -- the first class in this `services/` directory
/// (as distinct from `widgets/`'s shared UI components). Reused identically
/// from the single-post download button ([PostDetailScreen], M9.4) and the
/// mass-download action (M9.5). Downloads are never proxied through the
/// server (see `docs/architecture.md`): this fetches the file directly from
/// the site's own CDN and writes it straight to [destinationFolder].
class DownloadManager {
  /// Injectable for tests (a fake [http.Client]); `null` lazily creates a
  /// real one per call rather than holding it as const-incompatible state.
  final http.Client? client;

  const DownloadManager({this.client});

  static String _sanitizeArtist(String? artist) {
    if (artist == null || artist.trim().isEmpty) {
      return 'unknown';
    }
    return artist.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  /// Whether [post] already has a file sitting at the exact deterministic
  /// path [downloadPost] would write to -- "downloaded" is a per-device
  /// filesystem fact (M42), not something a shared server can meaningfully
  /// track: a download recorded on one device used to show as already-
  /// downloaded on every other device sharing the same server, even on a
  /// device that never actually wrote the file. Mirrors [downloadPost]'s own
  /// path computation exactly (same artist-folder sanitization, same
  /// `$externalId.$ext` filename, same SAF-vs-plain-path branch) without
  /// touching the network.
  Future<bool> isDownloaded(BunnyPost post, String destinationFolder) async {
    final artistFolder = _sanitizeArtist(post.artist);
    final ext = post.fileExt ?? 'bin';
    final filename = '${post.externalId}.$ext';
    if (destinationFolder.startsWith('content://')) {
      final child = await SafUtil().child(destinationFolder, [artistFolder, filename]);
      return child != null;
    }
    return File('$destinationFolder/$artistFolder/$filename').exists();
  }

  /// Reads back whatever already sits at [downloadPost]'s own deterministic
  /// path for [post], if anything does -- same SAF-vs-plain-path branch as
  /// [isDownloaded], just returning the bytes (for a checksum check) and the
  /// resolved path/uri instead of a bare bool. Null if nothing is there yet.
  Future<(Uint8List bytes, String path)?> _readExistingFile(BunnyPost post, String destinationFolder, String artistFolder, String ext) async {
    final filename = '${post.externalId}.$ext';
    if (destinationFolder.startsWith('content://')) {
      final child = await SafUtil().child(destinationFolder, [artistFolder, filename]);
      if (child == null) {
        return null;
      }
      return (await SafStream().readFileBytes(child.uri), child.uri);
    }
    final file = File('$destinationFolder/$artistFolder/$filename');
    if (!await file.exists()) {
      return null;
    }
    return (await file.readAsBytes(), file.path);
  }

  /// [autoFavorite] (M10.1) queues a favorite-add for [post] once the file is
  /// actually written to disk (a [DownloadOutcome.verified] or
  /// [DownloadOutcome.checksumMismatch] result -- never [noFileUrl]/[failed],
  /// since nothing was downloaded in those cases). [autoUpvote] (M14.2) does
  /// the same for an upvote, but e621-only -- Inkbunny has no vote API, same
  /// gate every other vote-related feature in this app already applies.
  /// Both only queue the action -- draining the action queue afterward is
  /// left to the caller, which already decides that for its own batching
  /// needs (an immediate drain for a single download, one drain after a
  /// whole mass-download loop).
  ///
  /// [onProgress] (M62), if given, is called as bytes arrive -- `total` is
  /// `null` whenever the server's response has no `Content-Length` (rare in
  /// practice for these two sites' CDNs, but not guaranteed), in which case
  /// a caller can still show `received` as a raw byte count but not a
  /// percentage. Streaming via `httpClient.send` rather than the simpler
  /// `httpClient.get` is what makes any progress reporting possible at all
  /// here -- `get` only ever resolves once the entire body has already
  /// been buffered, with nothing to report partway through.
  ///
  /// Skips the network fetch entirely when a file already sits at the
  /// deterministic path *and* its checksum still matches what was
  /// published (M62 follow-up) -- common when re-running a mass download
  /// over a batch that's mostly already on disk (e.g. after clearing a
  /// finished queue and tapping "download all" again). A checksum mismatch
  /// against the existing file (or no file there yet) falls through to a
  /// real fetch/overwrite below, same as before this existed.
  Future<DownloadResult> downloadPost(
    BunnyPost post,
    BunnyRepository repository,
    String destinationFolder, {
    bool autoFavorite = false,
    bool autoUpvote = false,
    void Function(int received, int? total)? onProgress,
  }) async {
    final url = post.fileUrl;
    if (url == null) {
      return const DownloadResult(DownloadOutcome.noFileUrl);
    }
    try {
      final artistFolder = _sanitizeArtist(post.artist);
      final ext = post.fileExt ?? 'bin';
      final existing = await _readExistingFile(post, destinationFolder, artistFolder, ext);
      if (existing != null) {
        final (existingBytes, existingPath) = existing;
        final expected = post.fileMd5;
        final alreadyVerified = expected == null || expected.toLowerCase() == await compute(_computeMd5, existingBytes);
        if (alreadyVerified) {
          if (autoFavorite) {
            await repository.queueFavoriteAdd(post.id);
          }
          if (autoUpvote && post.site == BunnySite.e621) {
            await repository.queueVote(post.id, 1);
          }
          return DownloadResult(DownloadOutcome.verified, filePath: existingPath);
        }
      }

      final httpClient = client ?? http.Client();
      final request = http.Request('GET', Uri.parse(url))..headers.addAll(imageHeadersFor(post.site) ?? const {});
      final streamedResponse = await httpClient.send(request);
      if (streamedResponse.statusCode != 200) {
        return DownloadResult(DownloadOutcome.failed, errorMessage: 'HTTP ${streamedResponse.statusCode}');
      }
      final total = streamedResponse.contentLength;
      final builder = BytesBuilder(copy: false);
      var received = 0;
      await for (final chunk in streamedResponse.stream) {
        builder.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      final bytes = builder.takeBytes();

      final String filePath;
      if (destinationFolder.startsWith('content://')) {
        // A `content://` destination means the user picked a folder via
        // Android's Storage Access Framework (see SettingsScreen's own doc
        // comment on _chooseDownloadFolder) -- dart:io's File/Directory
        // can't write there at all, so this goes through saf_util/saf_stream
        // instead: create (or reuse) the artist subfolder under the picked
        // tree, then write the file into it. overwrite: true matches the
        // plain-path branch below, which always overwrites at the same
        // deterministic path rather than generating a new name each time.
        final artistDir = await SafUtil().mkdirp(destinationFolder, [artistFolder]);
        final newFile = await SafStream().writeFileBytes(artistDir.uri, '${post.externalId}.$ext', _mimeTypeFor(ext), bytes, overwrite: true);
        filePath = newFile.uri.toString();
      } else {
        final directory = Directory('$destinationFolder/$artistFolder');
        await directory.create(recursive: true);
        filePath = '${directory.path}/${post.externalId}.$ext';
        // Written to a temp file first, then moved into place, so a crash
        // or kill mid-write (M43) never leaves a corrupt, half-written file
        // sitting at the user-visible destination path -- `rename` is atomic
        // within the same filesystem; the copy+delete fallback only matters
        // if the OS temp dir and destination folder happen to be on
        // different filesystems/volumes. The suffix (M62) makes this unique
        // per call, not just per post -- parallel downloads mean the exact
        // same post could theoretically be in flight twice at once (nothing
        // dedupes the queue against itself), which would otherwise let two
        // calls race on the identical temp path.
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/${post.site.toWireString()}_${post.externalId}.$ext.${DateTime.now().microsecondsSinceEpoch}.tmp');
        await tempFile.writeAsBytes(bytes);
        try {
          await tempFile.rename(filePath);
        } catch (_) {
          await tempFile.copy(filePath);
          await tempFile.delete();
        }
      }

      final checksum = await compute(_computeMd5, bytes);
      final expected = post.fileMd5;
      final verified = expected == null || expected.toLowerCase() == checksum;

      if (autoFavorite) {
        await repository.queueFavoriteAdd(post.id);
      }
      if (autoUpvote && post.site == BunnySite.e621) {
        await repository.queueVote(post.id, 1);
      }

      return DownloadResult(verified ? DownloadOutcome.verified : DownloadOutcome.checksumMismatch, filePath: filePath);
    } catch (e) {
      return DownloadResult(DownloadOutcome.failed, errorMessage: e.toString());
    }
  }
}
