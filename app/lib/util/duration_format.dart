/// Compact, human-readable rendering of [duration] for notification text --
/// e.g. '45s', '2m 30s', '1h 5m'. Deliberately terse (no "hours"/"minutes"
/// words) to match this app's existing minimalist notification body text
/// ('$done of $total').
String formatDurationCompact(Duration duration) {
  final totalSeconds = duration.inSeconds;
  if (totalSeconds < 60) {
    return '${totalSeconds}s';
  }
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '${hours}h ${minutes}m';
  }
  return seconds > 0 ? '${minutes}m ${seconds}s' : '${minutes}m';
}
