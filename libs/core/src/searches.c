#include "bunny_core/core.h"

#include "internal.h"

bunny_core_result_t bunny_core_search_create(bunny_core_t *core, bunny_db_site_t site, const char *label, const char *query, int interval_hours, int64_t *out_id)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    return bunny_core_map_db_result(bunny_db_search_create(core->db, site, label, query, interval_hours, out_id));
}

bunny_core_result_t bunny_core_search_delete(bunny_core_t *core, int64_t search_id)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    return bunny_core_map_db_result(bunny_db_search_delete(core->db, search_id));
}

bunny_core_result_t bunny_core_search_list(bunny_core_t *core, bunny_db_search_list_t *out_list)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    return bunny_core_map_db_result(bunny_db_search_list(core->db, out_list));
}

bunny_core_result_t bunny_core_search_list_posts(bunny_core_t *core, int64_t search_id, bool unseen_only, bunny_db_post_list_t *out_list)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    return bunny_core_map_db_result(bunny_db_search_list_posts(core->db, search_id, unseen_only, out_list));
}

bunny_core_result_t bunny_core_tag_autocomplete(bunny_core_t *core, bunny_db_site_t site, const char *prefix, int limit, bunny_db_tag_stat_list_t *out_list)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    return bunny_core_map_db_result(bunny_db_tag_autocomplete(core->db, site, prefix, limit, out_list));
}

bunny_core_result_t bunny_core_post_mark_seen(bunny_core_t *core, int64_t post_id)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    return bunny_core_map_db_result(bunny_db_post_mark_seen(core->db, post_id));
}

bunny_core_result_t bunny_core_search_mark_all_seen(bunny_core_t *core, int64_t search_id)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    return bunny_core_map_db_result(bunny_db_search_mark_all_seen(core->db, search_id));
}
