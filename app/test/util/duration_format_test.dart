import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/util/duration_format.dart';

void main() {
  group('formatDurationCompact', () {
    test('zero duration', () {
      expect(formatDurationCompact(Duration.zero), '0s');
    });

    test('under a minute', () {
      expect(formatDurationCompact(const Duration(seconds: 45)), '45s');
      expect(formatDurationCompact(const Duration(seconds: 59)), '59s');
    });

    test('exactly a minute drops the trailing 0s', () {
      expect(formatDurationCompact(const Duration(seconds: 60)), '1m');
    });

    test('minutes and seconds', () {
      expect(formatDurationCompact(const Duration(seconds: 150)), '2m 30s');
    });

    test('exactly an hour drops seconds too', () {
      expect(formatDurationCompact(const Duration(seconds: 3600)), '1h 0m');
    });

    test('hours and minutes', () {
      expect(formatDurationCompact(const Duration(seconds: 3900)), '1h 5m');
    });
  });
}
