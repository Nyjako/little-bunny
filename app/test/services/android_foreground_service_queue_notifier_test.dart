import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/services/android_foreground_service_queue_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('little_bunny/download_foreground_service');

  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('showProgress invokes updateProgress with done/total', () async {
    final notifier = AndroidForegroundServiceQueueNotifier(channel: channel);

    await notifier.showProgress(done: 3, total: 10);

    expect(calls, [isA<MethodCall>().having((c) => c.method, 'method', 'updateProgress').having((c) => c.arguments, 'arguments', {'done': 3, 'total': 10})]);
  });

  test('showSummary invokes showSummary with succeeded/mismatched/failed', () async {
    final notifier = AndroidForegroundServiceQueueNotifier(channel: channel);

    await notifier.showSummary(succeeded: 5, mismatched: 1, failed: 2);

    expect(calls, [
      isA<MethodCall>().having((c) => c.method, 'method', 'showSummary').having((c) => c.arguments, 'arguments', {'succeeded': 5, 'mismatched': 1, 'failed': 2}),
    ]);
  });

  test('clear invokes clear with no arguments', () async {
    final notifier = AndroidForegroundServiceQueueNotifier(channel: channel);

    await notifier.clear();

    expect(calls, [isA<MethodCall>().having((c) => c.method, 'method', 'clear')]);
  });

  test('a platform exception from any method is swallowed, not rethrown', () async {
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'boom');
    });
    final notifier = AndroidForegroundServiceQueueNotifier(channel: channel);

    await notifier.showProgress(done: 1, total: 1);
    await notifier.showSummary(succeeded: 1, mismatched: 0, failed: 0);
    await notifier.clear();
    // Reaching here without an uncaught exception is the assertion.
  });
}
