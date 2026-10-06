import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../util/image_headers.dart';

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
  /// since nothing was downloaded in those cases). Only queues it --
  /// draining the action queue afterward is left to the caller, which
  /// already decides that for its own batching needs (an immediate drain for
  /// a single download, one drain after a whole mass-download loop).
  Future<DownloadResult> downloadPost(BunnyPost post, BunnyRepository repository, String destinationFolder, {bool autoFavorite = false}) async {
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
      final directory = Directory('$destinationFolder/$artistFolder');
      await directory.create(recursive: true);
      final filePath = '${directory.path}/${post.externalId}.$ext';
      await File(filePath).writeAsBytes(bytes);

      final checksum = md5.convert(bytes).toString();
      final expected = post.fileMd5;
      final verified = expected == null || expected.toLowerCase() == checksum;

      await repository.recordDownload(post.id, filePath, checksumMd5: checksum, verified: verified);
      if (autoFavorite) {
        await repository.queueFavoriteAdd(post.id);
      }

      return DownloadResult(verified ? DownloadOutcome.verified : DownloadOutcome.checksumMismatch, filePath: filePath);
    } catch (_) {
      return const DownloadResult(DownloadOutcome.failed);
    }
  }
}
