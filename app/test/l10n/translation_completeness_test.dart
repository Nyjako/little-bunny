import 'package:flutter_test/flutter_test.dart';
import 'package:little_bunny/l10n/translation_completeness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('english is excluded from the result -- it is the template, not a translation of anything', () async {
    final result = await loadTranslationCompletenessPercent(['en', 'pl']);
    expect(result.containsKey('en'), isFalse);
  });

  test('a fully-translated locale (pl) reports 100%', () async {
    final result = await loadTranslationCompletenessPercent(['pl']);
    expect(result['pl'], 100);
  });

  test('a locale with no bundled ARB asset is left out rather than throwing', () async {
    final result = await loadTranslationCompletenessPercent(['xx']);
    expect(result.containsKey('xx'), isFalse);
  });
}
