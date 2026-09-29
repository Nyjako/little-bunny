import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:little_bunny/l10n/app_localizations.dart';

/// Wraps [child] in a `MaterialApp` with the localization delegates
/// registered -- every screen calls `AppLocalizations.of(context)!`, which
/// throws without this, so widget tests can't just use a bare `MaterialApp`.
Widget wrapWithLocalization(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [AppLocalizations.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
}
