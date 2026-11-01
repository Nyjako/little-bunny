import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/settings/app_lock_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_secret_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('isEnabled is false before anything is configured', () async {
    final service = AppLockService(FakeSecretStore());

    expect(await service.isEnabled(), isFalse);
  });

  test('enable then verify accepts the correct secret and rejects a wrong one', () async {
    final service = AppLockService(FakeSecretStore());

    await service.enable('1234', mode: AppLockMode.password);

    expect(await service.isEnabled(), isTrue);
    expect(await service.verify('1234'), isTrue);
    expect(await service.verify('0000'), isFalse);
  });

  test('disable clears both the flag and the stored secret', () async {
    final service = AppLockService(FakeSecretStore());
    await service.enable('1234', mode: AppLockMode.password);

    await service.disable();

    expect(await service.isEnabled(), isFalse);
    expect(await service.verify('1234'), isFalse);
  });

  test('verify is false when nothing has ever been enabled', () async {
    final service = AppLockService(FakeSecretStore());

    expect(await service.verify('anything'), isFalse);
  });

  test('getMode/getPinLength default to password/4 before anything is enabled', () async {
    final service = AppLockService(FakeSecretStore());

    expect(await service.getMode(), AppLockMode.password);
    expect(await service.getPinLength(), 4);
  });

  test('enable with pin mode persists mode and pin length', () async {
    final service = AppLockService(FakeSecretStore());

    await service.enable('135790', mode: AppLockMode.pin, pinLength: 6);

    expect(await service.getMode(), AppLockMode.pin);
    expect(await service.getPinLength(), 6);
  });

  test('enable with password mode leaves pin length at its default', () async {
    final service = AppLockService(FakeSecretStore());

    await service.enable('hunter2', mode: AppLockMode.password);

    expect(await service.getMode(), AppLockMode.password);
    expect(await service.getPinLength(), 4);
  });

  test('disable resets mode and pin length back to defaults', () async {
    final service = AppLockService(FakeSecretStore());
    await service.enable('1234', mode: AppLockMode.pin, pinLength: 5);

    await service.disable();

    expect(await service.getMode(), AppLockMode.password);
    expect(await service.getPinLength(), 4);
  });
}
