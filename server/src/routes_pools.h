#ifndef BUNNY_SERVER_ROUTES_POOLS_H
#define BUNNY_SERVER_ROUTES_POOLS_H

#include <civetweb.h>

#include "context.h"

/* GET /pools/{id} -> bunny_core_fetch_pool (e621 only, live -- no persistence).
 * GET /inkbunny_pools/{id} -> bunny_core_inkbunny_pool_name_for_id (Inkbunny's
 * best substitute -- backfilled from local data, not a live site fetch). */
void server_routes_register_pools(struct mg_context *mg_ctx, server_context_t *ctx);

#endif /* BUNNY_SERVER_ROUTES_POOLS_H */
