import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/util/pool_description.dart';

void main() {
  group('parsePoolDescriptionSegments', () {
    test('plain text with no reference is a single text segment', () {
      final segments = parsePoolDescriptionSegments('A comic about wolves.');
      expect(segments, [isA<PoolDescriptionTextSegment>().having((s) => s.text, 'text', 'A comic about wolves.')]);
    });

    test('a reference mid-sentence splits into text/reference/text', () {
      final segments = parsePoolDescriptionSegments('See pool #456 for the sequel.');
      expect(segments, hasLength(3));
      expect((segments[0] as PoolDescriptionTextSegment).text, 'See ');
      final reference = segments[1] as PoolDescriptionReferenceSegment;
      expect(reference.poolId, 456);
      expect(reference.matchedText, 'pool #456');
      expect((segments[2] as PoolDescriptionTextSegment).text, ' for the sequel.');
    });

    test('a reference at the very start has no leading text segment', () {
      final segments = parsePoolDescriptionSegments('pool #1 is the prequel.');
      expect(segments, hasLength(2));
      expect(segments[0], isA<PoolDescriptionReferenceSegment>());
    });

    test('a reference at the very end has no trailing text segment', () {
      final segments = parsePoolDescriptionSegments('Continuation of pool #99');
      expect(segments, hasLength(2));
      expect(segments[1], isA<PoolDescriptionReferenceSegment>());
    });

    test('multiple references in one description', () {
      final segments = parsePoolDescriptionSegments('See pool #1 and pool #2.');
      final references = segments.whereType<PoolDescriptionReferenceSegment>().toList();
      expect(references.map((r) => r.poolId), [1, 2]);
    });

    test('"pool #" with no digits after it is left as plain text, not a reference', () {
      final segments = parsePoolDescriptionSegments('A pool #for cats.');
      expect(segments, [isA<PoolDescriptionTextSegment>().having((s) => s.text, 'text', 'A pool #for cats.')]);
    });

    test('a false "pool #" match does not swallow the text in front of a later real one', () {
      final segments = parsePoolDescriptionSegments('A pool #for cats, see pool #7.');
      expect(segments, hasLength(3));
      expect((segments[0] as PoolDescriptionTextSegment).text, 'A pool #for cats, see ');
      expect((segments[1] as PoolDescriptionReferenceSegment).poolId, 7);
      expect((segments[2] as PoolDescriptionTextSegment).text, '.');
    });

    test('an empty description produces no segments at all', () {
      expect(parsePoolDescriptionSegments(''), isEmpty);
    });
  });
}
