import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/screens/lock_screen.dart';
import 'package:little_bunny/settings/app_lock_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_secret_store.dart';

// Runs on the Linux/desktop test host, so Platform.isAndroid is false and
// LockScreen never attempts the biometric path here -- that's inherently
// untestable without a real device/platform channel (see
// docs/architecture.md's M7.4 notes). This only covers the PIN/password
// fallback, which every platform uses.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('entering the correct PIN calls onUnlocked', (WidgetTester tester) async {
    final lockService = AppLockService(FakeSecretStore());
    await lockService.enable('1234');
    var unlocked = false;

    await tester.pumpWidget(MaterialApp(home: LockScreen(lockService: lockService, onUnlocked: () => unlocked = true)));

    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(unlocked, isTrue);
  });

  testWidgets('entering the wrong PIN shows an error and does not unlock', (WidgetTester tester) async {
    final lockService = AppLockService(FakeSecretStore());
    await lockService.enable('1234');
    var unlocked = false;

    await tester.pumpWidget(MaterialApp(home: LockScreen(lockService: lockService, onUnlocked: () => unlocked = true)));

    await tester.enterText(find.byType(TextField), '0000');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(unlocked, isFalse);
    expect(find.text('Incorrect PIN/password'), findsOneWidget);
  });
}
