import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../repository/bunny_models.dart';

/// Inkbunny's `api_search.php` advanced filters (M74) -- a controlled
/// widget (value + onChanged, same pattern as a `TextField`'s own
/// controller) so `CreateSearchScreen`/`EditSearchScreen`/
/// `CustomSearchScreen` can each hold the one [InkbunnySearchFilters] value
/// their own state already needs, without three near-duplicate forms.
/// Collapsed by default (an `ExpansionTile`) -- every field here is
/// optional, and most searches won't need any of them.
class InkbunnyAdvancedFiltersPanel extends StatelessWidget {
  final InkbunnySearchFilters value;
  final ValueChanged<InkbunnySearchFilters> onChanged;
  final bool enabled;

  const InkbunnyAdvancedFiltersPanel({super.key, required this.value, required this.onChanged, this.enabled = true});

  static const Map<String, int> _orderByValues = {
    '': 0, // "default" -- create_datetime, api_search.php's own default
    'last_file_update_datetime': 1,
    'views': 2,
    'total_print_sales': 3,
    'total_digital_sales': 4,
    'total_sales': 5,
    'username': 6,
  };

  String _orderByLabel(AppLocalizations l10n, String key) => switch (key) {
    'last_file_update_datetime' => l10n.inkbunnyOrderByLastFileUpdate,
    'views' => l10n.inkbunnyOrderByViews,
    'total_print_sales' => l10n.inkbunnyOrderByTotalPrintSales,
    'total_digital_sales' => l10n.inkbunnyOrderByTotalDigitalSales,
    'total_sales' => l10n.inkbunnyOrderByTotalSales,
    'username' => l10n.inkbunnyOrderByUsername,
    _ => l10n.inkbunnyOrderByDefault,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ExpansionTile(
      key: const Key('inkbunnyAdvancedFiltersPanel'),
      title: Text(l10n.inkbunnyAdvancedFiltersTitle),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.inkbunnySearchInLabel, style: Theme.of(context).textTheme.labelLarge),
              CheckboxListTile(
                key: const Key('inkbunnySearchInKeywords'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                enabled: enabled,
                title: Text(l10n.inkbunnySearchInKeywords),
                value: (value.searchInMask & kInkbunnySearchInKeywords) != 0,
                onChanged: (checked) => onChanged(value.copyWith(searchInMask: checked! ? value.searchInMask | kInkbunnySearchInKeywords : value.searchInMask & ~kInkbunnySearchInKeywords)),
              ),
              CheckboxListTile(
                key: const Key('inkbunnySearchInTitle'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                enabled: enabled,
                title: Text(l10n.inkbunnySearchInTitle),
                value: (value.searchInMask & kInkbunnySearchInTitle) != 0,
                onChanged: (checked) => onChanged(value.copyWith(searchInMask: checked! ? value.searchInMask | kInkbunnySearchInTitle : value.searchInMask & ~kInkbunnySearchInTitle)),
              ),
              CheckboxListTile(
                key: const Key('inkbunnySearchInDescription'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                enabled: enabled,
                title: Text(l10n.inkbunnySearchInDescription),
                value: (value.searchInMask & kInkbunnySearchInDescription) != 0,
                onChanged: (checked) => onChanged(value.copyWith(searchInMask: checked! ? value.searchInMask | kInkbunnySearchInDescription : value.searchInMask & ~kInkbunnySearchInDescription)),
              ),
              CheckboxListTile(
                key: const Key('inkbunnySearchInMd5'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                enabled: enabled,
                title: Text(l10n.inkbunnySearchInMd5),
                value: (value.searchInMask & kInkbunnySearchInMd5) != 0,
                onChanged: (checked) => onChanged(value.copyWith(searchInMask: checked! ? value.searchInMask | kInkbunnySearchInMd5 : value.searchInMask & ~kInkbunnySearchInMd5)),
              ),
              const SizedBox(height: 8),
              Text(l10n.inkbunnyFieldJoinLabel, style: Theme.of(context).textTheme.labelLarge),
              SegmentedButton<int>(
                segments: [ButtonSegment(value: 0, label: Text(l10n.inkbunnyFieldJoinAny)), ButtonSegment(value: 1, label: Text(l10n.inkbunnyFieldJoinAll))],
                selected: {value.fieldJoinType},
                onSelectionChanged: enabled ? (selection) => onChanged(value.copyWith(fieldJoinType: selection.first)) : null,
              ),
              const SizedBox(height: 8),
              Text(l10n.inkbunnyStringJoinLabel, style: Theme.of(context).textTheme.labelLarge),
              SegmentedButton<int>(
                segments: [ButtonSegment(value: 0, label: Text(l10n.inkbunnyStringJoinAll)), ButtonSegment(value: 1, label: Text(l10n.inkbunnyStringJoinAny)), ButtonSegment(value: 2, label: Text(l10n.inkbunnyStringJoinExact))],
                selected: {value.stringJoinType},
                onSelectionChanged: enabled ? (selection) => onChanged(value.copyWith(stringJoinType: selection.first)) : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('inkbunnyUsernameField'),
                enabled: enabled,
                initialValue: value.username,
                decoration: InputDecoration(labelText: l10n.inkbunnyUsernameLabel),
                onChanged: (text) => onChanged(value.copyWith(username: text, clearUsername: text.isEmpty)),
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('inkbunnyDaysLimitField'),
                enabled: enabled,
                initialValue: value.daysLimit == 0 ? '' : '${value.daysLimit}',
                decoration: InputDecoration(labelText: l10n.inkbunnyDaysLimitLabel),
                keyboardType: TextInputType.number,
                onChanged: (text) => onChanged(value.copyWith(daysLimit: int.tryParse(text) ?? 0)),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                key: const Key('inkbunnyOrderByField'),
                decoration: InputDecoration(labelText: l10n.inkbunnyOrderByLabel),
                initialValue: _orderByValues[value.orderBy ?? ''] ?? 0,
                items: _orderByValues.entries.map((entry) => DropdownMenuItem(value: entry.value, child: Text(_orderByLabel(l10n, entry.key)))).toList(),
                onChanged: enabled
                    ? (selected) {
                        final key = _orderByValues.entries.firstWhere((entry) => entry.value == selected).key;
                        onChanged(value.copyWith(orderBy: key, clearOrderBy: key.isEmpty));
                      }
                    : null,
              ),
              CheckboxListTile(
                key: const Key('inkbunnyRandomCheckbox'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                enabled: enabled,
                title: Text(l10n.inkbunnyRandomLabel),
                value: value.random,
                onChanged: (checked) => onChanged(value.copyWith(random: checked!)),
              ),
              const SizedBox(height: 8),
              Text(l10n.inkbunnyScrapsLabel, style: Theme.of(context).textTheme.labelLarge),
              SegmentedButton<int>(
                segments: [ButtonSegment(value: 0, label: Text(l10n.inkbunnyScrapsBoth)), ButtonSegment(value: 1, label: Text(l10n.inkbunnyScrapsExclude)), ButtonSegment(value: 2, label: Text(l10n.inkbunnyScrapsOnly))],
                selected: {value.scraps},
                onSelectionChanged: enabled ? (selection) => onChanged(value.copyWith(scraps: selection.first)) : null,
              ),
              const SizedBox(height: 8),
              Text(l10n.inkbunnySubmissionTypeLabel, style: Theme.of(context).textTheme.labelLarge),
              Wrap(
                spacing: 8,
                children: kInkbunnySubmissionTypeNames.entries.map((entry) {
                  final bit = kInkbunnySubmissionTypeBit(entry.key);
                  return FilterChip(
                    key: Key('inkbunnySubmissionType${entry.key}'),
                    label: Text(entry.value),
                    selected: (value.submissionTypeMask & bit) != 0,
                    onSelected: enabled ? (selected) => onChanged(value.copyWith(submissionTypeMask: selected ? value.submissionTypeMask | bit : value.submissionTypeMask & ~bit)) : null,
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
