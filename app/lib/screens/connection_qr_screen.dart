import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../repository/http_bunny_repository.dart';

/// Shows this device's own connection info (server URL/bearer token/cert
/// fingerprint -- whatever [serverUrl]/[bearerToken]/[certSha256] were
/// already loaded from [NetworkedConfig]) as a QR code rendered by the
/// server's `/qr` route, for a second device to scan into `SetupScreen`'s
/// "Scan QR code" entry point. Fetches once on open, same pattern as
/// [ServerLogsScreen].
class ConnectionQrScreen extends StatefulWidget {
  final HttpBunnyRepository repository;
  final Uri serverUrl;
  final String bearerToken;
  final String certSha256;

  const ConnectionQrScreen({super.key, required this.repository, required this.serverUrl, required this.bearerToken, required this.certSha256});

  @override
  State<ConnectionQrScreen> createState() => _ConnectionQrScreenState();
}

class _ConnectionQrScreenState extends State<ConnectionQrScreen> {
  late final Future<Uint8List> _pngFuture;

  @override
  void initState() {
    super.initState();
    _pngFuture = widget.repository.fetchConnectionQrPng(serverUrl: widget.serverUrl, bearerToken: widget.bearerToken, certSha256: widget.certSha256);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.connectionQrScreenTitle)),
      body: Center(
        child: FutureBuilder<Uint8List>(
          future: _pngFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Padding(padding: const EdgeInsets.all(16), child: Text(l10n.connectionQrLoadError('${snapshot.error}')));
            }
            if (!snapshot.hasData) {
              return const CircularProgressIndicator();
            }
            return Padding(padding: const EdgeInsets.all(16), child: Image.memory(snapshot.data!));
          },
        ),
      ),
    );
  }
}
