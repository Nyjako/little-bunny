#include <bunny_core/core.h>
#include <goblin/appdirs.h>

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "app.h"
#include "config.h"
#include "log.h"

static volatile sig_atomic_t g_shutdown_requested = 0;

static void handle_shutdown_signal(int signum)
{
    (void)signum;
    g_shutdown_requested = 1;
}

int main(void)
{
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
        sleep(1);
    }

    server_log("INFO", "shutting down...");
    server_app_stop(app);
    server_config_free(config);
    return 0;
}
