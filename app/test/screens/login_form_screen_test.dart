import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/screens/login_form_screen.dart';

import '../fakes/fake_bunny_repository.dart';
import '../fakes/test_app.dart';

void main() {
  testWidgets('e621 form has a username and API key field, then saves on success', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    bool? popped;

    await tester.pumpWidget(
      wrapWithLocalization(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              popped = await Navigator.push<bool>(context, MaterialPageRoute(builder: (context) => LoginFormScreen(site: BunnySite.e621, repository: repository)));
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('API key'), findsOneWidget);
    expect(find.text('Password'), findsNothing);

    await tester.enterText(find.widgetWithText(TextFormField, 'Username'), 'someuser');
    await tester.enterText(find.widgetWithText(TextFormField, 'API key'), 'somekey');
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    expect(popped, isTrue);
    expect(repository.accounts[BunnySite.e621]?.username, 'someuser');
  });

  testWidgets('inkbunny form obscures the password field', (WidgetTester tester) async {
    await tester.pumpWidget(wrapWithLocalization(LoginFormScreen(site: BunnySite.inkbunny, repository: FakeBunnyRepository())));

    expect(find.text('Password'), findsOneWidget);
    final field = tester.widget<TextField>(find.descendant(of: find.widgetWithText(TextFormField, 'Password'), matching: find.byType(TextField)));
    expect(field.obscureText, isTrue);
  });

  testWidgets('shows an inline error and does not save when verification fails', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    repository.verifyFailures[BunnySite.e621] = 'an e621/Inkbunny client call failed (network, auth, ...)';

    await tester.pumpWidget(wrapWithLocalization(LoginFormScreen(site: BunnySite.e621, repository: repository)));

    await tester.enterText(find.widgetWithText(TextFormField, 'Username'), 'someuser');
    await tester.enterText(find.widgetWithText(TextFormField, 'API key'), 'wrongkey');
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    expect(find.text('an e621/Inkbunny client call failed (network, auth, ...)'), findsOneWidget);
    expect(repository.accounts.containsKey(BunnySite.e621), isFalse);
  });

  testWidgets('validates required fields before submitting', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();

    await tester.pumpWidget(wrapWithLocalization(LoginFormScreen(site: BunnySite.e621, repository: repository)));

    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    expect(find.text('Required'), findsNWidgets(2));
    expect(repository.accounts.containsKey(BunnySite.e621), isFalse);
  });
}
