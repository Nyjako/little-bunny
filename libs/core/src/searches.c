#include "bunny_core/core.h"

#include <limits.h>

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

bunny_core_result_t bunny_core_search_merge_duplicate(bunny_core_t *core, int64_t keeper_id, int64_t duplicate_id)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    bunny_core_db_lock(core);
    bunny_db_result_t result = bunny_db_search_merge_duplicate(core->db, keeper_id, duplicate_id);
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

bunny_core_result_t bunny_core_search_list_posts(bunny_core_t *core, int64_t search_id, bool unseen_only, int rating_mask, int media_mask, int page, bunny_db_post_list_t *out_list)
{
    if (!core || page < 1) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    size_t slot;
    bunny_db_t *read_db = bunny_core_db_read_lock(core, &slot);

    /* A pool search (M26) orders by e621's own post_ids order instead of
     * the normal newest-first-by-creation-date -- same connection/lock as
     * the actual post listing below, so this doesn't cost a second round
     * trip through the pool. A favorites search (M37) is exempt from the
     * blacklist, same as a pool search (which bunny_db_pool_search_list_posts
     * never filters at all, regardless of this flag). */
    bunny_db_search_list_t searches;
    bunny_db_result_t search_list_result = bunny_db_search_list(read_db, &searches);
    int64_t pool_id = 0;
    bool is_pool = false;
    bool is_favorites = false;
    bunny_db_site_t site = BUNNY_DB_SITE_E621;
    if (search_list_result == BUNNY_DB_OK) {
        for (size_t i = 0; i < searches.count; i++) {
            if (searches.items[i].id == search_id) {
                site = searches.items[i].site;
                is_pool = bunny_core_parse_pool_id_from_query(searches.items[i].query, &pool_id);
                is_favorites = bunny_core_is_favorites_query(searches.items[i].site, searches.items[i].query);
                break;
            }
        }
        bunny_db_search_list_free(&searches);
    }

    bunny_db_result_t result = is_pool ? bunny_db_pool_search_list_posts(read_db, search_id, pool_id, unseen_only, page, out_list) : bunny_db_search_list_posts(read_db, search_id, site, unseen_only, !is_favorites, rating_mask, media_mask, page, out_list);
    bunny_core_db_read_unlock(core, slot);
    return bunny_core_map_db_result(result);
}

/* --- Slideshows (M51 v2) --------------------------------------------------
 * A persisted, download-backed slideshow -- bunny_db/slideshows.c owns the
 * rows, this file owns the pick/reroll/replace logic that decides WHAT goes
 * into those rows. Thin CRUD pass-throughs follow the exact lock/db-call/
 * unlock/map_result shape every other section of this file already uses;
 * the pick/commit/reroll/replace functions below are the real logic. */

bunny_core_result_t bunny_core_slideshow_create(bunny_core_t *core, const char *label, bool has_default_posts_per_search, int default_posts_per_search, bool has_max_total_posts, int max_total_posts, int64_t *out_id)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    bunny_core_db_lock(core);
    bunny_db_result_t result = bunny_db_slideshow_create(core->db, label, has_default_posts_per_search, default_posts_per_search, has_max_total_posts, max_total_posts, out_id);
    bunny_core_db_unlock(core);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_slideshow_update(bunny_core_t *core, int64_t slideshow_id, const char *label, bool has_default_posts_per_search, int default_posts_per_search, bool has_max_total_posts, int max_total_posts)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    bunny_core_db_lock(core);
    bunny_db_result_t result = bunny_db_slideshow_update(core->db, slideshow_id, label, has_default_posts_per_search, default_posts_per_search, has_max_total_posts, max_total_posts);
    bunny_core_db_unlock(core);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_slideshow_delete(bunny_core_t *core, int64_t slideshow_id)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    bunny_core_db_lock(core);
    bunny_db_result_t result = bunny_db_slideshow_delete(core->db, slideshow_id);
    bunny_core_db_unlock(core);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_slideshow_get(bunny_core_t *core, int64_t slideshow_id, bunny_db_slideshow_t *out_slideshow)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    size_t slot;
    bunny_db_t *read_db = bunny_core_db_read_lock(core, &slot);
    bunny_db_result_t result = bunny_db_slideshow_get(read_db, slideshow_id, out_slideshow);
    bunny_core_db_read_unlock(core, slot);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_slideshow_list(bunny_core_t *core, bunny_db_slideshow_list_t *out_list)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    size_t slot;
    bunny_db_t *read_db = bunny_core_db_read_lock(core, &slot);
    bunny_db_result_t result = bunny_db_slideshow_list(read_db, out_list);
    bunny_core_db_read_unlock(core, slot);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_slideshow_search_add(bunny_core_t *core, int64_t slideshow_id, int64_t search_id, bool has_override_count, int override_count)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    bunny_core_db_lock(core);
    bunny_db_result_t result = bunny_db_slideshow_search_add(core->db, slideshow_id, search_id, has_override_count, override_count);
    bunny_core_db_unlock(core);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_slideshow_search_remove(bunny_core_t *core, int64_t slideshow_id, int64_t search_id)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    bunny_core_db_lock(core);
    bunny_db_result_t result = bunny_db_slideshow_search_remove(core->db, slideshow_id, search_id);
    bunny_core_db_unlock(core);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_slideshow_search_list(bunny_core_t *core, int64_t slideshow_id, bunny_db_slideshow_search_list_t *out_list)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    size_t slot;
    bunny_db_t *read_db = bunny_core_db_read_lock(core, &slot);
    bunny_db_result_t result = bunny_db_slideshow_search_list(read_db, slideshow_id, out_list);
    bunny_core_db_read_unlock(core, slot);
    return bunny_core_map_db_result(result);
}

