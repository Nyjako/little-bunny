import 'package:little_bunny/services/download_queue_notifier.dart';

/// Records every call's arguments for assertion -- same pattern as
/// `fake_saf_platform.dart`'s `FakeSafStreamPlatform.writeFileBytesCalls`.
class FakeDownloadQueueNotifier implements DownloadQueueNotifier {
  final List<int> startingCalls = [];
  final List<(int done, int total)> progressCalls = [];
  final List<(int succeeded, int mismatched, int failed)> summaryCalls = [];
  int clearCallCount = 0;

  @override
  Future<void> showStarting({required int total}) async {
    startingCalls.add(total);
  }

  @override
  Future<void> showProgress({required int done, required int total}) async {
    progressCalls.add((done, total));
  }

  @override
  Future<void> showSummary({required int succeeded, required int mismatched, required int failed}) async {
    summaryCalls.add((succeeded, mismatched, failed));
  }

  @override
  Future<void> clear() async {
    clearCallCount++;
  }
}
