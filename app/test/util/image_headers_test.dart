import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/repository/bunny_models.dart';
import 'package:little_bunny/util/image_headers.dart';

void main() {
  test('returns User-Agent/Referer headers for Inkbunny', () {
    final headers = imageHeadersFor(BunnySite.inkbunny);

    expect(headers, isNotNull);
    expect(headers!['User-Agent'], isNotEmpty);
    expect(headers['Referer'], 'https://inkbunny.net/');
  });

  test('returns null for e621 (no CDN header requirement)', () {
    expect(imageHeadersFor(BunnySite.e621), isNull);
  });
}
