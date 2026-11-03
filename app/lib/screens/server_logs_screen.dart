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

/// Matches `server_log`'s own `"[%s] [%s] %s"` line format (timestamp,
/// then level) -- used to color just the level tag, not the whole line.
final _levelPattern = RegExp(r'^\[[^\]]*\] \[([A-Z]+)\]');

class _ServerLogsScreenState extends State<ServerLogsScreen> {
  Future<List<String>>? _logsFuture;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _load() {
    _logsFuture = widget.repository.getServerLogs();
  }

  /// [server_log_snapshot]'s own doc comment confirms lines arrive
  /// oldest-first, same order `journalctl -f` reads -- jumping to the
  /// bottom (not reversing the list) keeps that familiar top-to-bottom
  /// reading order while still landing on the newest line without the user
  /// having to scroll for it themselves, matching a `tail -f` feel.
  void _scrollToNewest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && _scrollController.position.hasContentDimensions) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Color? _levelColor(BuildContext context, String line) {
    final level = _levelPattern.firstMatch(line)?.group(1);
    return switch (level) {
      'ERROR' => Theme.of(context).colorScheme.error,
      'WARN' || 'WARNING' => Colors.orange,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.serverLogsScreenTitle),
        actions: [IconButton(icon: const Icon(Icons.refresh), tooltip: l10n.serverLogsRefreshTooltip, onPressed: () => setState(_load))],
      ),
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
          _scrollToNewest();
          return ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(8),
            itemCount: lines.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                lines[index],
                style: TextStyle(fontFamily: 'monospace', color: _levelColor(context, lines[index])),
              ),
            ),
          );
        },
      ),
    );
  }
}
