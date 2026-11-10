import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_version.dart';
import '../l10n/app_localizations.dart';
import '../services/update_apply_service.dart';
import '../services/update_check_service.dart';
import '../widgets/update_dialog.dart';
import 'changelog_screen.dart';

/// App version/description + open-source license list (M27) -- the license
/// list itself is Flutter's own [LicensePage]/[LicenseRegistry], which
/// `flutter pub get` already populates from every dependency's own license
/// file at build time, so there's nothing to maintain here by hand.
class AboutScreen extends StatelessWidget {
  /// Injectable for tests (same reasoning as [UpdateApplyService.client]);
  /// both default to real instances.
  final UpdateCheckService updateCheckService;
  final UpdateApplyService updateApplyService;

  const AboutScreen({super.key, this.updateCheckService = const UpdateCheckService(), this.updateApplyService = const UpdateApplyService()});

  static const _repoUrl = 'https://github.com/Nyjako/little-bunny';

  Future<void> _openRepo() async {
    await launchUrl(Uri.parse(_repoUrl), mode: LaunchMode.externalApplication);
  }

  /// Unlike the automatic once-per-launch check (SearchesScreen.initState),
  /// which stays silent when nothing's found, this manual path confirms it
  /// actually checked -- `checkForUpdateAndMaybePrompt`'s return value is
  /// exactly that signal.
  Future<void> _checkForUpdate(BuildContext context) async {
    final found = await checkForUpdateAndMaybePrompt(context, checkService: updateCheckService, applyService: updateApplyService);
    if (!found && context.mounted) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.aboutNoUpdateAvailable)));
    }
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
            leading: const Icon(Icons.system_update),
            title: Text(l10n.aboutCheckForUpdateButton),
            onTap: () => _checkForUpdate(context),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.history),
            title: Text(l10n.aboutViewChangelogEntry),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ChangelogScreen(checkService: updateCheckService))),
          ),
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
