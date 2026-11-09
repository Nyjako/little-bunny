import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Thin reference-counted wrapper around [WakelockPlus.enable]/[disable] --
/// those are a flat on/off toggle, not a counter, so two independent
/// features holding it at once (M47's [PostDetailScreen] viewing a post,
/// the download queue processing in the background) would otherwise turn
/// it off out from under each other the moment either one releases it.
class AppWakelock {
  static int _count = 0;

  static Future<void> acquire() async {
    if (_count++ == 0) {
      await WakelockPlus.enable();
    }
  }

  static Future<void> release() async {
    if (--_count <= 0) {
      _count = 0;
      await WakelockPlus.disable();
    }
  }

  /// Zeroes the reference count between tests. [_count] otherwise survives
  /// for as long as the test file's isolate does -- if a test throws (or
  /// times out) before its own cleanup tail runs [release], the leaked
  /// `acquire` permanently wedges the count above zero, silently turning
  /// every later test's [acquire] into a no-op for the rest of that file's
  /// run (same leaked-global-singleton shape `download_queue_service_test.dart`
  /// already hit once with the old `PathProviderPlatform.instance`-reading
  /// persistence path, fixed there by making sure every test drains before
  /// ending -- this covers the case where a test *doesn't* get that far).
  @visibleForTesting
  static void resetForTesting() => _count = 0;
}