bunny_core_result_t bunny_core_slideshow_posts_list(bunny_core_t *core, int64_t slideshow_id, int64_t search_id, bunny_db_slideshow_post_list_t *out_list)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    size_t slot;
    bunny_db_t *read_db = bunny_core_db_read_lock(core, &slot);
    bunny_db_result_t result = bunny_db_slideshow_posts_list(read_db, slideshow_id, search_id, out_list);
    bunny_core_db_read_unlock(core, slot);
    return bunny_core_map_db_result(result);
}

/* Shared by bunny_core_slideshow_pick_posts_for_search (which takes its own
 * read lock) and bunny_core_slideshow_search_commit_picks/_replace_post
 * (which already hold the WRITE lock when they need this -- bunny_core's
 * lock pair is explicitly not reentrant, so this takes a bunny_db_t*
 * directly rather than a bunny_core_t pointer plus its own locking, letting both callers
 * share the exact same resolution/pick/filter logic without ever locking
 * twice). Resolves search_id's own site/pool-ness/favorites-ness (same
 * lookup bunny_core_search_list_posts does for a single search), picks via
 * the pool-random or tag/favorites-random DB function depending on which
 * kind of search this is -- no longer excluding pools, lifting M51 v1's own
 * limitation -- then filters out anything already in excluded_post_ids and
 * truncates to count. Oversamples the DB request by excluded_count so
 * filtering still has a reasonable shot at reaching `count`; may still
 * return fewer, same "can return fewer than requested" precedent every
 * random-pick function in this codebase already accepts. `slideshow_id` (0
 * means "none") additionally excludes anything matching that slideshow's own
 * per-slideshow blacklist -- applies regardless of is_pool/is_favorites,
 * unlike the per-site blacklist just above (see
 * bunny_db_search_list_posts_random/bunny_db_pool_search_list_posts_random's
 * own doc comments on why). */
static bunny_core_result_t bunny_core_slideshow_pick_posts_for_search_locked(bunny_db_t *db, int64_t search_id, int64_t slideshow_id, int count, const int64_t *excluded_post_ids, size_t excluded_count, int rating_mask, int media_mask, bunny_db_post_list_t *out_list)
{
    memset(out_list, 0, sizeof(*out_list));
    if (count <= 0) {
        return BUNNY_CORE_OK;
    }

    bunny_db_search_list_t searches;
    bunny_db_result_t search_list_result = bunny_db_search_list(db, &searches);
    if (search_list_result != BUNNY_DB_OK) {
        return bunny_core_map_db_result(search_list_result);
    }
    bool found = false, is_pool = false, is_favorites = false;
    int64_t pool_id = 0;
    bunny_db_site_t site = BUNNY_DB_SITE_E621;
    for (size_t i = 0; i < searches.count; i++) {
        if (searches.items[i].id == search_id) {
            found = true;
            site = searches.items[i].site;
            is_pool = bunny_core_parse_pool_id_from_query(searches.items[i].query, &pool_id);
            is_favorites = bunny_core_is_favorites_query(searches.items[i].site, searches.items[i].query);
            break;
        }
    }
    bunny_db_search_list_free(&searches);
    if (!found) {
        return BUNNY_CORE_ERR_NOT_FOUND;
    }

    /* Oversampling by excluded_count is only useful up to a point -- cap it
     * so a slideshow with thousands of already-committed posts can't force
     * an unreasonably large single query. */
    long long request_count = (long long)count + (long long)excluded_count;
    if (request_count > INT_MAX) {
        request_count = INT_MAX;
    }

    bunny_db_post_list_t candidates;
    bunny_db_result_t result;
    if (is_pool) {
        result = bunny_db_pool_search_list_posts_random(db, search_id, pool_id, slideshow_id, (int)request_count, &candidates);
    } else {
        int64_t ids[] = {search_id};
        bunny_db_site_t sites[] = {site};
        bool apply_blacklist[] = {!is_favorites};
        result = bunny_db_search_list_posts_random(db, ids, sites, apply_blacklist, 1, slideshow_id, rating_mask, media_mask, (int)request_count, &candidates);
    }
    if (result != BUNNY_DB_OK) {
        return bunny_core_map_db_result(result);
    }

    size_t write = 0;
    for (size_t i = 0; i < candidates.count; i++) {
        bool excluded = false;
        for (size_t j = 0; j < excluded_count; j++) {
            if (candidates.items[i].id == excluded_post_ids[j]) {
                excluded = true;
                break;
            }
        }
        if (excluded) {
            bunny_db_post_free(&candidates.items[i]);
        } else {
            candidates.items[write++] = candidates.items[i];
        }
    }
    size_t take = write < (size_t)count ? write : (size_t)count;
    for (size_t i = take; i < write; i++) {
        bunny_db_post_free(&candidates.items[i]);
    }
    candidates.count = take;
    *out_list = candidates;
    return BUNNY_CORE_OK;
}

