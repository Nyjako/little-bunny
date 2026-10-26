import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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

  AndroidForegroundServiceQueueNotifier({MethodChannel? channel}) : _channel = channel ?? const MethodChannel(_channelName);

  @override
  Future<void> showProgress({required int done, required int total}) async {
    try {
      await _channel.invokeMethod('updateProgress', {'done': done, 'total': total});
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
