import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:little_bunny/l10n/app_localizations.dart';

/// Wraps [child] in a `MaterialApp` with the localization delegates
/// registered -- every screen calls `AppLocalizations.of(context)!`, which
/// throws without this, so widget tests can't just use a bare `MaterialApp`.
/// `locale` is pinned to English explicitly, not left to resolve from the
/// platform's own locale the way the real app does (M30) -- every test that
/// matches on English text (the overwhelming majority of this suite) would
/// otherwise silently break the moment a machine's own system locale
/// happens to match a locale this app also supports (e.g. a Polish-locale
/// machine once `pl` became supported, where Flutter's resolution picked
/// that over English with nothing here pinning it).
Widget wrapWithLocalization(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [AppLocalizations.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: child,
  );
}
