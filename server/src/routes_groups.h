#ifndef BUNNY_SERVER_ROUTES_GROUPS_H
#define BUNNY_SERVER_ROUTES_GROUPS_H

#include <civetweb.h>

#include "context.h"

/* POST/GET /groups, PUT/DELETE /groups/{id} -- folder-like groups for
 * organizing saved searches in SearchesScreen's tree view (M21). Deleting a
 * group ungroups its member searches rather than deleting them (see
 * bunny_db_group_delete's doc comment). A search's own membership is set via
 * POST /searches/{id}/group (routes_searches.c), not here. */
void server_routes_register_groups(struct mg_context *mg_ctx, server_context_t *ctx);

#endif /* BUNNY_SERVER_ROUTES_GROUPS_H */
