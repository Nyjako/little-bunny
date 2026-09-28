#ifndef BUNNY_SERVER_ROUTE_UTILS_H
#define BUNNY_SERVER_ROUTE_UTILS_H

#include <bunny_db/types.h>

#include <stdbool.h>
#include <stdint.h>

/* Returns a pointer into `uri` just past `prefix` + '/', or NULL if `uri`
 * isn't exactly `prefix` followed by a non-empty sub-path. E.g.
 * server_route_sub_path("/accounts/e621", "/accounts") -> "e621";
 * server_route_sub_path("/accounts", "/accounts") -> NULL (exact match). */
const char *server_route_sub_path(const char *uri, const char *prefix);

/* Parses `text` as a positive int64 id. Returns false (and doesn't touch
 * *out_id) if `text` isn't a valid, fully-consumed positive integer. */
bool server_route_parse_id(const char *text, int64_t *out_id);

/* If `sub_path` is exactly "<id>/<suffix>", parses <id> into *out_id and
 * returns true. Used for routes like "/searches/{id}/posts". */
bool server_route_parse_id_with_suffix(const char *sub_path, const char *suffix, int64_t *out_id);

/* Parses "e621"/"inkbunny" (case-sensitive, matching bunny_db_site_to_string's
 * own output) into *out_site. Returns false for anything else. */
bool server_route_parse_site(const char *text, bunny_db_site_t *out_site);

#endif /* BUNNY_SERVER_ROUTE_UTILS_H */
