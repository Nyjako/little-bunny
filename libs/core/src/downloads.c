#include "bunny_core/core.h"

#include "internal.h"

bunny_core_result_t bunny_core_record_download(bunny_core_t *core, int64_t post_id, const char *file_path, const char *checksum_md5, bool verified, int64_t *out_id)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    bunny_core_db_lock(core);
    bunny_db_result_t result = bunny_db_download_record(core->db, post_id, file_path, checksum_md5, verified, out_id);
    bunny_core_db_unlock(core);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_list_downloads_for_post(bunny_core_t *core, int64_t post_id, bunny_db_download_list_t *out_list)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    bunny_core_db_lock(core);
    bunny_db_result_t result = bunny_db_download_list_for_post(core->db, post_id, out_list);
    bunny_core_db_unlock(core);
    return bunny_core_map_db_result(result);
}
