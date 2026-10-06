import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/util/media_type.dart';

void main() {
  group('isVideoExt', () {
    test('matches webm and mp4', () {
      expect(isVideoExt('webm'), isTrue);
      expect(isVideoExt('mp4'), isTrue);
    });

    test('is case-insensitive', () {
      expect(isVideoExt('MP4'), isTrue);
    });

    test('rejects an image extension', () {
      expect(isVideoExt('jpg'), isFalse);
      expect(isVideoExt('gif'), isFalse);
    });

    test('rejects null', () {
      expect(isVideoExt(null), isFalse);
    });
  });

  group('isGifExt', () {
    test('matches gif', () {
      expect(isGifExt('gif'), isTrue);
    });

    test('is case-insensitive', () {
      expect(isGifExt('GIF'), isTrue);
    });

    test('rejects a non-gif extension', () {
      expect(isGifExt('png'), isFalse);
      expect(isGifExt('webm'), isFalse);
    });

    test('rejects null', () {
      expect(isGifExt(null), isFalse);
    });
  });
}