/* Has no slideshow_id of its own to scope a per-slideshow blacklist check
 * against (it predates that feature, and picks for search_id in the
 * abstract rather than for any one slideshow) -- passes 0 ("none") to
 * `_locked` below, so a pick through THIS entry point is never filtered by
 * any per-slideshow exclusion. Confirmed unreachable from any live Dart/
 * server caller today (test-only + raw FFI); see
 * test_slideshow_pick_posts_for_search_is_unaffected_by_any_slideshow_blacklist
 * for a regression test documenting this explicitly. The real, live
 * orchestration path is bunny_core_slideshow_search_commit_picks below,
 * which DOES have a slideshow_id and passes it through. */
bunny_core_result_t bunny_core_slideshow_pick_posts_for_search(bunny_core_t *core, int64_t search_id, int count, const int64_t *excluded_post_ids, size_t excluded_count, int rating_mask, int media_mask, bunny_db_post_list_t *out_list)
{
    if (!core || !out_list) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    size_t slot;
    bunny_db_t *read_db = bunny_core_db_read_lock(core, &slot);
    bunny_core_result_t result = bunny_core_slideshow_pick_posts_for_search_locked(read_db, search_id, 0, count, excluded_post_ids, excluded_count, rating_mask, media_mask, out_list);
    bunny_core_db_read_unlock(core, slot);
    return result;
}

/* The real orchestration: resolves search_id's effective post count
 * (its own override_count if set, else the slideshow's own
 * default_posts_per_search, else "no cap"), trims that against the
 * slideshow's own max_total_posts (counting every OTHER search's current
 * picks, since this search's own old picks are about to be replaced
 * wholesale and shouldn't count against the new budget twice), picks fresh
 * posts excluding every post already committed anywhere in this slideshow,
 * then commits via bunny_db_slideshow_posts_set. Used both for a search's
 * first-ever commit (just added) and for "reroll this search" (old picks
 * dropped, new ones committed) -- identical operation either way. */
