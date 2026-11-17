import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/settings/writing_position_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('getPosition returns null when nothing is saved for that post', () async {
    const store = WritingPositionStore();

    expect(await store.getPosition(42), isNull);
  });

  test('savePosition then getPosition round-trips', () async {
    const store = WritingPositionStore();
    await store.savePosition(42, 0.37);

    expect(await store.getPosition(42), 0.37);
  });

  test('positions are tracked independently per post id', () async {
    const store = WritingPositionStore();
    await store.savePosition(1, 0.1);
    await store.savePosition(2, 0.9);

    expect(await store.getPosition(1), 0.1);
    expect(await store.getPosition(2), 0.9);
  });

  test('savePosition clamps an out-of-range fraction', () async {
    const store = WritingPositionStore();
    await store.savePosition(1, 1.5);
    await store.savePosition(2, -0.5);

    expect(await store.getPosition(1), 1.0);
    expect(await store.getPosition(2), 0.0);
  });

  test('a later savePosition for the same post overwrites the earlier one', () async {
    const store = WritingPositionStore();
    await store.savePosition(42, 0.2);
    await store.savePosition(42, 0.8);

    expect(await store.getPosition(42), 0.8);
  });
}
