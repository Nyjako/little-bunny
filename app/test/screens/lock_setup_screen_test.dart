import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/screens/lock_setup_screen.dart';
import 'package:little_bunny/settings/app_lock_service.dart';
import 'package:little_bunny/widgets/pin_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_secret_store.dart';
import '../fakes/test_app.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> tapDigits(WidgetTester tester, Finder pinEntry, String digits) async {
    for (final digit in digits.split('')) {
      await tester.tap(find.descendant(of: pinEntry, matching: find.byKey(ValueKey('pinDigit$digit'))));
      await tester.pump();
    }
  }

  // The PIN flows stack a mode picker, a length picker, and up to two full
  // keypads (dots + 4 rows of digit buttons each) -- taller than the default
  // 600px test surface. A bigger surface avoids every PIN-mode test needing
  // its own scroll-into-view choreography, same reasoning as other tests in
  // this codebase that resize the test view (e.g. post_grid_screen_test.dart's
  // "app bar shrinks on wide windows").
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('enabling the lock requires matching passwords', (WidgetTester tester) async {
    final lockService = AppLockService(FakeSecretStore());

    await tester.pumpWidget(wrapWithLocalization(LockSetupScreen(lockService: lockService)));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'New password'), '1234');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm'), '4321');
    await tester.tap(find.text('Enable app lock'));
    await tester.pumpAndSettle();

    expect(find.text('Entries do not match'), findsOneWidget);
    expect(await lockService.isEnabled(), isFalse);
  });

  testWidgets('enabling the lock with matching passwords persists it', (WidgetTester tester) async {
    final lockService = AppLockService(FakeSecretStore());

    await tester.pumpWidget(wrapWithLocalization(LockSetupScreen(lockService: lockService)));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'New password'), '1234');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm'), '1234');
    await tester.tap(find.text('Enable app lock'));
    await tester.pumpAndSettle();

    expect(await lockService.isEnabled(), isTrue);
    expect(await lockService.getMode(), AppLockMode.password);
    expect(await lockService.verify('1234'), isTrue);
    expect(find.text('App lock is currently on.'), findsOneWidget);
  });

  testWidgets('disabling requires the correct current password', (WidgetTester tester) async {
    final lockService = AppLockService(FakeSecretStore());
    await lockService.enable('1234', mode: AppLockMode.password);

    await tester.pumpWidget(wrapWithLocalization(LockSetupScreen(lockService: lockService)));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Enter current password to disable'), '0000');
    await tester.tap(find.text('Disable app lock'));
    await tester.pumpAndSettle();

    expect(find.text('Incorrect PIN or password'), findsOneWidget);
    expect(await lockService.isEnabled(), isTrue);

    await tester.enterText(find.widgetWithText(TextField, 'Enter current password to disable'), '1234');
    await tester.tap(find.text('Disable app lock'));
    await tester.pumpAndSettle();

    expect(await lockService.isEnabled(), isFalse);
  });

  testWidgets('selecting PIN mode reveals the length picker and two PIN entries, hides the password fields', (WidgetTester tester) async {
    useTallSurface(tester);
    final lockService = AppLockService(FakeSecretStore());

    await tester.pumpWidget(wrapWithLocalization(LockSetupScreen(lockService: lockService)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('PIN'));
    await tester.pumpAndSettle();

    expect(find.text('PIN length'), findsOneWidget);
    expect(find.byType(PinEntry), findsNWidgets(2));
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('changing PIN length after partial entry clears both PIN values', (WidgetTester tester) async {
    useTallSurface(tester);
    final lockService = AppLockService(FakeSecretStore());

    await tester.pumpWidget(wrapWithLocalization(LockSetupScreen(lockService: lockService)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PIN'));
    await tester.pumpAndSettle();

    final newPinEntry = find.byType(PinEntry).first;
    await tapDigits(tester, newPinEntry, '12');

    await tester.tap(find.descendant(of: find.byType(SegmentedButton<int>), matching: find.text('6')));
    await tester.pumpAndSettle();

    final newPinWidget = tester.widget<PinEntry>(find.byType(PinEntry).first);
    expect(newPinWidget.value, isEmpty);
  });

  testWidgets('matching new/confirm PIN at the configured length auto-enables, no button tap', (WidgetTester tester) async {
    useTallSurface(tester);
    final lockService = AppLockService(FakeSecretStore());

    await tester.pumpWidget(wrapWithLocalization(LockSetupScreen(lockService: lockService)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PIN'));
    await tester.pumpAndSettle();

    final pinEntries = find.byType(PinEntry);
    await tapDigits(tester, pinEntries.at(0), '1357');
    await tapDigits(tester, pinEntries.at(1), '1357');
    await tester.pumpAndSettle();

    expect(await lockService.isEnabled(), isTrue);
    expect(await lockService.getMode(), AppLockMode.pin);
    expect(await lockService.getPinLength(), 4);
    expect(await lockService.verify('1357'), isTrue);
    expect(find.text('App lock is currently on.'), findsOneWidget);
  });

  testWidgets('mismatched PIN at matching length shows an error and clears only the confirm entry', (WidgetTester tester) async {
    useTallSurface(tester);
    final lockService = AppLockService(FakeSecretStore());

    await tester.pumpWidget(wrapWithLocalization(LockSetupScreen(lockService: lockService)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PIN'));
    await tester.pumpAndSettle();

    final pinEntries = find.byType(PinEntry);
    await tapDigits(tester, pinEntries.at(0), '1357');
    await tapDigits(tester, pinEntries.at(1), '2468');
    await tester.pumpAndSettle();

    expect(find.text('Entries do not match'), findsOneWidget);
    expect(await lockService.isEnabled(), isFalse);
    final newPinWidget = tester.widget<PinEntry>(find.byType(PinEntry).first);
    expect(newPinWidget.value, '1357');
    final confirmPinWidget = tester.widget<PinEntry>(find.byType(PinEntry).at(1));
    expect(confirmPinWidget.value, isEmpty);
  });

  testWidgets('PIN disable flow: wrong PIN at full length shows an error without a tap', (WidgetTester tester) async {
    useTallSurface(tester);
    final lockService = AppLockService(FakeSecretStore());
    await lockService.enable('1357', mode: AppLockMode.pin, pinLength: 4);

    await tester.pumpWidget(wrapWithLocalization(LockSetupScreen(lockService: lockService)));
    await tester.pumpAndSettle();

    expect(find.text('Enter current PIN to disable'), findsOneWidget);
    await tapDigits(tester, find.byType(PinEntry), '0000');
    await tester.pumpAndSettle();

    expect(find.text('Incorrect PIN or password'), findsOneWidget);
    expect(await lockService.isEnabled(), isTrue);
  });

  testWidgets('PIN disable flow: correct PIN at full length auto-disables without a tap', (WidgetTester tester) async {
    useTallSurface(tester);
    final lockService = AppLockService(FakeSecretStore());
    await lockService.enable('1357', mode: AppLockMode.pin, pinLength: 4);

    await tester.pumpWidget(wrapWithLocalization(LockSetupScreen(lockService: lockService)));
    await tester.pumpAndSettle();

    await tapDigits(tester, find.byType(PinEntry), '1357');
    await tester.pumpAndSettle();

    expect(await lockService.isEnabled(), isFalse);
  });
}
