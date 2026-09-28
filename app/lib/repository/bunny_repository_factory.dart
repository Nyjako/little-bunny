import 'bunny_repository.dart';
import 'ffi_bunny_repository.dart';
import 'http_bunny_repository.dart';

/// Which [BunnyRepository] implementation to build -- the single switch
/// point the roadmap's M6 entry describes, so `main.dart` and every screen
/// only ever depend on the abstract interface.
sealed class BunnyRepositoryConfig {
  const BunnyRepositoryConfig();
}

/// FFI into `bunny_core` (see `bunny_core_ffi/`).
class StandaloneConfig extends BunnyRepositoryConfig {
  final String dbPath;
  final String userAgent;

  const StandaloneConfig({required this.dbPath, required this.userAgent});
}

/// HTTPS against a `bunny_server` instance (see `docs/architecture.md`'s
/// "C server (M5)" section).
class NetworkedConfig extends BunnyRepositoryConfig {
  final Uri serverBaseUrl;
  final String bearerToken;
  final String certificateSha256Fingerprint;

  const NetworkedConfig({required this.serverBaseUrl, required this.bearerToken, required this.certificateSha256Fingerprint});
}

Future<BunnyRepository> createBunnyRepository(BunnyRepositoryConfig config) => switch (config) {
  StandaloneConfig(:final dbPath, :final userAgent) => FfiBunnyRepository.open(dbPath: dbPath, userAgent: userAgent),
  NetworkedConfig(:final serverBaseUrl, :final bearerToken, :final certificateSha256Fingerprint) => Future.value(
    HttpBunnyRepository(baseUrl: serverBaseUrl, bearerToken: bearerToken, certificateSha256Fingerprint: certificateSha256Fingerprint),
  ),
};
