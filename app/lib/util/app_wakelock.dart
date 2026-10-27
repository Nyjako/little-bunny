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
}
