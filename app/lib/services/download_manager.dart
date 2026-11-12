import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:http/http.dart' as http;
import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';

import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';
import '../util/image_headers.dart';

/// Top-level (not a method) because [compute] requires that -- it spawns a
/// real worker isolate to run this on, so a multi-megabyte checksum hash
/// never blocks the main isolate's event loop. Only used by the SAF branch
/// below (M66 moved the plain-filesystem-path branch's own hashing into C,
/// see [BunnyRepository.downloadFile]) -- SAF (Android's Storage Access
/// Framework) has no native C path at all, so that branch still buffers
/// and hashes in Dart exactly as it always has.
String _computeMd5(Uint8List bytes) => md5.convert(bytes).toString();

/// Best-effort extension-to-MIME-type mapping, only needed for the SAF write
/// path below (`saf_stream`'s `writeFileBytes` requires one; the native
/// plain-path write doesn't). Falls back to a generic binary type for
/// anything not covered -- SAF doesn't refuse an unknown MIME type, it just
/// can't give the resulting file a more specific one.
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
///
/// A thin dispatcher since M66: a `content://` [destinationFolder] (Android
/// Storage Access Framework, picked via Settings) still goes through this
/// class's own Dart fetch/hash/write, since SAF needs Android's
/// `ContentResolver` -- no practical path from C without large amounts of
/// fragile JNI that would just reimplement what `saf_stream`/`saf_util`
/// already do well. Every other (plain filesystem path) destination now
/// delegates to [BunnyRepository.downloadFile], which does the real fetch
/// natively -- see that method's own doc comment for why this is correct
/// for networked mode too (downloads never proxy through the server).
class DownloadManager {
  /// Injectable for tests (a fake [http.Client]); `null` lazily creates a
  /// real one per call rather than holding it as const-incompatible state.
  /// Only used by the SAF branch now (M66) -- the plain-path branch no
  /// longer does its own HTTP at all.
  final http.Client? client;

  const DownloadManager({this.client});

