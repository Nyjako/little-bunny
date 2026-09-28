import '../repository/bunny_repository.dart';
import '../repository/http_bunny_repository.dart';

/// Tests networked-mode config (server URL, bearer token, cert fingerprint)
/// with one real authenticated request before the setup screen persists it.
/// Deliberately reuses [HttpBunnyRepository] itself rather than a bare
/// `GET /health` -- `/health` needs no auth (see docs/architecture.md's "C
/// server (M5)" section), so it would confirm the server and certificate are
/// reachable but never catch a wrong bearer token. `listSearches` is a
/// lightweight authenticated read that exercises both checks at once.
/// Returns `null` on success, or a message to show the user on failure.
/// Not a [BunnyRepository] interface method: a connection health check
/// isn't meaningful for standalone/FFI mode, so it doesn't belong on the
/// shared abstract interface.
Future<String?> checkServerConnection({required Uri baseUrl, required String bearerToken, required String certificateSha256Fingerprint}) async {
  final repository = HttpBunnyRepository(baseUrl: baseUrl, bearerToken: bearerToken, certificateSha256Fingerprint: certificateSha256Fingerprint);
  try {
    await repository.listSearches();
    return null;
  } on BunnyRepositoryException catch (e) {
    return e.message;
  } on Object catch (e) {
    return e.toString();
  } finally {
    repository.close();
  }
}
