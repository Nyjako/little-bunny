#ifndef BUNNY_SERVER_ROUTES_SEARCH_H
#define BUNNY_SERVER_ROUTES_SEARCH_H

#include <civetweb.h>

#include "context.h"

/* POST /search/preview?site=&query= -> bunny_core_preview_search (stateless
 * one-page live search + cache, no searches/search_results row created) */
void server_routes_register_search(struct mg_context *mg_ctx, server_context_t *ctx);

#endif /* BUNNY_SERVER_ROUTES_SEARCH_H */
