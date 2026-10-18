import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../app_version.dart';

/// What [UpdateCheckService.check] found (or didn't) -- [UpdateCheckResult.none]
/// covers every "nothing to do" case (no network, malformed response,
/// already on the latest build, or a platform autoupdate doesn't support)
/// so callers only ever need one `if (result.updateAvailable)` branch.
class UpdateCheckResult {
  final bool updateAvailable;
  final int latestBuildNumber;
  final String? tagName;

  /// The current platform's own release asset URL -- never null when
  /// [updateAvailable] is true and the release actually has a matching
  /// asset; a release missing one (e.g. a still-in-progress CI run) is
  /// treated the same as no update at all.
  final String? downloadUrl;
  final String? releaseNotes;

  const UpdateCheckResult({required this.updateAvailable, required this.latestBuildNumber, this.tagName, this.downloadUrl, this.releaseNotes});

  static const none = UpdateCheckResult(updateAvailable: false, latestBuildNumber: 0);
}

/// Checks GitHub's public Releases API (the same one server/src/updater.c
/// uses, over plain HTTPS) for a release newer than [appBuildNumber] --
/// deliberately not libgit2: release *binaries* live in GitHub's separate
/// Releases storage, never the git object database, so there's no git-level
/// way to get a download URL for one in the first place.
class UpdateCheckService {
  static const _repoOwner = 'Nyjako';
  static const _repoName = 'little-bunny';

  /// Injectable for tests (a fake [http.Client]); `null` lazily creates a
  /// real one per call -- same pattern as [DownloadManager.client].
  final http.Client? client;

  const UpdateCheckService({this.client});

  /// The suffix identifying this platform's own release asset (every
  /// platform's filename is namespaced consistently, see release.yml) --
  /// `null` on a platform autoupdate doesn't support at all (iOS: no
  /// signing/distribution story for a sideloaded build in the first place).
  static String? assetSuffixForPlatform() {
    if (Platform.isLinux) return 'app-linux-x64.tar.gz';
    if (Platform.isWindows) return 'app-windows-x64.zip';
    if (Platform.isMacOS) return 'app-macos-arm64.zip';
    if (Platform.isAndroid) return 'app-android.apk';
    return null;
  }

  Future<UpdateCheckResult> check() async {
    final assetSuffix = assetSuffixForPlatform();
    if (assetSuffix == null) {
      return UpdateCheckResult.none;
    }

    final httpClient = client ?? http.Client();
    try {
      final response = await httpClient.get(
        Uri.parse('https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest'),
        headers: {'User-Agent': 'LittleBunny-App', 'Accept': 'application/vnd.github+json'},
      );
      if (response.statusCode != 200) {
        return UpdateCheckResult.none;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName = json['tag_name'] as String?;
      if (tagName == null || !tagName.startsWith('build-')) {
        return UpdateCheckResult.none;
      }
      final latestBuildNumber = int.tryParse(tagName.substring('build-'.length));
      if (latestBuildNumber == null || latestBuildNumber <= appBuildNumber) {
        return UpdateCheckResult.none;
      }

      final assets = (json['assets'] as List<dynamic>?) ?? const [];
      String? downloadUrl;
      for (final asset in assets) {
        final name = asset['name'] as String?;
        if (name != null && name.endsWith(assetSuffix)) {
          downloadUrl = asset['browser_download_url'] as String?;
          break;
        }
      }
      if (downloadUrl == null) {
        return UpdateCheckResult.none;
      }

      return UpdateCheckResult(updateAvailable: true, latestBuildNumber: latestBuildNumber, tagName: tagName, downloadUrl: downloadUrl, releaseNotes: json['body'] as String?);
    } catch (_) {
      return UpdateCheckResult.none;
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }
}
