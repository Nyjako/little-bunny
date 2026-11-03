#ifndef BUNNY_SERVER_ROUTES_BLACKLIST_H
#define BUNNY_SERVER_ROUTES_BLACKLIST_H

#include <civetweb.h>

#include "context.h"

/* GET /blacklist?site= -> bunny_core_blacklist_list
 * POST /blacklist (body: site, tag) -> bunny_core_blacklist_add
 * DELETE /blacklist?site=&tag= -> bunny_core_blacklist_remove (M13.3)
 * GET /tag_query/validate?site=&text= -> bunny_core_tag_query_validate
 * (M28/M54 -- not blacklist-specific, just lives here alongside the
 * blacklist editor's own validation use) */
void server_routes_register_blacklist(struct mg_context *mg_ctx, server_context_t *ctx);

#endif /* BUNNY_SERVER_ROUTES_BLACKLIST_H */
