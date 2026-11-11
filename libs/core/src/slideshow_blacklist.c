#include "bunny_core/core.h"

#include <bunny_tag_query/tag_query.h>

#include "internal.h"

bunny_core_result_t bunny_core_slideshow_blacklist_list(bunny_core_t *core, int64_t slideshow_id, bunny_db_string_list_t *out_list)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    size_t slot;
    bunny_db_t *read_db = bunny_core_db_read_lock(core, &slot);
    bunny_db_result_t result = bunny_db_slideshow_blacklist_list(read_db, slideshow_id, out_list);
    bunny_core_db_read_unlock(core, slot);
    return bunny_core_map_db_result(result);
}

/* Validated under e621's dialect always, unlike the per-site blacklist's own
 * dialect_for_site (blacklist.c) -- a slideshow has no single site of its
 * own (it can mix e621 and Inkbunny searches), so there's no one dialect to
 * pick from the slideshow itself. e621's dialect is the strict superset, so
 * this accepts any syntactically valid rule; one using OR/wildcard/group
 * syntax simply never matches against an Inkbunny-sourced post in the same
 * slideshow (see bunny_db_slideshow_blacklist_fetch_complex_rules's own doc
 * comment) rather than being rejected outright for a slideshow that happens
 * to include any Inkbunny searches. */
bunny_core_result_t bunny_core_slideshow_blacklist_add(bunny_core_t *core, int64_t slideshow_id, const char *tag)
{
    if (!core || !tag) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    if (!bunny_tag_query_validate(tag, BUNNY_TAG_QUERY_DIALECT_E621, NULL)) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    bunny_core_db_lock(core);
    bunny_db_result_t result = bunny_db_slideshow_blacklist_add(core->db, slideshow_id, tag);
    bunny_core_db_unlock(core);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_slideshow_blacklist_remove(bunny_core_t *core, int64_t slideshow_id, const char *tag)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    bunny_core_db_lock(core);
    bunny_db_result_t result = bunny_db_slideshow_blacklist_remove(core->db, slideshow_id, tag);
    bunny_core_db_unlock(core);
    return bunny_core_map_db_result(result);
}
