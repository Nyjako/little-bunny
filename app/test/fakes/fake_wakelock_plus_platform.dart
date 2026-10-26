import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

/// `flutter test` has no real platform channel implementation for
/// `wakelock_plus` -- the default `MethodChannelWakelockPlus` throws
/// (observed concretely inside `tester.runAsync`, where the real zone lets
/// the exception actually surface instead of being swallowed), so any test
/// that reaches `PostDetailScreen`'s `WakelockPlus.enable/disable` calls
/// needs this registered first. No-op, since the real OS-level wakelock
/// behavior isn't something a widget test can observe anyway.
class FakeWakelockPlusPlatform extends WakelockPlusPlatformInterface {
  bool enabledValue = false;

  @override
  Future<void> toggle({required bool enable}) async {
    enabledValue = enable;
  }

  @override
  Future<bool> get enabled async => enabledValue;
}
