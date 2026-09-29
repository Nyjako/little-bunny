import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/screens/lock_setup_screen.dart';
import 'package:little_bunny/settings/app_lock_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_secret_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('enabling the lock requires matching PIN entries', (WidgetTester tester) async {
    final lockService = AppLockService(FakeSecretStore());

    await tester.pumpWidget(MaterialApp(home: LockSetupScreen(lockService: lockService)));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'New PIN/password'), '1234');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm'), '4321');
    await tester.tap(find.text('Enable app lock'));
    await tester.pumpAndSettle();

    expect(find.text('Entries do not match'), findsOneWidget);
    expect(await lockService.isEnabled(), isFalse);
  });

  testWidgets('enabling the lock with matching entries persists it', (WidgetTester tester) async {
    final lockService = AppLockService(FakeSecretStore());

    await tester.pumpWidget(MaterialApp(home: LockSetupScreen(lockService: lockService)));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'New PIN/password'), '1234');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm'), '1234');
    await tester.tap(find.text('Enable app lock'));
    await tester.pumpAndSettle();

    expect(await lockService.isEnabled(), isTrue);
    expect(await lockService.verify('1234'), isTrue);
    expect(find.text('App lock is currently on.'), findsOneWidget);
  });

  testWidgets('disabling requires the correct current PIN', (WidgetTester tester) async {
    final lockService = AppLockService(FakeSecretStore());
    await lockService.enable('1234');

    await tester.pumpWidget(MaterialApp(home: LockSetupScreen(lockService: lockService)));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Enter current PIN/password to disable'), '0000');
    await tester.tap(find.text('Disable app lock'));
    await tester.pumpAndSettle();

    expect(find.text('Incorrect PIN/password'), findsOneWidget);
    expect(await lockService.isEnabled(), isTrue);

    await tester.enterText(find.widgetWithText(TextField, 'Enter current PIN/password to disable'), '1234');
    await tester.tap(find.text('Disable app lock'));
    await tester.pumpAndSettle();

    expect(await lockService.isEnabled(), isFalse);
  });
}
