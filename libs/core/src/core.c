#include "bunny_core/core.h"

#include <stdlib.h>

#include "internal.h"

bunny_core_result_t bunny_core_open(const char *db_path, bunny_core_t **out_core)
{
    if (!db_path || !out_core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }

    bunny_core_t *core = calloc(1, sizeof(bunny_core_t));
    if (!core) {
        return BUNNY_CORE_ERR_UNKNOWN;
    }

    bunny_db_result_t result = bunny_db_open(db_path, &core->db);
    if (result != BUNNY_DB_OK) {
        free(core);
        return bunny_core_map_db_result(result);
    }

    *out_core = core;
    return BUNNY_CORE_OK;
}

void bunny_core_close(bunny_core_t *core)
{
    if (!core) {
        return;
    }
    bunny_db_close(core->db);
    free(core);
}
