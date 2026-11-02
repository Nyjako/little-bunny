#ifndef BUNNY_TAG_QUERY_H
#define BUNNY_TAG_QUERY_H

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Full e621 tag-search grammar (M28/M54), shared between actual blacklist
 * matching (libs/db) and syntax-only validation (the Flutter app, via FFI)
 * -- a single implementation backs both, since both ultimately link this
 * same C code (networked server directly, standalone app through FFI).
 *
 * Grammar:
 *   - Space-separated terms are AND'd (all required).
 *   - `~term` means OR -- every `~`-prefixed term at the SAME level forms
 *     one "at least one of these" set (e.g. "cat ~dog ~fox bird" requires
 *     cat AND bird, AND (dog OR fox)).
 *   - `-term` negates/excludes it (forbidden).
 *   - A bare tag may contain a `*` anywhere as a wildcard marker (matched
 *     as a prefix -- see bunny_tag_query_matches).
 *   - `( term term )` groups -- a required whitespace run right after `(`
 *     and right before `)`. A group can itself carry a `-`/`~` prefix,
 *     treating its own evaluated result as a single atom at the parent
 *     level. Nesting is capped at 10 levels; an empty group is a syntax
 *     error.
 *   - An empty (or all-whitespace) top-level query is syntactically valid
 *     and matches everything -- there's nothing malformed about it;
 *     "non-empty" is a separate, caller-side concern (e.g. a UI's own
 *     required-field check), not a grammar rule. */

/* Opaque parsed AST. Owns its own copies of every tag's text, so `text`
 * passed to bunny_tag_query_parse can be freed/go out of scope immediately
 * after the call returns. */
typedef struct bunny_tag_query_node bunny_tag_query_node_t;

/* Parses `text`. On success returns true with *out_root set to a non-NULL
 * tree the caller must eventually pass to bunny_tag_query_free. On a
 * syntax error (or exceeding the 10-level nesting cap) returns false,
 * *out_root is left NULL, and *out_error_pos (if out_error_pos is
 * non-NULL) is set to the byte offset into `text` nearest the problem --
 * e.g. for highlighting the offending character in a text field. */
bool bunny_tag_query_parse(const char *text, bunny_tag_query_node_t **out_root, size_t *out_error_pos);

void bunny_tag_query_free(bunny_tag_query_node_t *root);

/* True if `tags` (a post's own tag names, `tag_count` entries, any order)
 * satisfies the parsed query `root`. Plain case-sensitive strcmp per tag
 * (not case-insensitive) -- matches this project's existing tag-name
 * storage convention, where tags are never case-folded on ingest. A
 * wildcarded tag (containing `*`) matches by comparing only the text
 * before the first `*` as a prefix. `tags` is read-only and not retained
 * past the call. */
bool bunny_tag_query_matches(const bunny_tag_query_node_t *root, const char *const *tags, size_t tag_count);

/* Validate-only: internally parses then immediately frees, never exposing
 * an AST. This is the entire surface the Flutter app needs for live-typing
 * validation (blacklist lines, search queries) -- just yes/no plus an
 * error position, with no lifetime to manage across FFI. Equivalent to
 * bunny_tag_query_parse followed by bunny_tag_query_free on success. */
bool bunny_tag_query_validate(const char *text, size_t *out_error_pos);

#ifdef __cplusplus
}
#endif

#endif /* BUNNY_TAG_QUERY_H */
