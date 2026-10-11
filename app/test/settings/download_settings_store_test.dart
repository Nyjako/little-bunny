import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/settings/download_settings_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProviderPlatform extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  @override
  Future<String?> getDownloadsPath() async => '/fake/downloads';
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PathProviderPlatform.instance = _FakePathProviderPlatform();
  });

  test('loadDestinationFolder falls back to the OS downloads directory when nothing is saved', () async {
    const store = DownloadSettingsStore();

    expect(await store.loadDestinationFolder(), '/fake/downloads');
  });

  test('saveDestinationFolder then loadDestinationFolder round-trips the chosen folder', () async {
    const store = DownloadSettingsStore();
    await store.saveDestinationFolder('/home/someone/MyDownloads');

    expect(await store.loadDestinationFolder(), '/home/someone/MyDownloads');
  });

  test('loadAutoUpvoteOnDownload defaults to false (M14.2)', () async {
    const store = DownloadSettingsStore();

    expect(await store.loadAutoUpvoteOnDownload(), isFalse);
  });

  test('saveAutoUpvoteOnDownload then loadAutoUpvoteOnDownload round-trips (M14.2)', () async {
    const store = DownloadSettingsStore();
    await store.saveAutoUpvoteOnDownload(true);

    expect(await store.loadAutoUpvoteOnDownload(), isTrue);
  });
}
