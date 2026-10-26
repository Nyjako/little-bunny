import '../repository/bunny_models.dart';

/// Groups [searches] by `(site, query)`, returning only the groups with more
/// than one member -- M38's own create-time check (the exact same `(site,
/// query)` equality, see [CreateSearchScreen]/[SearchesScreen]'s pool-
/// creation path) stops *new* duplicates, but has no effect on ones that
/// were already saved before that check existed (M41). A pool search's
/// identity is already fully encoded in its `query` (`pool:<id>`, see
/// [BunnySearch.isPool]), so no special-casing is needed for it to be
/// grouped the same way as a regular search.
///
/// Order is otherwise unspecified -- callers that care about a stable
/// display order should sort the result themselves.
List<List<BunnySearch>> findDuplicateSearchGroups(List<BunnySearch> searches) {
  final bySiteAndQuery = <(BunnySite, String), List<BunnySearch>>{};
  for (final search in searches) {
    bySiteAndQuery.putIfAbsent((search.site, search.query), () => []).add(search);
  }
  return [for (final group in bySiteAndQuery.values) if (group.length > 1) group];
}
