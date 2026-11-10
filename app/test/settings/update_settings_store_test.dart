import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/settings/update_settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('loadAutoCheckEnabled defaults to true when nothing is saved', () async {
    const store = UpdateSettingsStore();

    expect(await store.loadAutoCheckEnabled(), isTrue);
  });

  test('saveAutoCheckEnabled then loadAutoCheckEnabled round-trips', () async {
    const store = UpdateSettingsStore();
    await store.saveAutoCheckEnabled(false);

    expect(await store.loadAutoCheckEnabled(), isFalse);

    await store.saveAutoCheckEnabled(true);

    expect(await store.loadAutoCheckEnabled(), isTrue);
  });
}
