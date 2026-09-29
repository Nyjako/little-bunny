import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/bunny_repository_scope.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/screens/accounts_screen.dart';
import 'package:little_bunny/settings/app_lock_service.dart';

import '../fakes/fake_bunny_repository.dart';
import '../fakes/fake_secret_store.dart';

Widget _wrap(FakeBunnyRepository repository) => MaterialApp(home: BunnyRepositoryScope(repository: repository, child: AccountsScreen(lockService: AppLockService(FakeSecretStore()))));

void main() {
  testWidgets('shows "Not connected" for both sites when nothing is configured', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(FakeBunnyRepository()));
    await tester.pumpAndSettle();

    expect(find.text('e621'), findsOneWidget);
    expect(find.text('inkbunny'), findsOneWidget);
    expect(find.text('Not connected'), findsNWidgets(2));
  });

  testWidgets('shows the username and a remove action for a configured account', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    await repository.setAccount(BunnySite.e621, 'someuser', 'somesecret');

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    expect(find.text('Logged in as someuser'), findsOneWidget);
    expect(find.byIcon(Icons.delete), findsOneWidget);
  });

  testWidgets('tapping remove then confirming deletes the account', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    await repository.setAccount(BunnySite.e621, 'someuser', 'somesecret');

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete));
    await tester.pumpAndSettle();
    expect(find.text('Remove account?'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(repository.accounts.containsKey(BunnySite.e621), isFalse);
    expect(find.text('Not connected'), findsNWidgets(2));
  });

  testWidgets('tapping cancel in the remove dialog keeps the account', (WidgetTester tester) async {
    final repository = FakeBunnyRepository();
    await repository.setAccount(BunnySite.e621, 'someuser', 'somesecret');

    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repository.accounts.containsKey(BunnySite.e621), isTrue);
  });

  testWidgets('tapping an unconfigured site opens its login form', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(FakeBunnyRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('e621'));
    await tester.pumpAndSettle();

    expect(find.text('Log in to e621'), findsOneWidget);
  });
}
