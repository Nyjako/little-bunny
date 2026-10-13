import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../repository/http_bunny_repository.dart';

/// Shows recent `bunny_server` log lines (see `server/src/log.c`) so a
/// stuck/slow server can be diagnosed from the app, without SSH access to
/// the box. Fetches once on open; refreshing is an explicit app bar action
/// rather than auto-polling, matching the rest of the app's "explicit
/// refresh" pattern (e.g. [SearchesScreen]'s check-for-updates button).
class ServerLogsScreen extends StatefulWidget {
  final HttpBunnyRepository repository;

  const ServerLogsScreen({super.key, required this.repository});

  @override
  State<ServerLogsScreen> createState() => _ServerLogsScreenState();
}

class _ServerLogsScreenState extends State<ServerLogsScreen> {
  Future<List<String>>? _logsFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _logsFuture = widget.repository.getServerLogs();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.serverLogsScreenTitle), actions: [IconButton(icon: const Icon(Icons.refresh), tooltip: l10n.serverLogsRefreshTooltip, onPressed: () => setState(_load))]),
      body: FutureBuilder<List<String>>(
        future: _logsFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final lines = snapshot.data!;
          if (lines.isEmpty) {
            return Center(child: Text(l10n.serverLogsEmptyState));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: lines.length,
            itemBuilder: (context, index) => Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(lines[index], style: const TextStyle(fontFamily: 'monospace'))),
          );
        },
      ),
    );
  }
}
