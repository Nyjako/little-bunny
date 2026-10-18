#include "bunny_core/core.h"

#include "internal.h"

bunny_core_result_t bunny_core_search_create(bunny_core_t *core, bunny_db_site_t site, const char *label, const char *query, int interval_hours, const bunny_db_search_options_t *options, int64_t *out_id)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    bunny_core_db_lock(core);
    bunny_db_result_t result = bunny_db_search_create(core->db, site, label, query, interval_hours, options, out_id);
    bunny_core_db_unlock(core);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_search_update(bunny_core_t *core, int64_t search_id, const char *label, const char *query, int interval_hours, const bunny_db_search_options_t *options)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    /* Deliberately doesn't reset initial_sync_done/highest_synced_external_id
     * (see sync.c) -- a query edit could in theory interact oddly with the
     * incremental-sync high-water-mark or Inkbunny's already-synced
     * early-stop if the new query's results overlap unpredictably with the
     * old one's, but that's rare enough in practice to flag rather than
     * engineer around here. */
    bunny_core_db_lock(core);
    bunny_db_result_t result = bunny_db_search_update(core->db, search_id, label, query, interval_hours, options);
    bunny_core_db_unlock(core);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_get_default_sync_interval_hours(bunny_core_t *core, int *out_hours)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    size_t slot;
    bunny_db_t *read_db = bunny_core_db_read_lock(core, &slot);
    bunny_db_result_t result = bunny_db_settings_get_default_interval_hours(read_db, out_hours);
    bunny_core_db_read_unlock(core, slot);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_set_default_sync_interval_hours(bunny_core_t *core, int hours)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    bunny_core_db_lock(core);
    bunny_db_result_t result = bunny_db_settings_set_default_interval_hours(core->db, hours);
    bunny_core_db_unlock(core);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_search_set_group(bunny_core_t *core, int64_t search_id, int64_t group_id)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    bunny_core_db_lock(core);
    bunny_db_result_t result = bunny_db_search_set_group(core->db, search_id, group_id);
    bunny_core_db_unlock(core);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_group_create(bunny_core_t *core, const char *name, bool pinned, int64_t *out_id)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    bunny_core_db_lock(core);
    bunny_db_result_t result = bunny_db_group_create(core->db, name, pinned, out_id);
    bunny_core_db_unlock(core);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_group_list(bunny_core_t *core, bunny_db_group_list_t *out_list)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    size_t slot;
    bunny_db_t *read_db = bunny_core_db_read_lock(core, &slot);
    bunny_db_result_t result = bunny_db_group_list(read_db, out_list);
    bunny_core_db_read_unlock(core, slot);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_group_update(bunny_core_t *core, int64_t group_id, const char *name, bool pinned)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    bunny_core_db_lock(core);
    bunny_db_result_t result = bunny_db_group_update(core->db, group_id, name, pinned);
    bunny_core_db_unlock(core);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_group_delete(bunny_core_t *core, int64_t group_id)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    bunny_core_db_lock(core);
    bunny_db_result_t result = bunny_db_group_delete(core->db, group_id);
    bunny_core_db_unlock(core);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_search_set_pinned(bunny_core_t *core, int64_t search_id, bool pinned)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    bunny_core_db_lock(core);
    bunny_db_result_t result = bunny_db_search_set_pinned(core->db, search_id, pinned);
    bunny_core_db_unlock(core);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_search_touch_last_viewed(bunny_core_t *core, int64_t search_id)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    bunny_core_db_lock(core);
    bunny_db_result_t result = bunny_db_search_touch_last_viewed(core->db, search_id);
    bunny_core_db_unlock(core);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_search_delete(bunny_core_t *core, int64_t search_id)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    bunny_core_db_lock(core);
    bunny_db_result_t result = bunny_db_search_delete(core->db, search_id);
    bunny_core_db_unlock(core);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_search_list(bunny_core_t *core, bunny_db_search_list_t *out_list)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    size_t slot;
    bunny_db_t *read_db = bunny_core_db_read_lock(core, &slot);
    bunny_db_result_t result = bunny_db_search_list(read_db, out_list);
    bunny_core_db_read_unlock(core, slot);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_search_list_posts(bunny_core_t *core, int64_t search_id, bool unseen_only, bunny_db_post_list_t *out_list)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    size_t slot;
    bunny_db_t *read_db = bunny_core_db_read_lock(core, &slot);
    bunny_db_result_t result = bunny_db_search_list_posts(read_db, search_id, unseen_only, out_list);
    bunny_core_db_read_unlock(core, slot);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_post_get_by_id(bunny_core_t *core, int64_t post_id, bunny_db_post_t *out_post)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    size_t slot;
    bunny_db_t *read_db = bunny_core_db_read_lock(core, &slot);
    bunny_db_result_t result = bunny_db_post_get_by_id(read_db, post_id, out_post);
    bunny_core_db_read_unlock(core, slot);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_tag_autocomplete(bunny_core_t *core, bunny_db_site_t site, const char *prefix, int limit, bunny_db_tag_stat_list_t *out_list)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    size_t slot;
    bunny_db_t *read_db = bunny_core_db_read_lock(core, &slot);
    bunny_db_result_t result = bunny_db_tag_autocomplete(read_db, site, prefix, limit, out_list);
    bunny_core_db_read_unlock(core, slot);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_top_favorited_tags(bunny_core_t *core, bunny_db_site_t site, int limit, bunny_db_tag_stat_list_t *out_list)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    size_t slot;
    bunny_db_t *read_db = bunny_core_db_read_lock(core, &slot);
    bunny_db_result_t result = bunny_db_top_favorited_tags(read_db, site, limit, out_list);
    bunny_core_db_read_unlock(core, slot);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_top_used_tags(bunny_core_t *core, bunny_db_site_t site, int limit, bunny_db_tag_stat_list_t *out_list)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    size_t slot;
    bunny_db_t *read_db = bunny_core_db_read_lock(core, &slot);
    bunny_db_result_t result = bunny_db_top_used_tags(read_db, site, limit, out_list);
    bunny_core_db_read_unlock(core, slot);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_post_mark_seen(bunny_core_t *core, int64_t post_id)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    bunny_core_db_lock(core);
    bunny_db_result_t result = bunny_db_post_mark_seen(core->db, post_id);
    bunny_core_db_unlock(core);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_search_mark_all_seen(bunny_core_t *core, int64_t search_id)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    bunny_core_db_lock(core);
    bunny_db_result_t result = bunny_db_search_mark_all_seen(core->db, search_id);
    bunny_core_db_unlock(core);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_post_get_tags_by_category(bunny_core_t *core, int64_t post_id, bunny_db_post_tag_list_t *out_list)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    size_t slot;
    bunny_db_t *read_db = bunny_core_db_read_lock(core, &slot);
    bunny_db_result_t result = bunny_db_post_get_tags_by_category(read_db, post_id, out_list);
    bunny_core_db_read_unlock(core, slot);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_post_get_sources(bunny_core_t *core, int64_t post_id, bunny_db_string_list_t *out_list)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    size_t slot;
    bunny_db_t *read_db = bunny_core_db_read_lock(core, &slot);
    bunny_db_result_t result = bunny_db_post_get_sources(read_db, post_id, out_list);
    bunny_core_db_read_unlock(core, slot);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_post_get_relationships(bunny_core_t *core, int64_t post_id, bunny_db_post_relationships_t *out_relationships)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    size_t slot;
    bunny_db_t *read_db = bunny_core_db_read_lock(core, &slot);
    bunny_db_result_t result = bunny_db_post_get_relationships(read_db, post_id, out_relationships);
    bunny_core_db_read_unlock(core, slot);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_post_get_pool_ids(bunny_core_t *core, int64_t post_id, bunny_db_int64_list_t *out_list)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    size_t slot;
    bunny_db_t *read_db = bunny_core_db_read_lock(core, &slot);
    bunny_db_result_t result = bunny_db_post_get_pool_ids(read_db, post_id, out_list);
    bunny_core_db_read_unlock(core, slot);
    return bunny_core_map_db_result(result);
}
