import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Minimal fake for widget tests that reach `SettingsScreen`'s downloads
/// section (M9.4) -- `path_provider`'s real `getDownloadsPath` throws
/// `UnsupportedError` outside macOS/the host platforms it has a native
/// implementation for, which real test runs (Linux CI, this environment)
/// would otherwise hit whenever `DownloadSettingsStore.loadDestinationFolder`
/// falls back to it.
class FakePathProviderPlatform extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  @override
  Future<String?> getDownloadsPath() async => '/fake/downloads';
}
