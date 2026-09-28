#include "config.h"

#include <goblin/appdirs.h>
#include <goblin/cstr.h>

#include <stdio.h>
#include <stdlib.h>

#define SERVER_DEFAULT_PORT 8443
#define SERVER_DEFAULT_POLL_INTERVAL_SEC (15 * 60)
#define SERVER_DEFAULT_USER_AGENT "LittleBunny-Server/0.1"
#define SERVER_APP_NAME "little-bunny"

static int getenv_int_or(const char *name, int default_value)
{
    const char *value = getenv(name);
    if (!value || !*value) {
        return default_value;
    }
    return atoi(value);
}

static char *getenv_str_or_copy(const char *name, const char *default_value)
{
    const char *value = getenv(name);
    return goblin_copy_cstr(value && *value ? value : default_value);
}

server_config_t *server_config_load(void)
{
    server_config_t *config = calloc(1, sizeof(server_config_t));
    if (!config) {
        return NULL;
    }

    config->port = getenv_int_or("BUNNY_SERVER_PORT", SERVER_DEFAULT_PORT);
    config->poll_interval_sec = getenv_int_or("BUNNY_SERVER_POLL_INTERVAL_SEC", SERVER_DEFAULT_POLL_INTERVAL_SEC);
    config->user_agent = getenv_str_or_copy("BUNNY_SERVER_USER_AGENT", SERVER_DEFAULT_USER_AGENT);

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
