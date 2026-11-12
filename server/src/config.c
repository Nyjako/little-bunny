#include "config.h"

#include <goblin/appdirs.h>
#include <goblin/cstr.h>
#include <goblin/env.h>

#include <stdio.h>
#include <stdlib.h>

#define SERVER_DEFAULT_PORT 8443
#define SERVER_DEFAULT_POLL_INTERVAL_SEC (15 * 60)
#define SERVER_DEFAULT_USER_AGENT "LittleBunny-Server/0.1"
#define SERVER_APP_NAME "little-bunny"

server_config_t *server_config_load(void)
{
    server_config_t *config = calloc(1, sizeof(server_config_t));
    if (!config) {
        return NULL;
    }

    config->port = goblin_getenv_int_or("BUNNY_SERVER_PORT", SERVER_DEFAULT_PORT);
    config->poll_interval_sec = goblin_getenv_int_or("BUNNY_SERVER_POLL_INTERVAL_SEC", SERVER_DEFAULT_POLL_INTERVAL_SEC);

    /* Not goblin_getenv_or -- that only falls back when the variable is
     * unset, not when it's set to an empty string, unlike every other
     * env-with-default read in this function (goblin_getenv_int_or above,
     * data_dir_env below). */
    const char *user_agent_env = getenv("BUNNY_SERVER_USER_AGENT");
    config->user_agent = goblin_copy_cstr((user_agent_env && *user_agent_env) ? user_agent_env : SERVER_DEFAULT_USER_AGENT);

    const char *data_dir_env = getenv("BUNNY_SERVER_DATA_DIR");
    if (data_dir_env && *data_dir_env) {
        config->data_dir = goblin_copy_cstr(data_dir_env);
    } else {
        config->data_dir = goblin_appdir_data_dir(SERVER_APP_NAME);
    }

    if (!config->data_dir || !config->user_agent) {
        server_config_free(config);
        return NULL;
    }

    if (goblin_appdir_mkdir_p(config->data_dir) != 0) {
        fprintf(stderr, "failed to create data directory: %s\n", config->data_dir);
        server_config_free(config);
        return NULL;
    }

    return config;
}

void server_config_free(server_config_t *config)
{
    if (!config) {
        return;
    }
    free(config->data_dir);
    free(config->user_agent);
    free(config);
}
