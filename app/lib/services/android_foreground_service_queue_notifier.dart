import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../util/duration_format.dart';
import 'download_queue_notifier.dart';

const _channelName = 'little_bunny/download_foreground_service';

/// Real [DownloadQueueNotifier] for Android (M57): backs the exact same
/// "Downloads" notification [FlutterLocalNotificationsQueueNotifier] shows
/// on every other platform, but posted from a native foreground `Service`
/// (app/android/.../DownloadForegroundService.kt) instead of directly from
/// Dart -- a foreground service is the only thing that reliably stops
/// Android from killing the whole process once the screen locks (the
/// Activity backgrounding on its own buys nothing). [DownloadQueueService]
/// is completely unaware this exists; it just sees a [DownloadQueueNotifier]
/// like any other. Every method swallows its own exceptions, same reasoning
/// as [FlutterLocalNotificationsQueueNotifier] -- a broken platform channel
/// must never affect the queue's own control flow.
class AndroidForegroundServiceQueueNotifier implements DownloadQueueNotifier {
  final MethodChannel _channel;

  /// Set by `main.dart`, same shape as [FlutterLocalNotificationsQueueNotifier
  /// .onResumeRequested] -- called whenever the "Resume" notification action
  /// (M65) lands, whether pushed live via [_handleMethodCall] (the Activity
  /// was already running) or discovered by [checkPendingResumeRequest]'s own
  /// startup poll (a fresh launch, where MainActivity.kt can't safely push
  /// before this class has even registered its handler below).
  void Function()? onResumeRequested;

  AndroidForegroundServiceQueueNotifier({MethodChannel? channel}) : _channel = channel ?? const MethodChannel(_channelName) {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'resumeRequested') {
      onResumeRequested?.call();
    }
  }

  /// Call once at startup, after [onResumeRequested] is set -- covers a
  /// "Resume" tap that launched a fresh engine (MainActivity.kt stores it
  /// rather than pushing immediately, since Dart's own handler above isn't
  /// guaranteed to be registered yet at that point). A no-op (false) on
  /// every other platform/launch path.
  Future<void> checkPendingResumeRequest() async {
    try {
      final pending = await _channel.invokeMethod<bool>('checkPendingResumeRequest') ?? false;
      if (pending) {
        onResumeRequested?.call();
      }
    } catch (e) {
      debugPrint('AndroidForegroundServiceQueueNotifier.checkPendingResumeRequest failed: $e');
    }
  }

  @override
  Future<void> showStarting({required int total}) async {
    try {
      await _channel.invokeMethod('startQueue', {'total': total});
    } catch (e) {
      debugPrint('AndroidForegroundServiceQueueNotifier.showStarting failed: $e');
    }
  }

  @override
  Future<void> showProgress({required int done, required int total, required int failed, Duration? eta}) async {
    try {
      await _channel.invokeMethod('updateProgress', {'done': done, 'total': total, 'failed': failed, 'etaText': eta != null ? formatDurationCompact(eta) : null});
    } catch (e) {
      debugPrint('AndroidForegroundServiceQueueNotifier.showProgress failed: $e');
    }
  }

  @override
  Future<void> showSummary({required int succeeded, required int mismatched, required int failed}) async {
    try {
      await _channel.invokeMethod('showSummary', {'succeeded': succeeded, 'mismatched': mismatched, 'failed': failed});
    } catch (e) {
      debugPrint('AndroidForegroundServiceQueueNotifier.showSummary failed: $e');
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _channel.invokeMethod('clear');
    } catch (e) {
      debugPrint('AndroidForegroundServiceQueueNotifier.clear failed: $e');
    }
  }
}
