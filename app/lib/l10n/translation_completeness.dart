import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Percentage of the English template's own keys that [languageCode]'s ARB
/// file defines a non-empty value for -- read from the raw ARB files
/// bundled as assets (see pubspec.yaml), not anything `flutter gen-l10n`
/// generates: a generated `AppLocalizationsXx` class already silently falls
/// back to the English text for anything missing (gen-l10n's own built-in
/// behavior), so there is no way to tell "genuinely translated" apart from
/// "fell back to English" from the generated code alone. English itself is
/// the template, not a translation of anything, so callers should skip
/// asking for it.
///
/// `languageCodes` lists every non-English locale to check (normally
/// [AppLocalizations.supportedLocales]'s own codes) -- a code with no
/// matching bundled `app_<code>.arb` asset is simply left out of the
/// result rather than throwing.
Future<Map<String, int>> loadTranslationCompletenessPercent(Iterable<String> languageCodes) async {
  final templateJson = jsonDecode(await rootBundle.loadString('lib/l10n/app_en.arb')) as Map<String, dynamic>;
  final templateKeys = templateJson.keys.where((key) => !key.startsWith('@')).toSet();
  if (templateKeys.isEmpty) {
    return {};
  }

  final result = <String, int>{};
  for (final code in languageCodes) {
    if (code == 'en') {
      continue;
    }
    try {
      final json = jsonDecode(await rootBundle.loadString('lib/l10n/app_$code.arb')) as Map<String, dynamic>;
      final translatedCount = templateKeys.where((key) => json[key] is String && (json[key] as String).isNotEmpty).length;
      result[code] = ((translatedCount / templateKeys.length) * 100).round();
    } catch (_) {
      // Best-effort -- a locale listed in AppLocalizations.supportedLocales
      // without a matching bundled ARB asset just shows no percentage.
    }
  }
  return result;
}
