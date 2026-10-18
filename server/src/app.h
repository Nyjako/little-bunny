#ifndef BUNNY_SERVER_APP_H
#define BUNNY_SERVER_APP_H

#include <bunny_core/core.h>
#include <civetweb.h>

#include "context.h"
#include "scheduler.h"

typedef struct
{
    struct mg_context *mg_ctx;
    server_context_t ctx;
    server_auth_t *auth;
    char *cert_path;
    bunny_core_t *core;
    server_sync_status_t *sync_status;
    task_queue_t *task_queue;
    server_scheduler_t scheduler;
} server_app_t;

/* Wires up a full server (bunny_core, auth token, TLS cert, all routes, and
 * the background scheduler) and starts listening on `port`. `data_dir` holds
 * the auth token and TLS cert (generated if missing); `core_config` is
 * passed to bunny_core_open as-is, so its db_path is independent of
 * data_dir -- callers needing test isolation can pass ":memory:" there while
 * still using a real data_dir for the token/cert. `poll_interval_sec <= 0`
 * disables the scheduler (see server_scheduler_start). Returns NULL on
 * failure. */
server_app_t *server_app_start(const bunny_core_config_t *core_config, const char *data_dir, int port, int poll_interval_sec);

/* The loaded/generated auth token, for callers (e.g. tests) that need to
 * authenticate against the app they just started. */
const char *server_app_auth_token(const server_app_t *app);

void server_app_stop(server_app_t *app);

#endif /* BUNNY_SERVER_APP_H */