bunny_core_result_t bunny_core_slideshow_search_commit_picks(bunny_core_t *core, int64_t slideshow_id, int64_t search_id)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    bunny_core_db_lock(core);

    bunny_db_slideshow_t slideshow;
    bunny_db_result_t result = bunny_db_slideshow_get(core->db, slideshow_id, &slideshow);
    if (result != BUNNY_DB_OK) {
        bunny_core_db_unlock(core);
        return bunny_core_map_db_result(result);
    }
    bool has_max_total_posts = slideshow.has_max_total_posts;
    int max_total_posts = slideshow.max_total_posts;
    bool has_default_posts_per_search = slideshow.has_default_posts_per_search;
    int default_posts_per_search = slideshow.default_posts_per_search;
    bunny_db_slideshow_free(&slideshow);

    bunny_db_slideshow_search_list_t links;
    result = bunny_db_slideshow_search_list(core->db, slideshow_id, &links);
    if (result != BUNNY_DB_OK) {
        bunny_core_db_unlock(core);
        return bunny_core_map_db_result(result);
    }
    bool link_found = false;
    bool has_override = false;
    int override_count = 0;
    for (size_t i = 0; i < links.count; i++) {
        if (links.items[i].search_id == search_id) {
            link_found = true;
            has_override = links.items[i].has_override_count;
            override_count = links.items[i].override_count;
            break;
        }
    }
    bunny_db_slideshow_search_list_free(&links);
    if (!link_found) {
        bunny_core_db_unlock(core);
        return BUNNY_CORE_ERR_NOT_FOUND;
    }

    bool has_count = has_override || has_default_posts_per_search;
    int effective_count = has_override ? override_count : default_posts_per_search;

    bunny_db_int64_list_t all_ids;
    result = bunny_db_slideshow_all_post_ids(core->db, slideshow_id, &all_ids);
    if (result != BUNNY_DB_OK) {
        bunny_core_db_unlock(core);
        return bunny_core_map_db_result(result);
    }
    bunny_db_slideshow_post_list_t current_for_this_search;
    result = bunny_db_slideshow_posts_list(core->db, slideshow_id, search_id, &current_for_this_search);
    if (result != BUNNY_DB_OK) {
        bunny_db_int64_list_free(&all_ids);
        bunny_core_db_unlock(core);
        return bunny_core_map_db_result(result);
    }
    size_t other_total = all_ids.count - current_for_this_search.count;
    bunny_db_slideshow_post_list_free(&current_for_this_search);

    /* "No cap" (has_count false) is represented by requesting a very large
     * count -- every random-pick DB function already just LIMITs by
     * whatever's actually available, so there's no separate "unbounded"
     * code path needed anywhere below this. */
    int request_count = has_count ? effective_count : INT_MAX;
    if (has_max_total_posts) {
        long long remaining_budget = (long long)max_total_posts - (long long)other_total;
        if (remaining_budget < 0) {
            remaining_budget = 0;
        }
        if (remaining_budget < request_count) {
            request_count = (int)remaining_budget;
        }
    }

    bunny_db_post_list_t picked;
    memset(&picked, 0, sizeof(picked));
    if (request_count > 0) {
        bunny_core_result_t pick_result = bunny_core_slideshow_pick_posts_for_search_locked(core->db, search_id, slideshow_id, request_count, all_ids.items, all_ids.count, BUNNY_DB_RATING_MASK_ALL, BUNNY_DB_MEDIA_MASK_ALL, &picked);
        bunny_db_int64_list_free(&all_ids);
        if (pick_result != BUNNY_CORE_OK) {
            bunny_core_db_unlock(core);
            return pick_result;
        }
    } else {
        bunny_db_int64_list_free(&all_ids);
    }

    int64_t *post_ids = NULL;
    if (picked.count > 0) {
        post_ids = malloc(picked.count * sizeof(int64_t));
        if (!post_ids) {
            for (size_t i = 0; i < picked.count; i++) {
                bunny_db_post_free(&picked.items[i]);
            }
            free(picked.items);
            bunny_core_db_unlock(core);
            return BUNNY_CORE_ERR_UNKNOWN;
        }
        for (size_t i = 0; i < picked.count; i++) {
            post_ids[i] = picked.items[i].id;
        }
    }
    bunny_db_result_t set_result = bunny_db_slideshow_posts_set(core->db, slideshow_id, search_id, post_ids, picked.count);
    free(post_ids);
    for (size_t i = 0; i < picked.count; i++) {
        bunny_db_post_free(&picked.items[i]);
    }
    free(picked.items);

    bunny_core_db_unlock(core);
    return bunny_core_map_db_result(set_result);
}

bunny_core_result_t bunny_core_slideshow_reroll_search(bunny_core_t *core, int64_t slideshow_id, int64_t search_id)
{
    return bunny_core_slideshow_search_commit_picks(core, slideshow_id, search_id);
}

/* One search at a time, in whatever order bunny_db_slideshow_search_list
 * returns them -- each commit's own exclusion set (bunny_db_slideshow_all_post_ids)
 * is re-read fresh every iteration, so a search rerolled earlier in this
 * same call is already reflected by the time a later search's own commit
 * runs, keeping the "never duplicate a post already picked in this
 * slideshow" guarantee across the whole batch, not just within one search.
 * Keeps going past one search's own failure (same precedent "check for
 * updates" already established for its own per-search loop), reporting the
 * last failure seen rather than stopping the whole reroll partway through. */
