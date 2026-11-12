/// A handful of e621's own metatag search syntax (`rating:`/`id:`/`score:`/
/// `favcount:`), pulled out of a free-text query string so a small structured
/// form (`E621MetatagsPanel`) can edit them without the user having to
/// remember/retype the exact syntax -- e621 has no form-based search UI like
/// Inkbunny's (see `InkbunnyAdvancedFiltersPanel`), these are just ordinary
/// tag text the existing query field already accepts verbatim (confirmed
/// live, M74's own investigation), so there's nothing to thread through the
/// backend here -- purely a query-string editing convenience.
class E621Metatags {
  final bool ratingSafe;
  final bool ratingQuestionable;
  final bool ratingExplicit;

  /// Raw `id:` value, exactly as typed (e621 itself accepts a bare id, a
  /// comma-separated list, or a range -- this form doesn't need to parse
  /// that any further, just carry it through as one token's worth of text).
  final String? id;

  final int? scoreMin;
  final int? scoreMax;
  final int? favcountMin;
  final int? favcountMax;

  const E621Metatags({
    this.ratingSafe = false,
    this.ratingQuestionable = false,
    this.ratingExplicit = false,
    this.id,
    this.scoreMin,
    this.scoreMax,
    this.favcountMin,
    this.favcountMax,
  });

  bool get isEmpty => !ratingSafe && !ratingQuestionable && !ratingExplicit && id == null && scoreMin == null && scoreMax == null && favcountMin == null && favcountMax == null;

  E621Metatags copyWith({
    bool? ratingSafe,
    bool? ratingQuestionable,
    bool? ratingExplicit,
    String? id,
    bool clearId = false,
    int? scoreMin,
    bool clearScoreMin = false,
    int? scoreMax,
    bool clearScoreMax = false,
    int? favcountMin,
    bool clearFavcountMin = false,
    int? favcountMax,
    bool clearFavcountMax = false,
  }) => E621Metatags(
    ratingSafe: ratingSafe ?? this.ratingSafe,
    ratingQuestionable: ratingQuestionable ?? this.ratingQuestionable,
    ratingExplicit: ratingExplicit ?? this.ratingExplicit,
    id: clearId ? null : (id ?? this.id),
    scoreMin: clearScoreMin ? null : (scoreMin ?? this.scoreMin),
    scoreMax: clearScoreMax ? null : (scoreMax ?? this.scoreMax),
    favcountMin: clearFavcountMin ? null : (favcountMin ?? this.favcountMin),
    favcountMax: clearFavcountMax ? null : (favcountMax ?? this.favcountMax),
  );
}

final RegExp _tokenPattern = RegExp(r'\S+');

/// Splits [query] into whichever of the metatags above are present, and
/// everything else untouched (`remainder`) -- a recognized token is removed
/// from the text entirely (not just ignored), so [applyE621Metatags] can
/// re-add it in the form's own canonical shape without ending up with two
/// copies. Matching is deliberately narrow (exactly the shapes this form
/// itself ever writes, see [applyE621Metatags]) -- a metatag typed by hand
/// in some other equivalent form (e.g. `score:25..50`, `-rating:e`) is left
/// alone in `remainder` as plain text the form doesn't try to understand,
/// rather than silently dropped or misrepresented.
(E621Metatags, String remainder) extractE621Metatags(String query) {
  bool ratingSafe = false, ratingQuestionable = false, ratingExplicit = false;
  String? id;
  int? scoreMin, scoreMax, favcountMin, favcountMax;
  final remainderTokens = <String>[];

  for (final match in _tokenPattern.allMatches(query)) {
    final token = match.group(0)!;
    final bareToken = token.startsWith('~') ? token.substring(1) : token;

    if (bareToken == 'rating:s' || bareToken == 'rating:safe') {
      ratingSafe = true;
    } else if (bareToken == 'rating:q' || bareToken == 'rating:questionable') {
      ratingQuestionable = true;
    } else if (bareToken == 'rating:e' || bareToken == 'rating:explicit') {
      ratingExplicit = true;
    } else if (bareToken.startsWith('id:') && id == null) {
      id = bareToken.substring('id:'.length);
    } else if (bareToken.startsWith('score:>=')) {
      scoreMin = int.tryParse(bareToken.substring('score:>='.length));
      if (scoreMin == null) remainderTokens.add(token);
    } else if (bareToken.startsWith('score:<=')) {
      scoreMax = int.tryParse(bareToken.substring('score:<='.length));
      if (scoreMax == null) remainderTokens.add(token);
    } else if (bareToken.startsWith('favcount:>=')) {
      favcountMin = int.tryParse(bareToken.substring('favcount:>='.length));
      if (favcountMin == null) remainderTokens.add(token);
    } else if (bareToken.startsWith('favcount:<=')) {
      favcountMax = int.tryParse(bareToken.substring('favcount:<='.length));
      if (favcountMax == null) remainderTokens.add(token);
    } else {
      remainderTokens.add(token);
    }
  }

  final metatags = E621Metatags(
    ratingSafe: ratingSafe,
    ratingQuestionable: ratingQuestionable,
    ratingExplicit: ratingExplicit,
    id: id,
    scoreMin: scoreMin,
    scoreMax: scoreMax,
    favcountMin: favcountMin,
    favcountMax: favcountMax,
  );
  return (metatags, remainderTokens.join(' '));
}

/// Rebuilds a query string from [remainder] (whatever [extractE621Metatags]
/// didn't recognize, e.g. plain tags the user typed by hand) plus whatever's
/// set in [metatags], appended in a fixed order for determinism. Multiple
/// ratings are OR'd (`~rating:s ~rating:q`) -- e621's grammar ANDs plain
/// space-separated terms by default, so two bare `rating:` tokens would
/// require a post to satisfy both at once (impossible); a lone rating
/// doesn't need the `~` prefix at all.
String applyE621Metatags(String remainder, E621Metatags metatags) {
  final ratings = <String>[if (metatags.ratingSafe) 's', if (metatags.ratingQuestionable) 'q', if (metatags.ratingExplicit) 'e'];
  final tokens = <String>[
    if (remainder.trim().isNotEmpty) remainder.trim(),
    if (ratings.length == 1) 'rating:${ratings.single}' else ...ratings.map((r) => '~rating:$r'),
    if (metatags.id != null && metatags.id!.isNotEmpty) 'id:${metatags.id}',
    if (metatags.scoreMin != null) 'score:>=${metatags.scoreMin}',
    if (metatags.scoreMax != null) 'score:<=${metatags.scoreMax}',
    if (metatags.favcountMin != null) 'favcount:>=${metatags.favcountMin}',
    if (metatags.favcountMax != null) 'favcount:<=${metatags.favcountMax}',
  ];
  return tokens.join(' ');
}
