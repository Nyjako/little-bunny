#include "bunny_core/core.h"

#include "internal.h"

bunny_core_result_t bunny_core_blacklist_list(bunny_core_t *core, bunny_db_site_t site, bunny_db_string_list_t *out_list)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    size_t slot;
    bunny_db_t *read_db = bunny_core_db_read_lock(core, &slot);
    bunny_db_result_t result = bunny_db_blacklist_list(read_db, site, out_list);
    bunny_core_db_read_unlock(core, slot);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_blacklist_add(bunny_core_t *core, bunny_db_site_t site, const char *tag)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    bunny_core_db_lock(core);
    bunny_db_result_t result = bunny_db_blacklist_add(core->db, site, tag);
    bunny_core_db_unlock(core);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_blacklist_remove(bunny_core_t *core, bunny_db_site_t site, const char *tag)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    bunny_core_db_lock(core);
    bunny_db_result_t result = bunny_db_blacklist_remove(core->db, site, tag);
    bunny_core_db_unlock(core);
    return bunny_core_map_db_result(result);
}
