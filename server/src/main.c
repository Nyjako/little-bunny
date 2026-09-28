#include <bunny_core/core.h>
#include <civetweb.h>
#include <goblin/appdirs.h>

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "auth.h"
#include "config.h"
#include "context.h"
#include "tls.h"

static volatile sig_atomic_t g_shutdown_requested = 0;

static void handle_shutdown_signal(int signum)
{
    (void)signum;
    g_shutdown_requested = 1;
}

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

int main(void)
{
    server_config_t *config = server_config_load();
    if (!config) {
        fprintf(stderr, "failed to load server config\n");
        return 1;
    }

    server_auth_t *auth = server_auth_load(config->data_dir);
    if (!auth) {
        fprintf(stderr, "failed to load/generate auth token\n");
        server_config_free(config);
        return 1;
    }

    char *cert_path = server_tls_ensure_cert(config->data_dir);
    if (!cert_path) {
        fprintf(stderr, "failed to load/generate TLS certificate\n");
        server_auth_free(auth);
        server_config_free(config);
        return 1;
    }

    char *db_path = goblin_appdir_join(config->data_dir, "bunny.db");
    if (!db_path) {
        fprintf(stderr, "failed to build database path\n");
        free(cert_path);
        server_auth_free(auth);
        server_config_free(config);
        return 1;
    }

    bunny_core_config_t core_config;
    memset(&core_config, 0, sizeof(core_config));
    core_config.db_path = db_path;
    core_config.user_agent = config->user_agent;

    bunny_core_t *core = NULL;
    bunny_core_result_t open_result = bunny_core_open(&core_config, &core);
    /* accounts.secret is stored plain (see M4.1) -- restrict the DB file the
     * same way as the auth token and TLS key, so a shared/multi-user host
     * doesn't leak credentials via world-readable file permissions. */
    chmod(db_path, 0600);
    free(db_path);
    if (open_result != BUNNY_CORE_OK) {
        fprintf(stderr, "failed to open core database: %s\n", bunny_core_result_to_string(open_result));
        free(cert_path);
        server_auth_free(auth);
        server_config_free(config);
        return 1;
    }

    server_context_t ctx;
    ctx.core = core;
    ctx.auth = auth;
    if (pthread_mutex_init(&ctx.core_mutex, NULL) != 0) {
        fprintf(stderr, "failed to initialize core mutex\n");
        bunny_core_close(core);
        free(cert_path);
        server_auth_free(auth);
        server_config_free(config);
        return 1;
    }

    char port_option[32];
    snprintf(port_option, sizeof(port_option), "%ds", config->port);

    const char *options[] = {
        "listening_ports", port_option, "ssl_certificate", cert_path, "num_threads", "4", NULL,
    };

    struct mg_context *mg_ctx = mg_start(NULL, NULL, options);
    if (!mg_ctx) {
        fprintf(stderr, "failed to start HTTP server on port %d\n", config->port);
        pthread_mutex_destroy(&ctx.core_mutex);
        bunny_core_close(core);
        free(cert_path);
        server_auth_free(auth);
        server_config_free(config);
        return 1;
    }
    free(cert_path);

    mg_set_request_handler(mg_ctx, "/health", health_handler, NULL);

    fprintf(stdout, "bunny_server listening on https://0.0.0.0:%d\n", config->port);

    signal(SIGINT, handle_shutdown_signal);
    signal(SIGTERM, handle_shutdown_signal);
    while (!g_shutdown_requested) {
        sleep(1);
    }

    fprintf(stdout, "shutting down...\n");
    mg_stop(mg_ctx);
    pthread_mutex_destroy(&ctx.core_mutex);
    bunny_core_close(core);
    server_auth_free(auth);
    server_config_free(config);
    return 0;
}
