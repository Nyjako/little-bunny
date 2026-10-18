import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/update_apply_service.dart';
import '../services/update_check_service.dart';

/// Checks for an update and, if one's available, shows a confirmation
/// dialog -- called once from [SearchesScreen]'s `initState` (M23).
/// Injectable services for tests; both default to real instances.
Future<void> checkForUpdateAndMaybePrompt(BuildContext context, {UpdateCheckService checkService = const UpdateCheckService(), UpdateApplyService applyService = const UpdateApplyService()}) async {
  final result = await checkService.check();
  if (!result.updateAvailable || !context.mounted) {
    return;
  }
  await showDialog<void>(context: context, builder: (context) => _UpdateDialog(result: result, applyService: applyService));
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
  double? _progress;
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
        onProgress: (progress) {
          if (mounted) {
            setState(() => _progress = progress);
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
    return AlertDialog(
      title: Text(l10n.updateAvailableTitle(widget.result.tagName ?? '')),
      content: _updating
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [LinearProgressIndicator(value: _progress), const SizedBox(height: 12), Text(l10n.updateDownloadingMessage)],
            )
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if ((widget.result.releaseNotes ?? '').isNotEmpty) Text(widget.result.releaseNotes!),
                  if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
                ],
              ),
            ),
      actions: _updating
          ? const []
          : [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.updateLaterAction)), FilledButton(onPressed: _update, child: Text(l10n.updateNowAction))],
    );
  }
}
