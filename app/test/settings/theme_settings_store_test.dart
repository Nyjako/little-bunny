import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/settings/theme_settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults to dark when nothing has been chosen yet', () async {
    const store = ThemeSettingsStore();

    expect(await store.load(), ThemeMode.dark);
  });

  test('save then load round-trips each ThemeMode', () async {
    const store = ThemeSettingsStore();

    for (final mode in ThemeMode.values) {
      await store.save(mode);
      expect(await store.load(), mode);
    }
  });
}
