import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../util/e621_metatags.dart';

/// A small structured editor for e621's own metatag search syntax
/// (`rating:`/`id:`/`score:`/`favcount:`) layered directly on top of the
/// existing free-text query field -- e621 has no form-based search UI to
/// mirror the way `InkbunnyAdvancedFiltersPanel` mirrors Inkbunny's, these
/// metatags are just ordinary tag text the query field already accepts
/// (confirmed live, M74), so this is purely a convenience for not having to
/// remember/retype the exact syntax by hand, not a separate parameter set
/// threaded anywhere else. [queryController] is read directly (via
/// [extractE621Metatags]) on every rebuild and written back to (via
/// [applyE621Metatags]) on every change here, so manual edits to the query
/// field and changes made through this panel both always agree -- there's
/// only ever the one text field as the source of truth.
class E621MetatagsPanel extends StatelessWidget {
  final TextEditingController queryController;
  final bool enabled;

  const E621MetatagsPanel({super.key, required this.queryController, this.enabled = true});

  void _update(String remainder, E621Metatags Function(E621Metatags) transform) {
    final (current, _) = extractE621Metatags(queryController.text);
    final newText = applyE621Metatags(remainder, transform(current));
    queryController.value = TextEditingValue(text: newText, selection: TextSelection.collapsed(offset: newText.length));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: queryController,
      builder: (context, _) {
        final (metatags, remainder) = extractE621Metatags(queryController.text);
        return ExpansionTile(
          key: const Key('e621MetatagsPanel'),
          title: Text(l10n.e621MetatagsTitle),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.e621MetatagsRatingLabel, style: Theme.of(context).textTheme.labelLarge),
                  CheckboxListTile(
                    key: const Key('e621MetatagRatingSafe'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    enabled: enabled,
                    title: Text(l10n.e621MetatagsRatingSafe),
                    value: metatags.ratingSafe,
                    onChanged: (checked) => _update(remainder, (m) => m.copyWith(ratingSafe: checked)),
                  ),
                  CheckboxListTile(
                    key: const Key('e621MetatagRatingQuestionable'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    enabled: enabled,
                    title: Text(l10n.e621MetatagsRatingQuestionable),
                    value: metatags.ratingQuestionable,
                    onChanged: (checked) => _update(remainder, (m) => m.copyWith(ratingQuestionable: checked)),
                  ),
                  CheckboxListTile(
                    key: const Key('e621MetatagRatingExplicit'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    enabled: enabled,
                    title: Text(l10n.e621MetatagsRatingExplicit),
                    value: metatags.ratingExplicit,
                    onChanged: (checked) => _update(remainder, (m) => m.copyWith(ratingExplicit: checked)),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const Key('e621MetatagIdField'),
                    enabled: enabled,
                    initialValue: metatags.id,
                    decoration: InputDecoration(labelText: l10n.e621MetatagsIdLabel, helperText: l10n.e621MetatagsIdHelper),
                    onChanged: (text) => _update(remainder, (m) => m.copyWith(id: text, clearId: text.isEmpty)),
                  ),
                  const SizedBox(height: 8),
                  Text(l10n.e621MetatagsScoreLabel, style: Theme.of(context).textTheme.labelLarge),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: const Key('e621MetatagScoreMinField'),
                          enabled: enabled,
                          initialValue: metatags.scoreMin?.toString(),
                          decoration: InputDecoration(labelText: l10n.e621MetatagsMinLabel),
                          keyboardType: const TextInputType.numberWithOptions(signed: true),
                          onChanged: (text) => _update(remainder, (m) => m.copyWith(scoreMin: int.tryParse(text), clearScoreMin: text.isEmpty)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          key: const Key('e621MetatagScoreMaxField'),
                          enabled: enabled,
                          initialValue: metatags.scoreMax?.toString(),
                          decoration: InputDecoration(labelText: l10n.e621MetatagsMaxLabel),
                          keyboardType: const TextInputType.numberWithOptions(signed: true),
                          onChanged: (text) => _update(remainder, (m) => m.copyWith(scoreMax: int.tryParse(text), clearScoreMax: text.isEmpty)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(l10n.e621MetatagsFavcountLabel, style: Theme.of(context).textTheme.labelLarge),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: const Key('e621MetatagFavcountMinField'),
                          enabled: enabled,
                          initialValue: metatags.favcountMin?.toString(),
                          decoration: InputDecoration(labelText: l10n.e621MetatagsMinLabel),
                          keyboardType: TextInputType.number,
                          onChanged: (text) => _update(remainder, (m) => m.copyWith(favcountMin: int.tryParse(text), clearFavcountMin: text.isEmpty)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          key: const Key('e621MetatagFavcountMaxField'),
                          enabled: enabled,
                          initialValue: metatags.favcountMax?.toString(),
                          decoration: InputDecoration(labelText: l10n.e621MetatagsMaxLabel),
                          keyboardType: TextInputType.number,
                          onChanged: (text) => _update(remainder, (m) => m.copyWith(favcountMax: int.tryParse(text), clearFavcountMax: text.isEmpty)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
