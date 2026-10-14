#include "bunny_core/core.h"

#include <goblin/cstr.h>

#include <stdlib.h>

#include "internal.h"

bunny_core_result_t bunny_core_open(const bunny_core_config_t *config, bunny_core_t **out_core)
{
    if (!config || !config->db_path || !config->user_agent || !out_core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }

    bunny_core_t *core = calloc(1, sizeof(bunny_core_t));
    if (!core) {
        return BUNNY_CORE_ERR_UNKNOWN;
    }

    bunny_db_result_t result = bunny_db_open(config->db_path, &core->db);
    if (result != BUNNY_DB_OK) {
        free(core);
        return bunny_core_map_db_result(result);
    }

    if (pthread_mutex_init(&core->db_mutex, NULL) != 0) {
        bunny_db_close(core->db);
        free(core);
        return BUNNY_CORE_ERR_UNKNOWN;
    }

    core->user_agent = goblin_copy_cstr(config->user_agent);
    core->e621_transport = config->e621_transport;
    core->inkbunny_transport = config->inkbunny_transport;
    core->min_request_interval_sec = config->min_request_interval_sec;
    core->log_callback = config->log_callback;
    core->log_user_data = config->log_user_data;

    *out_core = core;
    return BUNNY_CORE_OK;
}

void bunny_core_close(bunny_core_t *core)
{
    if (!core) {
        return;
    }
    pthread_mutex_destroy(&core->db_mutex);
    bunny_db_close(core->db);
    free(core->user_agent);
    free(core);
}
