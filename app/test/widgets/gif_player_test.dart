import 'dart:io';

import 'package:file/local.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:little_bunny/widgets/gif_player.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../fakes/fake_cache_manager.dart';
import '../fakes/fake_path_provider.dart';
import '../fakes/test_app.dart';

/// Single-frame, 1x1 transparent GIF -- a well-known minimal valid GIF byte
/// sequence (used widely as a "tracking pixel" test fixture).
const _singleFrameGifBytes = [
  0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, //
  0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, //
  0x21, 0xF9, 0x04, 0x01, 0x00, 0x00, 0x00, 0x00, //
  0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, //
  0x02, 0x02, 0x44, 0x01, 0x00, //
  0x3B,
];

/// Same single-frame image descriptor/data block repeated twice (each
/// self-contained), making a crude but valid 2-frame animated GIF -- a
/// deliberately long 1-second-per-frame delay (GCE delay field = 100, in
/// 1/100s units) so the player's own frame-advance timer can't race the
/// test's own short real-time wait below and land on frame 2 before the
/// assertion runs (confirmed flaky at delay=0 under a loaded test run).
const _twoFrameGifBytes = [
  0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, //
  0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, //
  0x21, 0xF9, 0x04, 0x01, 0x64, 0x00, 0x00, 0x00, //
  0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, //
  0x02, 0x02, 0x44, 0x01, 0x00, //
  0x21, 0xF9, 0x04, 0x01, 0x64, 0x00, 0x00, 0x00, //
  0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, //
  0x02, 0x02, 0x44, 0x01, 0x00, //
  0x3B,
];

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('gif_player_test_');
    // Only exercised by the size-guard fallback's own preview Image, which
    // goes through CachedNetworkImage's flutter_cache_manager just like a
    // real post thumbnail would.
    PathProviderPlatform.instance = FakePathProviderPlatform();
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  FakeCacheManager fakeCacheManagerFor(List<int> bytes) {
    final file = File('${tempDir.path}/test.gif')..writeAsBytesSync(bytes);
    return FakeCacheManager(const LocalFileSystem().file(file.path));
  }

  // GifPlayer drives its own animation loop with a plain `Timer` (so the
  // GIF keeps looping once playing), which -- like any perpetually-
  // repeating animation -- `tester.pumpAndSettle()` can never settle past
  // (a well-known Flutter testing limitation, not specific to this widget:
  // https://docs.flutter.dev/cookbook/testing/widget/introduction notes the
  // same for any `AnimationController.repeat()`). A few bounded `pump()`
  // calls are enough to let the real (but now test-injected, synchronous)
  // decode resolve and the first frame render.
  testWidgets('decodes and shows a single-frame gif with no frame counter overlay', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(home: GifPlayer(imageUrl: 'https://example.invalid/single.gif', cacheManager: fakeCacheManagerFor(_singleFrameGifBytes))));
      // The codec decode this triggers is real async work -- has to start
      // inside runAsync's real zone to ever resolve under flutter_test, same
      // lesson as every other real-async case elsewhere in this app's own
      // tests. A short real delay (not tester.pump(), unreliable inside
      // runAsync) gives it room to finish before the next pump paints it.
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    expect(find.byType(RawImage), findsOneWidget);
    expect(find.textContaining('/'), findsNothing);
  });

  testWidgets('decodes and shows a 2-frame gif with a "1/2" frame counter overlay (M49)', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(home: GifPlayer(imageUrl: 'https://example.invalid/two.gif', cacheManager: fakeCacheManagerFor(_twoFrameGifBytes))));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    expect(find.byType(RawImage), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
  });

  group('size guard (M76)', () {
    testWidgets('a network gif over the limit shows the fallback with the preview, not the real gif -- Play anyway loads it', (WidgetTester tester) async {
      final client = MockClient((request) async {
        expect(request.method, 'HEAD');
        return http.Response('', 200, headers: {'content-length': '500'});
      });

      await tester.pumpWidget(
        wrapWithLocalization(
          GifPlayer(
            imageUrl: 'https://example.invalid/big.gif',
            previewUrl: 'https://example.invalid/big_preview.jpg',
            cacheManager: fakeCacheManagerFor(_singleFrameGifBytes),
            client: client,
            autoPlayMaxBytes: 100,
          ),
        ),
      );
      await tester.pump();

      // RawImage shows up either way here -- Image's own loading placeholder
      // (the preview, before its network fetch resolves) also renders one
      // internally -- so GifPlayer's real decoded frame is distinguished by
      // where it actually lives: nested in the FittedBox/SizedBox GifPlayer
      // itself wraps it in, which the preview Image is never part of.
      expect(find.descendant(of: find.byType(FittedBox), matching: find.byType(RawImage)), findsNothing);
      expect(find.byType(Image), findsOneWidget);
      expect(find.textContaining('500 B'), findsOneWidget);
      expect(find.byKey(const Key('gifPlayAnywayButton')), findsOneWidget);

      // tester.tap()'s gesture-arena resolution needs a pump() to actually
      // invoke onPressed, but pump() relies on the fake-async zone's own
      // clock -- mixing it with runAsync (needed so the real file read/
      // decode this kicks off can actually resolve) is unreliable. Invoking
      // onPressed directly sidesteps gesture recognition entirely, same
      // precedent as PostDetailScreen's own download-button tests.
      final playAnywayButton = tester.widget<FilledButton>(find.byKey(const Key('gifPlayAnywayButton')));
      await tester.runAsync(() async {
        playAnywayButton.onPressed!();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      expect(find.descendant(of: find.byType(FittedBox), matching: find.byType(RawImage)), findsOneWidget);
    });

    testWidgets('a network gif over the limit with no preview shows a plain placeholder instead', (WidgetTester tester) async {
      final client = MockClient((request) async => http.Response('', 200, headers: {'content-length': '500'}));

      await tester.pumpWidget(
        wrapWithLocalization(
          GifPlayer(imageUrl: 'https://example.invalid/big.gif', cacheManager: fakeCacheManagerFor(_singleFrameGifBytes), client: client, autoPlayMaxBytes: 100),
        ),
      );
      await tester.pump();

      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    });

    testWidgets('a network gif under the limit loads normally without ever showing the fallback', (WidgetTester tester) async {
      final client = MockClient((request) async => http.Response('', 200, headers: {'content-length': '10'}));

      await tester.runAsync(() async {
        await tester.pumpWidget(
          wrapWithLocalization(
            GifPlayer(imageUrl: 'https://example.invalid/small.gif', cacheManager: fakeCacheManagerFor(_singleFrameGifBytes), client: client, autoPlayMaxBytes: 100),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      expect(find.byKey(const Key('gifPlayAnywayButton')), findsNothing);
      expect(find.descendant(of: find.byType(FittedBox), matching: find.byType(RawImage)), findsOneWidget);
    });

    testWidgets('a local gif over the limit shows the fallback -- Play anyway reads the real file', (WidgetTester tester) async {
      final file = File('${tempDir.path}/local.gif')..writeAsBytesSync(_singleFrameGifBytes);

      await tester.runAsync(() async {
        await tester.pumpWidget(wrapWithLocalization(GifPlayer(imageUrl: '', localFilePath: file.path, autoPlayMaxBytes: 2)));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      expect(find.descendant(of: find.byType(FittedBox), matching: find.byType(RawImage)), findsNothing);
      expect(find.byKey(const Key('gifPlayAnywayButton')), findsOneWidget);

      // Same onPressed-direct-invocation reasoning as the network test above.
      final playAnywayButton = tester.widget<FilledButton>(find.byKey(const Key('gifPlayAnywayButton')));
      await tester.runAsync(() async {
        playAnywayButton.onPressed!();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      expect(find.descendant(of: find.byType(FittedBox), matching: find.byType(RawImage)), findsOneWidget);
    });

    testWidgets('a local gif under the limit loads normally without ever showing the fallback', (WidgetTester tester) async {
      final file = File('${tempDir.path}/local.gif')..writeAsBytesSync(_singleFrameGifBytes);

      await tester.runAsync(() async {
        await tester.pumpWidget(wrapWithLocalization(GifPlayer(imageUrl: '', localFilePath: file.path)));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      expect(find.byKey(const Key('gifPlayAnywayButton')), findsNothing);
      expect(find.descendant(of: find.byType(FittedBox), matching: find.byType(RawImage)), findsOneWidget);
    });
  });
}
