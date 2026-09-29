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

    await service.enable('1234');

    expect(await service.isEnabled(), isTrue);
    expect(await service.verify('1234'), isTrue);
    expect(await service.verify('0000'), isFalse);
  });

  test('disable clears both the flag and the stored secret', () async {
    final service = AppLockService(FakeSecretStore());
    await service.enable('1234');

    await service.disable();

    expect(await service.isEnabled(), isFalse);
    expect(await service.verify('1234'), isFalse);
  });

  test('verify is false when nothing has ever been enabled', () async {
    final service = AppLockService(FakeSecretStore());

    expect(await service.verify('anything'), isFalse);
  });
}
