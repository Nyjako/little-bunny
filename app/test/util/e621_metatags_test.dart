import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/util/e621_metatags.dart';

void main() {
  group('extractE621Metatags', () {
    test('a query with no recognized metatags leaves everything in remainder', () {
      final (metatags, remainder) = extractE621Metatags('fox forest');
      expect(metatags.isEmpty, isTrue);
      expect(remainder, 'fox forest');
    });

    test('a lone rating is recognized with or without the ~ prefix', () {
      expect(extractE621Metatags('fox rating:s').$1.ratingSafe, isTrue);
      expect(extractE621Metatags('fox ~rating:s').$1.ratingSafe, isTrue);
    });

    test('recognizes every rating independently', () {
      final (metatags, remainder) = extractE621Metatags('rating:s ~rating:q ~rating:e fox');
      expect(metatags.ratingSafe, isTrue);
      expect(metatags.ratingQuestionable, isTrue);
      expect(metatags.ratingExplicit, isTrue);
      expect(remainder, 'fox');
    });

    test('recognizes id:, keeping only the first occurrence', () {
      final (metatags, remainder) = extractE621Metatags('id:100,121 fox id:999');
      expect(metatags.id, '100,121');
      expect(remainder, 'fox id:999');
    });

    test('recognizes score:>=/score:<= as min/max', () {
      final (metatags, remainder) = extractE621Metatags('fox score:>=10 score:<=50');
      expect(metatags.scoreMin, 10);
      expect(metatags.scoreMax, 50);
      expect(remainder, 'fox');
    });

    test('recognizes favcount:>=/favcount:<= as min/max', () {
      final (metatags, remainder) = extractE621Metatags('favcount:>=5 fox favcount:<=20');
      expect(metatags.favcountMin, 5);
      expect(metatags.favcountMax, 20);
      expect(remainder, 'fox');
    });

    test('a malformed score:/favcount: value is left in remainder rather than silently dropped', () {
      final (metatags, remainder) = extractE621Metatags('score:>=abc fox');
      expect(metatags.scoreMin, isNull);
      expect(remainder, 'score:>=abc fox');
    });

    test('an unrecognized metatag shape (e.g. a range) is left alone in remainder', () {
      final (metatags, remainder) = extractE621Metatags('score:25..50 fox');
      expect(metatags.scoreMin, isNull);
      expect(metatags.scoreMax, isNull);
      expect(remainder, 'score:25..50 fox');
    });
  });

  group('applyE621Metatags', () {
    test('an empty E621Metatags with an empty remainder produces an empty string', () {
      expect(applyE621Metatags('', const E621Metatags()), '');
    });

    test('a single rating is written without the ~ prefix', () {
      expect(applyE621Metatags('fox', const E621Metatags(ratingSafe: true)), 'fox rating:s');
    });

    test('multiple ratings are OR-joined with ~', () {
      expect(applyE621Metatags('', const E621Metatags(ratingSafe: true, ratingExplicit: true)), '~rating:s ~rating:e');
    });

    test('writes id:/score:/favcount: tokens in a fixed order', () {
      final result = applyE621Metatags('fox', const E621Metatags(id: '100', scoreMin: 10, scoreMax: 50, favcountMin: 5, favcountMax: 20));
      expect(result, 'fox id:100 score:>=10 score:<=50 favcount:>=5 favcount:<=20');
    });

    test('round-trips through extract/apply unchanged', () {
      const original = 'fox ~rating:s ~rating:q id:100 score:>=10 score:<=50 favcount:>=5 favcount:<=20';
      final (metatags, remainder) = extractE621Metatags(original);
      expect(applyE621Metatags(remainder, metatags), original);
    });
  });
}
