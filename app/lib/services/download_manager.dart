import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';

import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../util/image_headers.dart';

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

  const DownloadResult(this.outcome, {this.filePath});
}

/// Pure logic, no widget -- the first class in this `services/` directory
/// (as distinct from `widgets/`'s shared UI components). Reused identically
/// from the single-post download button ([PostDetailScreen], M9.4) and the
/// mass-download action (M9.5). Downloads are never proxied through the
/// server (see `docs/architecture.md`): this fetches the file directly from
/// the site's own CDN and only calls [BunnyRepository.recordDownload]
/// afterward, purely for bookkeeping.
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
  Future<DownloadResult> downloadPost(BunnyPost post, BunnyRepository repository, String destinationFolder, {bool autoFavorite = false, bool autoUpvote = false}) async {
    final url = post.fileUrl;
    if (url == null) {
      return const DownloadResult(DownloadOutcome.noFileUrl);
    }
    try {
      final httpClient = client ?? http.Client();
      final response = await httpClient.get(Uri.parse(url), headers: imageHeadersFor(post.site) ?? const {});
      if (response.statusCode != 200) {
        return const DownloadResult(DownloadOutcome.failed);
      }
      final bytes = response.bodyBytes;

      final artistFolder = _sanitizeArtist(post.artist);
      final ext = post.fileExt ?? 'bin';
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
        await File(filePath).writeAsBytes(bytes);
      }

      final checksum = md5.convert(bytes).toString();
      final expected = post.fileMd5;
      final verified = expected == null || expected.toLowerCase() == checksum;

      await repository.recordDownload(post.id, filePath, checksumMd5: checksum, verified: verified);
      if (autoFavorite) {
        await repository.queueFavoriteAdd(post.id);
      }
      if (autoUpvote && post.site == BunnySite.e621) {
        await repository.queueVote(post.id, 1);
      }

      return DownloadResult(verified ? DownloadOutcome.verified : DownloadOutcome.checksumMismatch, filePath: filePath);
    } catch (_) {
      return const DownloadResult(DownloadOutcome.failed);
    }
  }
}
