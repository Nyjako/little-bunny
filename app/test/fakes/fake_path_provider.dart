import 'dart:io';

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

  /// Backs `RepositorySettingsStore`'s standalone db path resolution (M15's
  /// Settings Connection section loads the persisted config, which touches
  /// this for a standalone config even when the FFI repository itself is a
  /// fake and never actually opens the path).
  @override
  Future<String?> getApplicationSupportPath() async => '/fake/support';

  /// Backs `UpdateApplyService`'s download/extract staging directory (M23)
  /// -- a real temp dir on the actual host filesystem (not a bare string
  /// like the two fakes above), since tests here genuinely write/read
  /// files through it.
  @override
  Future<String?> getTemporaryPath() async => Directory.systemTemp.createTempSync('bunny_test_').path;
}
