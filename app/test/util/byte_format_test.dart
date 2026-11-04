import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/util/byte_format.dart';

void main() {
  group('formatBytesCompact', () {
    test('renders a sub-kilobyte count as plain bytes', () {
      expect(formatBytesCompact(0), '0 B');
      expect(formatBytesCompact(845), '845 B');
    });

    test('renders kilobytes with one decimal place', () {
      expect(formatBytesCompact(1024), '1.0 KB');
      expect(formatBytesCompact(1536), '1.5 KB');
    });

    test('renders megabytes', () {
      expect(formatBytesCompact(1024 * 1024 * 2), '2.0 MB');
    });

    test('renders gigabytes, the largest unit, without climbing further', () {
      expect(formatBytesCompact(1024 * 1024 * 1024), '1.0 GB');
      expect(formatBytesCompact(1024 * 1024 * 1024 * 5), '5.0 GB');
    });
  });
}
