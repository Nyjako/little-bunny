import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/update_apply_service.dart';
import '../services/update_check_service.dart';
import '../util/byte_format.dart';
import 'release_notes_text.dart';

/// Checks for an update and, if one's available, shows a confirmation
/// dialog -- called once from [SearchesScreen]'s `initState` (M23), and also
/// from [AboutScreen]'s manual "Check for app update" button. Returns
/// whether an update was actually found (and the dialog shown), so the
/// manual path can confirm it checked ("no update available") while the
/// automatic path can keep ignoring the result and staying silent either
/// way. Injectable services for tests; both default to real instances.
Future<bool> checkForUpdateAndMaybePrompt(BuildContext context, {UpdateCheckService checkService = const UpdateCheckService(), UpdateApplyService applyService = const UpdateApplyService()}) async {
  final result = await checkService.check();
  if (!result.updateAvailable || !context.mounted) {
    return false;
  }
  await showDialog<void>(context: context, builder: (context) => _UpdateDialog(result: result, applyService: applyService));
  return true;
}

class _UpdateDialog extends StatefulWidget {
  final UpdateCheckResult result;
  final UpdateApplyService applyService;

  const _UpdateDialog({required this.result, required this.applyService});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _updating = false;
  int _bytesReceived = 0;
  int? _bytesTotal;
  String? _error;

  Future<void> _update() async {
    setState(() {
      _updating = true;
      _error = null;
    });
    bool ok;
    try {
      ok = await widget.applyService.downloadAndApply(
        widget.result.downloadUrl!,
        sha256SumsUrl: widget.result.sha256SumsUrl,
        onProgress: (received, total) {
          if (mounted) {
            setState(() {
              _bytesReceived = received;
              _bytesTotal = total;
            });
          }
        },
      );
    } catch (_) {
      ok = false;
    }
    // On Linux/macOS/Windows a successful apply calls exit(0) on this same
    // process (see UpdateApplyService) and this widget never gets a chance
    // to run again -- reaching here at all means either Android (no
    // exit -- the OS's own installer UI takes over from here) or a failure.
    if (!mounted) {
      return;
    }
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _updating = false;
        _error = AppLocalizations.of(context)!.updateFailedMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final total = _bytesTotal;
    return PopScope(
      // Blocks both the barrier tap (showDialog's default barrierDismissible
      // routes it through Navigator.maybePop, which respects this) and the
      // system back gesture while a download is actually in flight -- before
      // _updating flips true, this stays a no-op and "Later"/tapping outside
      // keep working exactly as before.
      canPop: !_updating,
      child: AlertDialog(
        title: Text(l10n.updateAvailableTitle(widget.result.tagName ?? '')),
        content: _updating
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: total != null && total > 0 ? _bytesReceived / total : null),
                  const SizedBox(height: 12),
                  Text(total != null ? '${formatBytesCompact(_bytesReceived)} / ${formatBytesCompact(total)}' : formatBytesCompact(_bytesReceived)),
                  const SizedBox(height: 4),
                  Text(l10n.updateDownloadingMessage),
                ],
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if ((widget.result.releaseNotes ?? '').isNotEmpty) ReleaseNotesText(text: widget.result.releaseNotes!),
                    if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
                  ],
                ),
              ),
        actions: _updating
            ? const []
            : [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.updateLaterAction)), FilledButton(onPressed: _update, child: Text(l10n.updateNowAction))],
      ),
    );
  }
}
