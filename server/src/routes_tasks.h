#ifndef BUNNY_SERVER_ROUTES_TASKS_H
#define BUNNY_SERVER_ROUTES_TASKS_H

#include <civetweb.h>

#include "context.h"

/* GET /tasks -> every pending + currently-running task_queue job, in the
 * order they'll actually run (highest priority first, then FIFO within a
 * priority) -- the in-app "task queue" view (M24), as opposed to GET
 * /sync/status's single "what's running right now" snapshot. */
void server_routes_register_tasks(struct mg_context *mg_ctx, server_context_t *ctx);

#endif /* BUNNY_SERVER_ROUTES_TASKS_H */
