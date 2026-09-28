#include "bunny_core/core.h"

#include "internal.h"

bunny_core_result_t bunny_core_account_set(bunny_core_t *core, bunny_db_site_t site, const char *username, const char *secret)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    return bunny_core_map_db_result(bunny_db_account_set(core->db, site, username, secret));
}

bunny_core_result_t bunny_core_account_get(bunny_core_t *core, bunny_db_site_t site, bunny_db_account_t *out_account)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    return bunny_core_map_db_result(bunny_db_account_get(core->db, site, out_account));
}

bunny_core_result_t bunny_core_account_delete(bunny_core_t *core, bunny_db_site_t site)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    return bunny_core_map_db_result(bunny_db_account_delete(core->db, site));
}
