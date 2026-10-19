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

  test('defaults to purple and AMOLED off when nothing has been chosen yet', () async {
    const store = ThemeSettingsStore();

    expect(await store.loadColor(), ThemeColorOption.purple);
    expect(await store.loadAmoled(), isFalse);
  });

  test('save then load round-trips each ThemeColorOption', () async {
    const store = ThemeSettingsStore();

    for (final color in ThemeColorOption.values) {
      await store.saveColor(color);
      expect(await store.loadColor(), color);
    }
  });

  test('save then load round-trips the AMOLED flag', () async {
    const store = ThemeSettingsStore();

    await store.saveAmoled(true);
    expect(await store.loadAmoled(), isTrue);

    await store.saveAmoled(false);
    expect(await store.loadAmoled(), isFalse);
  });
}
