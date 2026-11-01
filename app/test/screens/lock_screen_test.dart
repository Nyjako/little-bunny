import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/screens/lock_screen.dart';
import 'package:little_bunny/settings/app_lock_service.dart';
import 'package:little_bunny/widgets/pin_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_secret_store.dart';
import '../fakes/test_app.dart';

// Runs on the Linux/desktop test host, so Platform.isAndroid is false and
// LockScreen never attempts the biometric path here -- that's inherently
// untestable without a real device/platform channel (see
// docs/architecture.md's M7.4 notes). This only covers the PIN/password
// fallback, which every platform uses.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> tapDigits(WidgetTester tester, String digits) async {
    for (final digit in digits.split('')) {
      await tester.tap(find.byKey(ValueKey('pinDigit$digit')));
      await tester.pump();
    }
  }

  testWidgets('entering the correct password calls onUnlocked', (WidgetTester tester) async {
    final lockService = AppLockService(FakeSecretStore());
    await lockService.enable('1234', mode: AppLockMode.password);
    var unlocked = false;

    await tester.pumpWidget(wrapWithLocalization(LockScreen(lockService: lockService, onUnlocked: () => unlocked = true)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(unlocked, isTrue);
  });

  testWidgets('entering the wrong password shows an error and does not unlock', (WidgetTester tester) async {
    final lockService = AppLockService(FakeSecretStore());
    await lockService.enable('1234', mode: AppLockMode.password);
    var unlocked = false;

    await tester.pumpWidget(wrapWithLocalization(LockScreen(lockService: lockService, onUnlocked: () => unlocked = true)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '0000');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(unlocked, isFalse);
    expect(find.text('Incorrect PIN or password'), findsOneWidget);
  });

  testWidgets('a loading state shows before the lock mode resolves', (WidgetTester tester) async {
    final lockService = AppLockService(FakeSecretStore());
    await lockService.enable('1234', mode: AppLockMode.password);

    await tester.pumpWidget(wrapWithLocalization(LockScreen(lockService: lockService, onUnlocked: () {})));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('PIN mode auto-unlocks once the configured length is entered, with no button', (WidgetTester tester) async {
    final lockService = AppLockService(FakeSecretStore());
    await lockService.enable('1234', mode: AppLockMode.pin, pinLength: 4);
    var unlocked = false;

    await tester.pumpWidget(wrapWithLocalization(LockScreen(lockService: lockService, onUnlocked: () => unlocked = true)));
    await tester.pumpAndSettle();

    expect(find.byType(PinEntry), findsOneWidget);
    expect(find.text('Unlock'), findsNothing);

    await tapDigits(tester, '123');
    expect(unlocked, isFalse);
    await tapDigits(tester, '4');
    await tester.pumpAndSettle();

    expect(unlocked, isTrue);
  });

  testWidgets('PIN mode clears entry and shows an error on a wrong PIN', (WidgetTester tester) async {
    final lockService = AppLockService(FakeSecretStore());
    await lockService.enable('1234', mode: AppLockMode.pin, pinLength: 4);
    var unlocked = false;

    await tester.pumpWidget(wrapWithLocalization(LockScreen(lockService: lockService, onUnlocked: () => unlocked = true)));
    await tester.pumpAndSettle();

    await tapDigits(tester, '0000');
    await tester.pumpAndSettle();

    expect(unlocked, isFalse);
    expect(find.text('Incorrect PIN or password'), findsOneWidget);
  });
}
