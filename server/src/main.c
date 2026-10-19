#include <bunny_common/thread.h>
#include <bunny_core/core.h>
#include <goblin/appdirs.h>

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "app.h"
#include "config.h"
#include "log.h"
#include "qr.h"
#include "updater.h"

static volatile sig_atomic_t g_shutdown_requested = 0;

static void handle_shutdown_signal(int signum)
{
    (void)signum;
    g_shutdown_requested = 1;
}

int main(int argc, char **argv)
{
    /* Used by the updater (updater.c, M23) after extracting a staged
     * release to confirm the new binary is actually the version it claims
     * to be, before the systemd ExecStartPre=+ helper installs it over the
     * live one -- also handy for plain ops/debugging ("what's running"). */
    if (argc > 1 && (strcmp(argv[1], "--version") == 0 || strcmp(argv[1], "-v") == 0)) {
        printf("%d\n", BUNNY_BUILD_NUMBER);
        return 0;
    }

    /* Prints a QR code (+ the raw JSON, for manual copy-paste) encoding this
     * server's own connection info -- scannable by the app's "Networked"
     * setup screen instead of typing the server URL/bearer token/cert
     * fingerprint in by hand. Doesn't start the server itself (see qr.c's
     * own doc comment for why that's fine even on a never-before-run data
     * dir). */
    if (argc > 1 && strcmp(argv[1], "--qr") == 0) {
        server_config_t *qr_config = server_config_load();
        if (!qr_config) {
            fprintf(stderr, "failed to load server config\n");
            return 1;
        }
        bool ok = server_print_connection_qr(qr_config);
        server_config_free(qr_config);
        return ok ? 0 : 1;
    }

    server_config_t *config = server_config_load();
    if (!config) {
        fprintf(stderr, "failed to load server config\n");
        return 1;
    }

    char *db_path = goblin_appdir_join(config->data_dir, "bunny.db");
    if (!db_path) {
        fprintf(stderr, "failed to build database path\n");
        server_config_free(config);
        return 1;
    }

    bunny_core_config_t core_config;
    memset(&core_config, 0, sizeof(core_config));
    core_config.db_path = db_path;
    core_config.user_agent = config->user_agent;

    server_app_t *app = server_app_start(&core_config, config->data_dir, config->port, config->poll_interval_sec);
    free(db_path);
    if (!app) {
        fprintf(stderr, "failed to start server\n");
        server_config_free(config);
        return 1;
    }

    server_log("INFO", "bunny_server listening on https://0.0.0.0:%d", config->port);

    signal(SIGINT, handle_shutdown_signal);
    signal(SIGTERM, handle_shutdown_signal);
    while (!g_shutdown_requested) {
        bunny_sleep_seconds(1);
    }

    server_log("INFO", "shutting down...");
    server_app_stop(app);
    server_config_free(config);
    return 0;
}
