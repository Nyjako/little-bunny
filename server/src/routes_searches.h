#ifndef BUNNY_SERVER_ROUTES_SEARCHES_H
#define BUNNY_SERVER_ROUTES_SEARCHES_H

#include <civetweb.h>

#include "context.h"

/* POST /searches (body: site, label, query, interval_hours) -> bunny_core_search_create
 * GET /searches -> bunny_core_search_list
 * DELETE /searches/{id} -> bunny_core_search_delete
 * GET /searches/{id}/posts?unseen_only=true -> bunny_core_search_list_posts */
void server_routes_register_searches(struct mg_context *mg_ctx, server_context_t *ctx);

#endif /* BUNNY_SERVER_ROUTES_SEARCHES_H */
