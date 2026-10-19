import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_version.dart';
import '../l10n/app_localizations.dart';

/// App version/description + open-source license list (M27) -- the license
/// list itself is Flutter's own [LicensePage]/[LicenseRegistry], which
/// `flutter pub get` already populates from every dependency's own license
/// file at build time, so there's nothing to maintain here by hand.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _repoUrl = 'https://github.com/Nyjako/little-bunny';

  Future<void> _openRepo() async {
    await launchUrl(Uri.parse(_repoUrl), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutScreenTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.appTitle, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(appBuildNumber > 0 ? l10n.aboutBuildNumber(appBuildNumber) : l10n.aboutLocalBuild, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          Text(l10n.aboutAppDescription),
          const SizedBox(height: 24),
          ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.link), title: Text(l10n.aboutSourceLink), onTap: _openRepo),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined),
            title: Text(l10n.aboutLicensesEntry),
            onTap: () => showLicensePage(context: context, applicationName: l10n.appTitle, applicationVersion: appBuildNumber > 0 ? l10n.aboutBuildNumber(appBuildNumber) : l10n.aboutLocalBuild),
          ),
        ],
      ),
    );
  }
}
