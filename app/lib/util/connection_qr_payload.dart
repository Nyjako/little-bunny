import 'dart:convert';

/// The three fields `bunny_server --qr`/the server's `/qr` route encode as
/// JSON (`server_qr_build_connection_json` in `server/src/qr.c`) -- the
/// exact same shape `SetupScreen`'s networked-mode fields need filled in,
/// whether that JSON came from a scanned QR code or pasted clipboard text.
class ConnectionQrPayload {
  final Uri serverUrl;
  final String bearerToken;
  final String certSha256;

  const ConnectionQrPayload({required this.serverUrl, required this.bearerToken, required this.certSha256});

  /// Null (never throws) on malformed JSON, non-object JSON, a missing/
  /// non-string/empty field, or a non-absolute `server_url` -- callers show
  /// an inline error rather than crashing on whatever text a camera or the
  /// clipboard happened to produce.
  static ConnectionQrPayload? tryParse(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) {
      return null;
    }

    final serverUrl = decoded['server_url'];
    final bearerToken = decoded['bearer_token'];
    final certSha256 = decoded['cert_sha256'];
    if (serverUrl is! String || bearerToken is! String || certSha256 is! String) {
      return null;
    }
    if (serverUrl.isEmpty || bearerToken.isEmpty || certSha256.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(serverUrl);
    if (uri == null || !uri.isAbsolute) {
      return null;
    }
    return ConnectionQrPayload(serverUrl: uri, bearerToken: bearerToken, certSha256: certSha256);
  }
}
