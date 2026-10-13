#ifndef BUNNY_SERVER_ROUTES_LOGS_H
#define BUNNY_SERVER_ROUTES_LOGS_H

#include <civetweb.h>

#include "context.h"

/* GET /logs -> server_log_snapshot (oldest-first JSON array of strings) */
void server_routes_register_logs(struct mg_context *mg_ctx, server_context_t *ctx);

#endif /* BUNNY_SERVER_ROUTES_LOGS_H */
