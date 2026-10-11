#include "app.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "auth.h"
#include "routes_accounts.h"
#include "routes_blacklist.h"
#include "routes_pools.h"
#include "routes_queue.h"
#include "routes_search.h"
#include "routes_searches.h"
#include "routes_tags.h"
#include "tls.h"

static int health_handler(struct mg_connection *conn, void *cbdata)
{
    (void)cbdata;
    const char *body = "{\"status\":\"ok\"}";
    mg_printf(conn,
              "HTTP/1.1 200 OK\r\n"
              "Content-Type: application/json\r\n"
              "Content-Length: %d\r\n"
              "Connection: close\r\n\r\n"
              "%s",
              (int)strlen(body), body);
    return 200;
}

server_app_t *server_app_start(const bunny_core_config_t *core_config, const char *data_dir, int port, int poll_interval_sec)
{
    server_app_t *app = calloc(1, sizeof(server_app_t));
    if (!app) {
        return NULL;
    }

    app->auth = server_auth_load(data_dir);
    if (!app->auth) {
        free(app);
        return NULL;
    }

    app->cert_path = server_tls_ensure_cert(data_dir);
    if (!app->cert_path) {
        server_auth_free(app->auth);
        free(app);
        return NULL;
    }

    bunny_core_result_t open_result = bunny_core_open(core_config, &app->core);
    /* accounts.secret is stored plain (see M4.1) -- restrict the DB file the
     * same way as the auth token and TLS key. No-op for ":memory:". */
    if (core_config->db_path && strcmp(core_config->db_path, ":memory:") != 0) {
        chmod(core_config->db_path, 0600);
    }
    if (open_result != BUNNY_CORE_OK) {
        free(app->cert_path);
        server_auth_free(app->auth);
        free(app);
        return NULL;
    }

    app->ctx.core = app->core;
    app->ctx.auth = app->auth;
    if (pthread_mutex_init(&app->ctx.core_mutex, NULL) != 0) {
        bunny_core_close(app->core);
        free(app->cert_path);
        server_auth_free(app->auth);
        free(app);
        return NULL;
    }

    char port_option[32];
    snprintf(port_option, sizeof(port_option), "%ds", port);
    const char *options[] = {
        "listening_ports", port_option, "ssl_certificate", app->cert_path, "num_threads", "4", NULL,
    };

    app->mg_ctx = mg_start(NULL, NULL, options);
    if (!app->mg_ctx) {
        pthread_mutex_destroy(&app->ctx.core_mutex);
        bunny_core_close(app->core);
        free(app->cert_path);
        server_auth_free(app->auth);
        free(app);
        return NULL;
    }

    mg_set_request_handler(app->mg_ctx, "/health", health_handler, NULL);
    server_routes_register_accounts(app->mg_ctx, &app->ctx);
    server_routes_register_searches(app->mg_ctx, &app->ctx);
    server_routes_register_queue(app->mg_ctx, &app->ctx);
    server_routes_register_tags(app->mg_ctx, &app->ctx);
    server_routes_register_pools(app->mg_ctx, &app->ctx);
    server_routes_register_search(app->mg_ctx, &app->ctx);
    server_routes_register_blacklist(app->mg_ctx, &app->ctx);

    if (!server_scheduler_start(&app->scheduler, &app->ctx, poll_interval_sec)) {
        mg_stop(app->mg_ctx);
        pthread_mutex_destroy(&app->ctx.core_mutex);
        bunny_core_close(app->core);
        free(app->cert_path);
        server_auth_free(app->auth);
        free(app);
        return NULL;
    }

    return app;
}

const char *server_app_auth_token(const server_app_t *app)
{
    return app && app->auth ? app->auth->token : NULL;
}

void server_app_stop(server_app_t *app)
{
    if (!app) {
        return;
    }
    /* Stop the scheduler first so it's done issuing bunny_core_* calls
     * before civetweb's workers and the core itself get torn down. */
    server_scheduler_stop(&app->scheduler);
    mg_stop(app->mg_ctx);
    pthread_mutex_destroy(&app->ctx.core_mutex);
    bunny_core_close(app->core);
    free(app->cert_path);
    server_auth_free(app->auth);
    free(app);
}
