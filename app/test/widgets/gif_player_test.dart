import 'dart:io';

import 'package:file/local.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/widgets/gif_player.dart';

import '../fakes/fake_cache_manager.dart';

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
}
