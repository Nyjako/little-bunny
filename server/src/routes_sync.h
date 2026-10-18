#ifndef BUNNY_SERVER_ROUTES_SYNC_H
#define BUNNY_SERVER_ROUTES_SYNC_H

#include <civetweb.h>

#include "context.h"

/* GET /sync/status -> current server_sync_status_t snapshot, visible to
 * every device regardless of which one triggered the sync.
 * POST /sync/all -> enqueues a HIGH-priority forced sync of every search
 * onto ctx->task_queue and returns immediately (202) -- the server-side
 * replacement for the old client-driven "check for updates" loop. */
void server_routes_register_sync(struct mg_context *mg_ctx, server_context_t *ctx);

#endif /* BUNNY_SERVER_ROUTES_SYNC_H */
