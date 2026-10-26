import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'download_queue_notifier.dart';

/// A fixed, reused id for every call -- `flutter_local_notifications` treats
/// the same id as "update this notification in place," which is exactly
/// what gives live-updating progress (as more items get queued mid-flight)
/// for free, with no extra bookkeeping needed here.
const _notificationId = 424300;

const _channelId = 'download_queue';
const _channelName = 'Downloads';

/// GUID for Windows toast activation callbacks -- must stay stable across
/// releases (regenerating it would orphan any notification Windows still
/// has a reference to), so it's hardcoded rather than generated at runtime.
const _windowsGuid = '9a3f5cf1-851e-4f11-ab69-e6dc3cd884b3';

/// Real implementation of [DownloadQueueNotifier], wrapping
/// `flutter_local_notifications`. Every method swallows its own exceptions
/// (missing permission, unsupported platform, plugin not initialized,
/// anything else) and only logs via [debugPrint] -- a broken or denied
/// notification must never affect [DownloadQueueService]'s own control flow,
/// since the actual download work has nothing to do with whether the user
/// can see a notification about it.
class FlutterLocalNotificationsQueueNotifier implements DownloadQueueNotifier {
  final FlutterLocalNotificationsPlugin _plugin;

  FlutterLocalNotificationsQueueNotifier({FlutterLocalNotificationsPlugin? plugin}) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// Best-effort setup -- called once from `main()`. Failures here (and in
  /// every other method of this class) are swallowed rather than thrown,
  /// so a platform this package doesn't support, or a user who denies the
  /// permission prompt, never breaks anything beyond not showing a
  /// notification.
  Future<void> initialize() async {
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
          macOS: DarwinInitializationSettings(),
          linux: LinuxInitializationSettings(defaultActionName: 'Open'),
          windows: WindowsInitializationSettings(appName: 'Little Bunny', appUserModelId: 'com.github.nyjako.little_bunny', guid: _windowsGuid),
        ),
      );
      if (Platform.isAndroid) {
        await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      }
    } catch (e) {
      debugPrint('FlutterLocalNotificationsQueueNotifier.initialize failed: $e');
    }
  }

  NotificationDetails _details({bool showProgress = false, int maxProgress = 0, int progress = 0}) => NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: showProgress,
      onlyAlertOnce: true,
      showProgress: showProgress,
      maxProgress: maxProgress,
      progress: progress,
    ),
  );

  @override
  Future<void> showProgress({required int done, required int total}) async {
    try {
      await _plugin.show(
        id: _notificationId,
        title: 'Downloading',
        body: '$done of $total',
        notificationDetails: _details(showProgress: true, maxProgress: total, progress: done),
      );
    } catch (e) {
      debugPrint('FlutterLocalNotificationsQueueNotifier.showProgress failed: $e');
    }
  }

  @override
  Future<void> showSummary({required int succeeded, required int mismatched, required int failed}) async {
    try {
      await _plugin.show(
        id: _notificationId,
        title: 'Downloads finished',
        body: '$succeeded downloaded, $mismatched checksum mismatch, $failed failed',
        notificationDetails: _details(),
      );
    } catch (e) {
      debugPrint('FlutterLocalNotificationsQueueNotifier.showSummary failed: $e');
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _plugin.cancel(id: _notificationId);
    } catch (e) {
      debugPrint('FlutterLocalNotificationsQueueNotifier.clear failed: $e');
    }
  }
}
