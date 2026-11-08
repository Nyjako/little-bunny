#include "bunny_core/core.h"

#include "internal.h"

bunny_core_result_t bunny_core_download_queue_add(bunny_core_t *core, int64_t post_id, int64_t pool_id, const char *pool_name, int pool_page, int64_t *out_id)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    bunny_core_db_lock(core);
    bunny_db_result_t result = bunny_db_download_queue_add(core->db, post_id, pool_id, pool_name, pool_page, out_id);
    bunny_core_db_unlock(core);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_download_queue_set_status(bunny_core_t *core, int64_t id, bunny_db_download_queue_status_t status, const char *failure_reason)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    bunny_core_db_lock(core);
    bunny_db_result_t result = bunny_db_download_queue_set_status(core->db, id, status, failure_reason);
    bunny_core_db_unlock(core);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_download_queue_list(bunny_core_t *core, bunny_db_download_queue_list_t *out_list)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    bunny_core_db_lock(core);
    bunny_db_result_t result = bunny_db_download_queue_list(core->db, out_list);
    bunny_core_db_unlock(core);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_download_queue_clear_finished(bunny_core_t *core)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    bunny_core_db_lock(core);
    bunny_db_result_t result = bunny_db_download_queue_clear_finished(core->db);
    bunny_core_db_unlock(core);
    return bunny_core_map_db_result(result);
}
