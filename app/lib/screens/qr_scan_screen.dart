import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../l10n/app_localizations.dart';

/// Scans a connection QR code (produced by `bunny_server --qr` or the app's
/// own "Share connection QR" screen) and pops back with the raw decoded
/// text -- parsing that text into the three connection fields is
/// [SetupScreen]'s job (via `ConnectionQrPayload.tryParse`), not this
/// screen's, so this stays a dumb camera-to-text widget.
class QrScanScreen extends StatelessWidget {
  const QrScanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.setupScanQrCode)),
      body: MobileScanner(
        onDetect: (capture) {
          final value = capture.barcodes.firstOrNull?.rawValue;
          if (value != null) {
            Navigator.pop(context, value);
          }
        },
      ),
    );
  }
}
