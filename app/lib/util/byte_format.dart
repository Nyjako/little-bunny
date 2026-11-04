/// Compact, human-readable rendering of a byte count (M62) -- e.g. '845 B',
/// '2.3 MB', '1.1 GB'. Same terse style as [formatDurationCompact], used for
/// the download queue's per-file byte progress.
String formatBytesCompact(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  const units = ['KB', 'MB', 'GB'];
  var value = bytes / 1024;
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  return '${value.toStringAsFixed(1)} ${units[unitIndex]}';
}
