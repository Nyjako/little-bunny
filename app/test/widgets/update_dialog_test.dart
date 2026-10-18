import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:little_bunny/services/update_apply_service.dart';
import 'package:little_bunny/services/update_check_service.dart';
import 'package:little_bunny/widgets/update_dialog.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../fakes/fake_path_provider.dart';
import '../fakes/test_app.dart';

void main() {
  setUp(() {
    PathProviderPlatform.instance = FakePathProviderPlatform();
  });

  // All of these intentionally never reach a *successful* desktop apply --
  // UpdateApplyService calls exit(0) on success (Linux/macOS/Windows, see
  // its own doc comment), which would kill the test process outright. Every
  // scenario here either finds no update at all, or drives the apply
  // service's download step to fail (a 404/network error, never a real
  // archive to extract), so the failure path is reached well before any
  // platform-specific apply/exit code ever runs.

  Widget wrapWithTrigger(UpdateCheckService checkService, {UpdateApplyService? applyService}) => wrapWithLocalization(
    Builder(
      builder: (context) => ElevatedButton(
        onPressed: () => checkForUpdateAndMaybePrompt(context, checkService: checkService, applyService: applyService ?? const UpdateApplyService()),
        child: const Text('check'),
      ),
    ),
  );

  testWidgets('shows no dialog when no update is available', (tester) async {
    final checkService = UpdateCheckService(client: MockClient((_) async => http.Response('{"tag_name":"build-0","assets":[]}', 200)));

    await tester.pumpWidget(wrapWithTrigger(checkService));
    await tester.tap(find.text('check'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('shows the release tag and notes when an update is available', (tester) async {
    final assetSuffix = UpdateCheckService.assetSuffixForPlatform();
    final checkService = UpdateCheckService(
      client: MockClient(
        (_) async => http.Response('{"tag_name":"build-42","body":"Fixed things","assets":[{"name":"little-bunny-$assetSuffix","browser_download_url":"https://example.invalid/asset"}]}', 200),
      ),
    );

    await tester.pumpWidget(wrapWithTrigger(checkService));
    await tester.tap(find.text('check'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('build-42'), findsOneWidget);
    expect(find.text('Fixed things'), findsOneWidget);
  });

  testWidgets('"Later" dismisses the dialog without downloading', (tester) async {
    final assetSuffix = UpdateCheckService.assetSuffixForPlatform();
    final checkService = UpdateCheckService(
      client: MockClient((_) async => http.Response('{"tag_name":"build-42","assets":[{"name":"little-bunny-$assetSuffix","browser_download_url":"https://example.invalid/asset"}]}', 200)),
    );
    var downloadAttempted = false;
    final applyService = UpdateApplyService(
      client: MockClient((_) async {
        downloadAttempted = true;
        return http.Response('', 404);
      }),
    );

    await tester.pumpWidget(wrapWithTrigger(checkService, applyService: applyService));
    await tester.tap(find.text('check'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(downloadAttempted, isFalse);
  });

  testWidgets('tapping "Update" and having the download fail shows an error and keeps the dialog open', (tester) async {
    final assetSuffix = UpdateCheckService.assetSuffixForPlatform();
    final checkService = UpdateCheckService(
      client: MockClient((_) async => http.Response('{"tag_name":"build-42","assets":[{"name":"little-bunny-$assetSuffix","browser_download_url":"https://example.invalid/asset"}]}', 200)),
    );
    final applyService = UpdateApplyService(client: MockClient((_) async => http.Response('', 404)));

    await tester.pumpWidget(wrapWithTrigger(checkService, applyService: applyService));
    await tester.tap(find.text('check'));
    await tester.pumpAndSettle();

    // Not pumpAndSettle -- the dialog's indeterminate LinearProgressIndicator
    // (shown while _updating is true) animates forever by design, which
    // pumpAndSettle treats as "never settles" and times out on. A couple of
    // explicit pumps is enough: one for the tap's setState (_updating ->
    // true), one more for the awaited mock HTTP call's continuation
    // (_updating -> false, _error set) to run.
    await tester.tap(find.text('Update'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Later'), findsOneWidget); // actions came back once _updating flipped false again
    expect(find.text('Update'), findsOneWidget);
  });
}
