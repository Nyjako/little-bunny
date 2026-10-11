#include "bunny_core/core.h"

#include "internal.h"

bunny_core_result_t bunny_core_blacklist_list(bunny_core_t *core, bunny_db_site_t site, bunny_db_string_list_t *out_list)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    return bunny_core_map_db_result(bunny_db_blacklist_list(core->db, site, out_list));
}

bunny_core_result_t bunny_core_blacklist_add(bunny_core_t *core, bunny_db_site_t site, const char *tag)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    return bunny_core_map_db_result(bunny_db_blacklist_add(core->db, site, tag));
}

bunny_core_result_t bunny_core_blacklist_remove(bunny_core_t *core, bunny_db_site_t site, const char *tag)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    return bunny_core_map_db_result(bunny_db_blacklist_remove(core->db, site, tag));
}