bunny_core_result_t bunny_core_slideshow_reroll_all(bunny_core_t *core, int64_t slideshow_id)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    size_t slot;
    bunny_db_t *read_db = bunny_core_db_read_lock(core, &slot);
    bunny_db_slideshow_search_list_t links;
    bunny_db_result_t result = bunny_db_slideshow_search_list(read_db, slideshow_id, &links);
    bunny_core_db_read_unlock(core, slot);
    if (result != BUNNY_DB_OK) {
        return bunny_core_map_db_result(result);
    }

    bunny_core_result_t overall = BUNNY_CORE_OK;
    for (size_t i = 0; i < links.count; i++) {
        bunny_core_result_t r = bunny_core_slideshow_search_commit_picks(core, slideshow_id, links.items[i].search_id);
        if (r != BUNNY_CORE_OK) {
            overall = r;
        }
    }
    bunny_db_slideshow_search_list_free(&links);
    return overall;
}

/* Self-healing swap-one: draws exactly one replacement post for search_id
 * (excluding every post already committed anywhere in this slideshow, same
 * exclusion set a fresh pick/reroll uses) and swaps it in for dead_post_id.
 * Returns BUNNY_CORE_ERR_NOT_FOUND if the search has nothing left to draw
 * (every remaining candidate is already committed elsewhere, or the search
 * itself is simply exhausted) -- the caller (Dart) surfaces that as
 * "couldn't find a replacement," distinct from a download failure. */
bunny_core_result_t bunny_core_slideshow_replace_post(bunny_core_t *core, int64_t slideshow_id, int64_t search_id, int64_t dead_post_id)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    bunny_core_db_lock(core);

    bunny_db_int64_list_t all_ids;
    bunny_db_result_t result = bunny_db_slideshow_all_post_ids(core->db, slideshow_id, &all_ids);
    if (result != BUNNY_DB_OK) {
        bunny_core_db_unlock(core);
        return bunny_core_map_db_result(result);
    }

    bunny_db_post_list_t picked;
    bunny_core_result_t pick_result = bunny_core_slideshow_pick_posts_for_search_locked(core->db, search_id, slideshow_id, 1, all_ids.items, all_ids.count, BUNNY_DB_RATING_MASK_ALL, BUNNY_DB_MEDIA_MASK_ALL, &picked);
    bunny_db_int64_list_free(&all_ids);
    if (pick_result != BUNNY_CORE_OK) {
        bunny_core_db_unlock(core);
        return pick_result;
    }
    if (picked.count == 0) {
        free(picked.items); /* still a valid (possibly non-NULL, zero-length) allocation even with nothing left after filtering */
        bunny_core_db_unlock(core);
        return BUNNY_CORE_ERR_NOT_FOUND;
    }

    bunny_db_result_t replace_result = bunny_db_slideshow_post_replace(core->db, slideshow_id, search_id, dead_post_id, picked.items[0].id);
    for (size_t i = 0; i < picked.count; i++) {
        bunny_db_post_free(&picked.items[i]);
    }
    free(picked.items);

    bunny_core_db_unlock(core);
    return bunny_core_map_db_result(replace_result);
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

/* A prefix shorter than this matches far too many tags for the (site, name)
 * index to narrow usefully -- each candidate tag still needs its own
 * post_tags join to count matches, which is what actually hung the server on
 * a one- or two-letter keystroke (M39). Below the minimum, skip the query
 * entirely rather than let the caller pay for it. */
#define BUNNY_CORE_TAG_AUTOCOMPLETE_MIN_PREFIX_LEN 5
#define BUNNY_CORE_TAG_AUTOCOMPLETE_MAX_RESULTS 5

bunny_core_result_t bunny_core_tag_autocomplete(bunny_core_t *core, bunny_db_site_t site, const char *prefix, int limit, bunny_db_tag_stat_list_t *out_list)
{
    if (!core || !out_list) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    if (!prefix || strlen(prefix) < BUNNY_CORE_TAG_AUTOCOMPLETE_MIN_PREFIX_LEN) {
        memset(out_list, 0, sizeof(*out_list));
        return BUNNY_CORE_OK;
    }
    int capped_limit = (limit <= 0 || limit > BUNNY_CORE_TAG_AUTOCOMPLETE_MAX_RESULTS) ? BUNNY_CORE_TAG_AUTOCOMPLETE_MAX_RESULTS : limit;
    size_t slot;
    bunny_db_t *read_db = bunny_core_db_read_lock(core, &slot);
    bunny_db_result_t result = bunny_db_tag_autocomplete(read_db, site, prefix, capped_limit, out_list);
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

bunny_core_result_t bunny_core_post_get_files(bunny_core_t *core, int64_t post_id, bunny_db_post_file_list_t *out_list)
{
    if (!core) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }
    size_t slot;
    bunny_db_t *read_db = bunny_core_db_read_lock(core, &slot);
    bunny_db_result_t result = bunny_db_post_get_files(read_db, post_id, out_list);
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
