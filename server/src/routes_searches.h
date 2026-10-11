#ifndef BUNNY_SERVER_ROUTES_SEARCHES_H
#define BUNNY_SERVER_ROUTES_SEARCHES_H

#include <civetweb.h>

#include "context.h"

/* POST /searches (body: site, label, query, interval_hours, auto_favorite,
 *   auto_favorite_stars, auto_upvote) -> bunny_core_search_create
 * GET /searches -> bunny_core_search_list
 * PUT /searches/{id} (body: label, query, interval_hours, auto_favorite,
 *   auto_favorite_stars, auto_upvote) -> bunny_core_search_update
 * DELETE /searches/{id} -> bunny_core_search_delete
 * GET /searches/{id}/posts?unseen_only=true -> bunny_core_search_list_posts
 * POST /searches/{id}/sync -> bunny_core_sync_search (M13.2, forces a sync
 *   regardless of the search's own due-interval) */
void server_routes_register_searches(struct mg_context *mg_ctx, server_context_t *ctx);

#endif /* BUNNY_SERVER_ROUTES_SEARCHES_H */
