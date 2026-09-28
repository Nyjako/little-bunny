import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/repository/bunny_models.dart';

void main() {
  group('BunnySite wire string', () {
    test('round-trips e621', () {
      expect(BunnySite.e621.toWireString(), 'e621');
      expect(BunnySite.fromWireString('e621'), BunnySite.e621);
    });

    test('round-trips inkbunny', () {
      expect(BunnySite.inkbunny.toWireString(), 'inkbunny');
      expect(BunnySite.fromWireString('inkbunny'), BunnySite.inkbunny);
    });

    test('rejects an unknown site string', () {
      expect(
        () => BunnySite.fromWireString('furaffinity'),
        throwsArgumentError,
      );
    });
  });
}