  static String _sanitizeArtist(String? artist) {
    if (artist == null || artist.trim().isEmpty) {
      return 'unknown';
    }
    return artist.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  static String _sanitizePoolName(String? name) {
    if (name == null || name.trim().isEmpty) {
      return 'untitled';
    }
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  /// Where [post] lands on disk -- the regular per-artist scheme, unless
  /// [poolId]/[poolName]/[poolPage] (M65) mark this as part of a pool
  /// download, in which case it's filed under a pool-named folder with a
  /// page-numbered filename instead, e.g. `pool:1234 - My Comic/1234 -
  /// p0007 [987654].png` for pool 1234 ("My Comic"), page 7, post external
  /// id 987654. e621 caps a pool at 1000 posts, hence the 4-digit zero-padded
  /// page width -- always enough, never excessive. [poolPage] <= 0 is
  /// treated the same as "not a pool download" (an unset/sentinel value,
  /// not a real page).
  (String folder, String filename) _destinationFor(BunnyPost post, String ext, {int poolId = 0, String? poolName, int poolPage = 0}) {
    if (poolId > 0 && poolPage > 0) {
      return ('pool:$poolId - ${_sanitizePoolName(poolName)}', '$poolId - p${poolPage.toString().padLeft(4, '0')} [${post.externalId}].$ext');
    }
    return (_sanitizeArtist(post.artist), '${post.externalId}.$ext');
  }

  /// Whether [post] already has a file sitting at the exact deterministic
  /// path [downloadPost] would write to -- "downloaded" is a per-device
  /// filesystem fact (M42), not something a shared server can meaningfully
  /// track: a download recorded on one device used to show as already-
  /// downloaded on every other device sharing the same server, even on a
  /// device that never actually wrote the file. Mirrors [downloadPost]'s own
  /// path computation exactly ([_destinationFor], same SAF-vs-plain-path
  /// branch) without touching the network. Stays 100% Dart (M66) -- a pure
  /// existence check with no network/checksum logic, not part of the fetch
  /// being migrated.
  Future<bool> isDownloaded(BunnyPost post, String destinationFolder, {int poolId = 0, String? poolName, int poolPage = 0}) async {
    final ext = post.fileExt ?? 'bin';
    final (folder, filename) = _destinationFor(post, ext, poolId: poolId, poolName: poolName, poolPage: poolPage);
    if (destinationFolder.startsWith('content://')) {
      final child = await SafUtil().child(destinationFolder, [folder, filename]);
      return child != null;
    }
    return File('$destinationFolder/$folder/$filename').exists();
  }

  /// Same question as [isDownloaded], for many posts at once -- returns a
  /// map keyed by [BunnyPost.id]. On a plain filesystem path this is just
  /// [isDownloaded] in a loop (already a fast direct stat call); under SAF
  /// (`content://`, Android's Storage Access Framework) it's a real
  /// optimization, not just a convenience wrapper: `SafUtil().child()` has
  /// no direct "does this path exist" primitive on Android's side, so it
  /// resolves one path *segment* at a time, meaning every call for a post
  /// re-lists that post's whole artist subfolder from scratch just to find
  /// one matching filename in it. Checking hundreds or thousands of posts
  /// this way (e.g. a slideshow's whole committed set, M51 v2 prepare)
  /// measured in minutes on a real device -- confirmed live as the cause of
  /// "Prepare" appearing to hang on Android while working fine on desktop's
  /// plain-path branch. This instead lists each distinct artist subfolder's
  /// contents exactly ONCE (posts naturally group into relatively few
  /// subfolders -- one per artist -- even when there are thousands of
  /// posts), then checks filename membership in that listing purely in
  /// Dart, with no further platform-channel round trip per post.
  Future<Map<int, bool>> batchIsDownloaded(List<BunnyPost> posts, String destinationFolder, {int poolId = 0, String? poolName, int poolPage = 0}) async {
    if (!destinationFolder.startsWith('content://')) {
      final result = <int, bool>{};
      for (final post in posts) {
        result[post.id] = await isDownloaded(post, destinationFolder, poolId: poolId, poolName: poolName, poolPage: poolPage);
      }
      return result;
    }

    final postsByFolder = <String, List<BunnyPost>>{};
    final filenameByPostId = <int, String>{};
    for (final post in posts) {
      final ext = post.fileExt ?? 'bin';
      final (folder, filename) = _destinationFor(post, ext, poolId: poolId, poolName: poolName, poolPage: poolPage);
      postsByFolder.putIfAbsent(folder, () => []).add(post);
      filenameByPostId[post.id] = filename;
    }

    final result = <int, bool>{};
    for (final entry in postsByFolder.entries) {
      final folderDoc = await SafUtil().child(destinationFolder, [entry.key]);
      if (folderDoc == null) {
        // The subfolder itself doesn't exist yet -- none of its posts can
        // be downloaded, and there's nothing to list.
        for (final post in entry.value) {
          result[post.id] = false;
        }
        continue;
      }
      final existingNames = (await SafUtil().list(folderDoc.uri)).map((f) => f.name).toSet();
      for (final post in entry.value) {
        result[post.id] = existingNames.contains(filenameByPostId[post.id]);
      }
    }
    return result;
  }

  /// Same deterministic-path computation [isDownloaded] already uses, but
  /// returning the resolved path (or SAF uri) instead of a bare bool --
  /// for a caller that needs to actually read the file, not just check
  /// whether it exists (e.g. a slideshow playing already-downloaded posts
  /// back from disk). Null if nothing is there yet, same as [isDownloaded]
  /// returning false.
  Future<String?> localFilePathFor(BunnyPost post, String destinationFolder, {int poolId = 0, String? poolName, int poolPage = 0}) async {
    final ext = post.fileExt ?? 'bin';
    final (folder, filename) = _destinationFor(post, ext, poolId: poolId, poolName: poolName, poolPage: poolPage);
    if (destinationFolder.startsWith('content://')) {
      final child = await SafUtil().child(destinationFolder, [folder, filename]);
      return child?.uri;
    }
    final file = File('$destinationFolder/$folder/$filename');
    return await file.exists() ? file.path : null;
  }

  /// Same question as [localFilePathFor], for many posts at once -- a post
  /// missing from the returned map simply has no file on disk. Same
  /// folder-grouped SAF optimization as [batchIsDownloaded] (see its own
  /// doc comment for why one `SafUtil().child()`/`list()` pair per
  /// *post* -- not per distinct artist folder -- measured in minutes for a
  /// large slideshow's worth of posts): confirmed live as the cause of
  /// a slideshow's own "Watch" action hanging on Android (and taking the
  /// better part of a minute even on a plain filesystem path, from the
  /// sheer number of sequential awaited calls) while [SlideshowPrepareService.
  /// prepare] itself was already fast after already getting this same
  /// treatment.
  Future<Map<int, String>> batchLocalFilePathFor(List<BunnyPost> posts, String destinationFolder, {int poolId = 0, String? poolName, int poolPage = 0}) async {
    if (!destinationFolder.startsWith('content://')) {
      final result = <int, String>{};
      for (final post in posts) {
        final path = await localFilePathFor(post, destinationFolder, poolId: poolId, poolName: poolName, poolPage: poolPage);
        if (path != null) {
          result[post.id] = path;
        }
      }
      return result;
    }

    final postsByFolder = <String, List<BunnyPost>>{};
    final filenameByPostId = <int, String>{};
    for (final post in posts) {
      final ext = post.fileExt ?? 'bin';
      final (folder, filename) = _destinationFor(post, ext, poolId: poolId, poolName: poolName, poolPage: poolPage);
      postsByFolder.putIfAbsent(folder, () => []).add(post);
      filenameByPostId[post.id] = filename;
    }

    final result = <int, String>{};
    for (final entry in postsByFolder.entries) {
      final folderDoc = await SafUtil().child(destinationFolder, [entry.key]);
      if (folderDoc == null) {
        continue;
      }
      final uriByName = {for (final file in await SafUtil().list(folderDoc.uri)) file.name: file.uri};
      for (final post in entry.value) {
        final uri = uriByName[filenameByPostId[post.id]];
        if (uri != null) {
          result[post.id] = uri;
        }
      }
    }
    return result;
  }

  /// SAF-only now (M66 moved the plain-path equivalent into C, see
  /// [BunnyRepository.downloadFile]'s own skip-fetch fast path). Reads back
  /// whatever already sits at [downloadPost]'s own deterministic SAF path
  /// for [post], if anything does -- same pool-aware [folder]/[filename]
  /// resolution as [isDownloaded], just returning the bytes (for a checksum
  /// check) and the resolved uri instead of a bare bool. Null if nothing is
  /// there yet.
  Future<(Uint8List bytes, String path)?> _readExistingSafFile(BunnyPost post, String destinationFolder, String folder, String filename) async {
    final child = await SafUtil().child(destinationFolder, [folder, filename]);
    if (child == null) {
      return null;
    }
    return (await SafStream().readFileBytes(child.uri), child.uri);
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
  /// percentage.
  ///
  /// Skips the fetch entirely when a file already sits at the deterministic
  /// path *and* its checksum still matches what was published (M62 follow-
  /// up) -- common when re-running a mass download over a batch that's
  /// mostly already on disk. For the plain-path branch this check is
  /// [repository.downloadFile]'s own concern now (M66); the SAF branch
  /// below still does it directly in Dart, same as before.
  ///
  /// [poolId]/[poolName]/[poolPage] (M65) -- see [_destinationFor]'s own
  /// doc comment for the alternate pool-named folder/filename scheme these
  /// select.
  Future<DownloadResult> downloadPost(
    BunnyPost post,
    BunnyRepository repository,
    String destinationFolder, {
    bool autoFavorite = false,
    bool autoUpvote = false,
    void Function(int received, int? total)? onProgress,
    int poolId = 0,
    String? poolName,
    int poolPage = 0,
  }) async {
    final url = post.fileUrl;
    if (url == null) {
      return const DownloadResult(DownloadOutcome.noFileUrl);
    }
    final ext = post.fileExt ?? 'bin';
    final (folder, filename) = _destinationFor(post, ext, poolId: poolId, poolName: poolName, poolPage: poolPage);

    if (destinationFolder.startsWith('content://')) {
      return _downloadViaSaf(post, url, repository, destinationFolder, folder, filename, ext, autoFavorite: autoFavorite, autoUpvote: autoUpvote);
    }

    try {
      final result = await repository.downloadFile(url, imageHeadersFor(post.site) ?? const {}, '$destinationFolder/$folder', filename, post.fileMd5, (received, total) => onProgress?.call(received, total));
      final filePath = '$destinationFolder/$folder/$filename';

      switch (result.outcome) {
        case 'verified':
        case 'checksumMismatch':
          if (autoFavorite) {
            await repository.queueFavoriteAdd(post.id);
          }
          if (autoUpvote && post.site == BunnySite.e621) {
            await repository.queueVote(post.id, 1);
          }
          return DownloadResult(result.outcome == 'verified' ? DownloadOutcome.verified : DownloadOutcome.checksumMismatch, filePath: filePath);
        default:
          return DownloadResult(DownloadOutcome.failed, errorMessage: result.errorMessage);
      }
    } catch (e) {
      return DownloadResult(DownloadOutcome.failed, errorMessage: e.toString());
    }
  }

  /// A `content://` destination means the user picked a folder via
  /// Android's Storage Access Framework (see SettingsScreen's own doc
  /// comment on `_chooseDownloadFolder`) -- `dart:io`'s File/Directory
  /// can't write there at all, and this has no native C path either (M66),
  /// so it stays exactly as it was before that migration: fetch via
  /// [client]/`http`, hash in Dart via [compute], write via
  /// `saf_util`/`saf_stream`. [folder]/[filename] are already resolved by
  /// [downloadPost] via [_destinationFor] (pool-aware, M65).
  Future<DownloadResult> _downloadViaSaf(
    BunnyPost post,
    String url,
    BunnyRepository repository,
    String destinationFolder,
    String folder,
    String filename,
    String ext, {
    required bool autoFavorite,
    required bool autoUpvote,
  }) async {
    try {
      final existing = await _readExistingSafFile(post, destinationFolder, folder, filename);
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
      final builder = BytesBuilder(copy: false);
      await for (final chunk in streamedResponse.stream) {
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();

      // create (or reuse) the folder under the picked tree, then write the
      // file into it. overwrite: true always overwrites at the same
      // deterministic path rather than generating a new name each time.
      final folderDir = await SafUtil().mkdirp(destinationFolder, [folder]);
      final newFile = await SafStream().writeFileBytes(folderDir.uri, filename, _mimeTypeFor(ext), bytes, overwrite: true);
      final filePath = newFile.uri.toString();

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
