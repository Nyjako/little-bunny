import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:little_bunny/screens/about_screen.dart';
import 'package:little_bunny/services/update_check_service.dart';

import '../fakes/test_app.dart';

void main() {
  testWidgets('tapping "Check for app update" shows the update dialog when one is available', (WidgetTester tester) async {
    final assetSuffix = UpdateCheckService.assetSuffixForPlatform();
    final checkService = UpdateCheckService(
      currentBuildNumber: 10,
      client: MockClient((_) async => http.Response('{"tag_name":"build-42","assets":[{"name":"little-bunny-$assetSuffix","browser_download_url":"https://example.invalid/asset"}]}', 200)),
    );

    await tester.pumpWidget(wrapWithLocalization(AboutScreen(updateCheckService: checkService)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Check for app update'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('build-42'), findsOneWidget);
    expect(find.text('No update available'), findsNothing);
  });

  testWidgets('tapping "Check for app update" shows a snackbar when none is available', (WidgetTester tester) async {
    final checkService = UpdateCheckService(currentBuildNumber: 10, client: MockClient((_) async => http.Response('{"tag_name":"build-0","assets":[]}', 200)));

    await tester.pumpWidget(wrapWithLocalization(AboutScreen(updateCheckService: checkService)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Check for app update'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('No update available'), findsOneWidget);
  });
}
