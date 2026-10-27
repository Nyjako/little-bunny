/// Reports [DownloadQueueService]'s progress through a local, on-device
/// notification -- never a server push (M43, renegotiated from the
/// roadmap's original "server-side queue + push" wording: downloads stay
/// entirely client-side per M42, and this app has no push-notification
/// backend at all). Kept as its own small interface, separate from
/// `flutter_local_notifications` itself, so [DownloadQueueService] can be
/// tested against a fake without touching a real platform channel -- same
/// reasoning as [DownloadManager]'s injectable `client`.
abstract class DownloadQueueNotifier {
  /// Called once, before the queue's first item is actually fetched --
  /// distinct from [showProgress] (which only ever fires *after* an item
  /// finishes) so the Android foreground service (M57) gets a chance to
  /// call `startForeground()` before the first HTTP request, not after it.
  /// Without this, locking the screen right after enqueueing could kill the
  /// process before anything ever told the service to start.
  Future<void> showStarting({required int total});

  Future<void> showProgress({required int done, required int total});

  Future<void> showSummary({required int succeeded, required int mismatched, required int failed});

  Future<void> clear();
}

/// Default/fallback notifier -- used when a real one hasn't been wired up
/// (e.g. in tests that don't care about notifications at all).
class NoopDownloadQueueNotifier implements DownloadQueueNotifier {
  const NoopDownloadQueueNotifier();

  @override
  Future<void> showStarting({required int total}) async {}

  @override
  Future<void> showProgress({required int done, required int total}) async {}

  @override
  Future<void> showSummary({required int succeeded, required int mismatched, required int failed}) async {}

  @override
  Future<void> clear() async {}
}
