#include "bunny_core/core.h"

#include "internal.h"

bunny_core_result_t bunny_core_table_stats(bunny_core_t *core, bunny_db_tag_stat_list_t *out_list)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    size_t slot;
    bunny_db_t *read_db = bunny_core_db_read_lock(core, &slot);
    bunny_db_result_t result = bunny_db_table_stats(read_db, out_list);
    bunny_core_db_read_unlock(core, slot);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_integrity_check(bunny_core_t *core, bool *out_ok)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    size_t slot;
    bunny_db_t *read_db = bunny_core_db_read_lock(core, &slot);
    bunny_db_result_t result = bunny_db_integrity_check(read_db, out_ok);
    bunny_core_db_read_unlock(core, slot);
    return bunny_core_map_db_result(result);
}
