import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';
import '../repository/bunny_repository.dart';

/// Shows the site/pool-id dialog and creates a pool search from it, same
/// flow [SearchesScreen]'s own FAB used to own directly -- extracted so the
/// slideshow editor's "add search" picker can reuse it too, without either
/// duplicating the duplicate-check/e621-name-lookup logic or promoting pool
/// creation to a full screen (unlike regular searches, there's no
/// `CreatePoolSearchScreen` to push). Returns `true` once a pool search was
/// actually created, mirroring `CreateSearchScreen`'s own pop-`true`
/// convention -- `false` on cancel or a declined duplicate.
Future<bool> showCreatePoolSearchDialog(BuildContext context, BunnyRepository repository) async {
  final l10n = AppLocalizations.of(context)!;
  final result = await showDialog<(BunnySite, String)>(
    context: context,
    builder: (context) {
      final controller = TextEditingController();
      var site = BunnySite.e621;
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l10n.createPoolSearchDialogTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<BunnySite>(
                segments: const [ButtonSegment(value: BunnySite.e621, label: Text('e621')), ButtonSegment(value: BunnySite.inkbunny, label: Text('Inkbunny'))],
                selected: {site},
                onSelectionChanged: (selection) => setState(() => site = selection.first),
              ),
              const SizedBox(height: 12),
              TextField(controller: controller, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: l10n.createPoolSearchIdLabel), autofocus: true),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonCancel)),
            TextButton(onPressed: () => Navigator.pop(context, (site, controller.text)), child: Text(l10n.createPoolSearchSubmit)),
          ],
        ),
      );
    },
  );
  if (result == null) {
    return false;
  }
  final (site, poolIdText) = result;
  final poolId = int.tryParse(poolIdText);
  if (poolId == null) {
    return false;
  }

  // Same duplicate-prevention check TagBrowseScreen's own checkmark action
  // applies (M38) -- a second pool search for the same (site, pool id)
  // would be functionally identical to the first.
  final existing = await repository.listSearches();
  if (existing.any((search) => search.site == site && search.query == 'pool:$poolId')) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.createPoolSearchAlreadyExists)));
    }
    return false;
  }

  // The pool's own name makes a far more useful label than the raw id, but
  // this works purely as a nice-to-have -- a failed lookup (network error,
  // deleted pool, etc.) still creates a perfectly functional pool search
  // with a fallback label, rather than blocking the whole action on it.
  // Inkbunny has no "fetch pool metadata" endpoint at all (M28) -- always
  // falls back to the raw-id label there, no lookup attempted (pool ids
  // aren't shared/comparable across sites, so trying e621's own lookup
  // with an Inkbunny pool id would risk silently naming it after an
  // unrelated e621 pool that happens to share the same numeric id).
  String label = 'pool:$poolId';
  if (site == BunnySite.e621) {
    try {
      final info = await repository.fetchPool(poolId);
      if (info.name != null && info.name!.isNotEmpty) {
        label = info.name!;
      }
    } catch (_) {
      // Fall back to the default label above.
    }
  }

  await repository.createSearch(site, label, 'pool:$poolId', usesDefaultInterval: true);
  return true;
}
