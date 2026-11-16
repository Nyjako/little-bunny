import 'repository/bunny_repository_factory.dart';
import 'settings/app_lock_service.dart';
import 'settings/download_settings_store.dart';
import 'settings/repository_settings_store.dart';

/// Pure logic behind the `--cli-handshake` entry point `main()` branches to
/// (M84) -- answers "what repository config is this app currently set up
/// with, and does [suppliedSecret] unlock it if app-lock is on" without
/// touching stdin/stdout/`exit()` itself, so this is fully unit-testable the
/// same way every other service in this app is. `main.dart`'s handshake
/// branch is the only place that actually reads a line from stdin,
/// JSON-encodes this function's return value to stdout, and calls `exit()`
/// -- see that function's own doc comment for the full protocol `bunny_cli`
/// (a separate, pure-C executable shipped alongside this app, shipped in the
/// same directory) speaks against it: it launches this app with
/// `--cli-handshake`, writes one line (the secret to try, or an empty line)
/// to its stdin, and reads exactly one JSON line back from its stdout before
/// this process exits.
///
/// Returns a JSON-ready [Map] with one of these shapes:
/// - `{'ok': false, 'error': 'locked'}` -- app-lock is on and [suppliedSecret]
///   didn't match (including an empty one). The real config is never
///   included here, even partially -- a locked app tells `bunny_cli` nothing
///   more than that it's locked.
/// - `{'ok': true, 'mode': 'none'}` -- unlocked (or app-lock is off), but no
///   repository has been configured yet (first launch -- [settingsStore]'s
///   own `load()` returned null). No [downloadDestinationFolder] either --
///   there's no meaningful "the app's download folder" before setup.
/// - `{'ok': true, 'mode': 'standalone', 'dbPath': ..., 'userAgent': ...,
///   'downloadDestinationFolder': ...}`
/// - `{'ok': true, 'mode': 'networked', 'serverBaseUrl': ..., 'bearerToken':
///   ..., 'certFingerprint': ..., 'downloadDestinationFolder': ...}`
///
/// [downloadDestinationFolder] (M85) is [DownloadSettingsStore
/// .loadDestinationFolder]'s own value -- a *separate* setting from
/// [settingsStore]'s repository config, but one `bunny_cli --download`
/// equally needs, to write files to the exact folder the app itself would
/// (same `DownloadManager._destinationFor` scheme either side builds,
/// ported to C as bunny_cli's own destination.c). Included alongside either
/// mode rather than nested under it, since this setting is mode-independent.
/// May itself be `null` in the rare case [DownloadSettingsStore
/// .loadDestinationFolder]'s own OS-Downloads-directory fallback also
/// fails -- bunny_cli reports that clearly rather than guessing a path.
Future<Map<String, Object?>> buildCliHandshakeResponse({
  required AppLockService lockService,
  required RepositorySettingsStore settingsStore,
  required DownloadSettingsStore downloadSettingsStore,
  required String suppliedSecret,
}) async {
  final locked = await lockService.isEnabled();
  if (locked && !await lockService.verify(suppliedSecret)) {
    return {'ok': false, 'error': 'locked'};
  }

  final config = await settingsStore.load();
  if (config == null) {
    return {'ok': true, 'mode': 'none'};
  }

  final downloadDestinationFolder = await downloadSettingsStore.loadDestinationFolder();
  return switch (config) {
    StandaloneConfig(:final dbPath, :final userAgent) => {
      'ok': true,
      'mode': 'standalone',
      'dbPath': dbPath,
      'userAgent': userAgent,
      'downloadDestinationFolder': downloadDestinationFolder,
    },
    NetworkedConfig(:final serverBaseUrl, :final bearerToken, :final certificateSha256Fingerprint) => {
      'ok': true,
      'mode': 'networked',
      'serverBaseUrl': serverBaseUrl.toString(),
      'bearerToken': bearerToken,
      'certFingerprint': certificateSha256Fingerprint,
      'downloadDestinationFolder': downloadDestinationFolder,
    },
  };
}
