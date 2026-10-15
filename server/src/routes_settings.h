#ifndef BUNNY_SERVER_ROUTES_SETTINGS_H
#define BUNNY_SERVER_ROUTES_SETTINGS_H

#include <civetweb.h>

#include "context.h"

/* GET/PUT /settings -> { "default_sync_interval_hours": <int> } -- the
 * server-wide default a search follows when its own uses_default_interval
 * is set (bunny_core_get/set_default_sync_interval_hours). */
void server_routes_register_settings(struct mg_context *mg_ctx, server_context_t *ctx);

#endif /* BUNNY_SERVER_ROUTES_SETTINGS_H */
