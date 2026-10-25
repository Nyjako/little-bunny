#include "bunny_db/db.h"

#include <goblin/dyn_array.h>

#include <stdlib.h>
#include <string.h>

#include "internal.h"

GOBLIN_DYN_ARRAY_DECL(bunny_db_search, bunny_db_search_t)

static const bunny_db_search_options_t BUNNY_DB_SEARCH_OPTIONS_DEFAULT = {false, 1, false, false};

bunny_db_result_t bunny_db_search_create(bunny_db_t *db, bunny_db_site_t site, const char *label, const char *query, int interval_hours, const bunny_db_search_options_t *options, int64_t *out_id)
{
    if (!db || !label || !query) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    if (!options) {
        options = &BUNNY_DB_SEARCH_OPTIONS_DEFAULT;
    }

    const char *sql = "INSERT INTO searches (site, label, query, interval_hours, auto_favorite, auto_favorite_stars, auto_upvote, uses_default_interval) VALUES (?, ?, ?, ?, ?, ?, ?, ?);";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }

    sqlite3_bind_text(stmt, 1, bunny_db_site_to_string(site), -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 2, label, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 3, query, -1, SQLITE_STATIC);
    sqlite3_bind_int(stmt, 4, interval_hours > 0 ? interval_hours : 24);
    sqlite3_bind_int(stmt, 5, options->auto_favorite ? 1 : 0);
    sqlite3_bind_int(stmt, 6, options->auto_favorite_stars);
    sqlite3_bind_int(stmt, 7, options->auto_upvote ? 1 : 0);
    sqlite3_bind_int(stmt, 8, options->uses_default_interval ? 1 : 0);

    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        return bunny_db_sqlite_rc_to_result(rc);
    }

    if (out_id) {
        *out_id = sqlite3_last_insert_rowid(db->handle);
    }
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_search_delete(bunny_db_t *db, int64_t search_id)
{
    if (!db) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }

    const char *sql = "DELETE FROM searches WHERE id = ?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, search_id);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
}

/* M41 -- folds duplicate_id into keeper_id: every search_results row duplicate_id
 * owns moves over to keeper_id (OR IGNORE, since (search_id, post_id) is the
 * primary key -- a post both searches already found would otherwise collide;
 * the keeper's own existing row for it just wins and duplicate_id's copy is
 * dropped), then duplicate_id itself is deleted. Deliberately doesn't touch
 * keeper_id's own label/interval_hours/auto_favorite/pinned/group_id/etc. --
 * which of two divergent duplicates to treat as the "keeper" is a decision
 * callers make (see docs/ROADMAP.md's M41 entry), not something this function
 * should second-guess. */
bunny_db_result_t bunny_db_search_merge_duplicate(bunny_db_t *db, int64_t keeper_id, int64_t duplicate_id)
{
    if (!db || keeper_id == duplicate_id) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }

    const char *move_sql = "UPDATE OR IGNORE search_results SET search_id = ? WHERE search_id = ?;";
    sqlite3_stmt *move_stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, move_sql, -1, &move_stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(move_stmt, 1, keeper_id);
    sqlite3_bind_int64(move_stmt, 2, duplicate_id);
    int rc = sqlite3_step(move_stmt);
    sqlite3_finalize(move_stmt);
    if (rc != SQLITE_DONE) {
        return bunny_db_sqlite_rc_to_result(rc);
    }

    return bunny_db_search_delete(db, duplicate_id);
}

static void fill_search_from_row(sqlite3_stmt *stmt, bunny_db_search_t *out)
{
    out->id = sqlite3_column_int64(stmt, 0);
    out->site = bunny_db_site_from_text((const char *)sqlite3_column_text(stmt, 1));
    out->label = bunny_db_column_text_dup(stmt, 2);
    out->query = bunny_db_column_text_dup(stmt, 3);
    out->interval_hours = sqlite3_column_int(stmt, 4);
    out->created_at = bunny_db_column_text_dup(stmt, 5);
    out->last_run_at = bunny_db_column_text_dup(stmt, 6);
    out->unseen_count = sqlite3_column_int(stmt, 7);
    out->total_count = sqlite3_column_int(stmt, 8);
    out->auto_favorite = sqlite3_column_int(stmt, 9) != 0;
    out->auto_favorite_stars = sqlite3_column_int(stmt, 10);
    out->auto_upvote = sqlite3_column_int(stmt, 11) != 0;
    out->pinned = sqlite3_column_int(stmt, 12) != 0;
    out->last_viewed_at = bunny_db_column_text_dup(stmt, 13);
    out->initial_sync_done = sqlite3_column_int(stmt, 14) != 0;
    out->highest_synced_external_id = sqlite3_column_int64(stmt, 15);
    out->uses_default_interval = sqlite3_column_int(stmt, 16) != 0;
    out->group_id = sqlite3_column_type(stmt, 17) == SQLITE_NULL ? 0 : sqlite3_column_int64(stmt, 17);
}

bunny_db_result_t bunny_db_search_list(bunny_db_t *db, bunny_db_search_list_t *out_list)
{
    if (!db || !out_list) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));

    /* unseen_count: how many of this search's linked posts have no
     * seen_posts row -- feeds SearchesScreen's "N new" badge without a
     * separate round trip per row. total_count (M14.1): how many posts are
     * linked at all, seen or not -- same live-subquery shape, shown
     * alongside the badge in the row's subtitle. */
    const char *sql = "SELECT s.id, s.site, s.label, s.query, s.interval_hours, s.created_at, s.last_run_at, "
                      "(SELECT COUNT(*) FROM search_results sr LEFT JOIN seen_posts seen ON seen.post_id = sr.post_id "
                      " WHERE sr.search_id = s.id AND seen.post_id IS NULL) AS unseen_count, "
                      "(SELECT COUNT(*) FROM search_results sr WHERE sr.search_id = s.id) AS total_count, "
                      "s.auto_favorite, s.auto_favorite_stars, s.auto_upvote, s.pinned, s.last_viewed_at, "
                      "s.initial_sync_done, s.highest_synced_external_id, s.uses_default_interval, s.group_id "
                      "FROM searches s ORDER BY s.id;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }

    bunny_db_search_array arr;
    bunny_db_search_array_init(&arr);

    int rc;
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        bunny_db_search_t item;
        memset(&item, 0, sizeof(item));
        fill_search_from_row(stmt, &item);
        if (!bunny_db_search_array_push(&arr, item)) {
            sqlite3_finalize(stmt);
            bunny_db_search_free(&item);
            for (size_t i = 0; i < arr.count; i++) {
                bunny_db_search_free(&arr.items[i]);
            }
            bunny_db_search_array_free(&arr);
            return BUNNY_DB_ERR_UNKNOWN;
        }
    }
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        for (size_t i = 0; i < arr.count; i++) {
            bunny_db_search_free(&arr.items[i]);
        }
        bunny_db_search_array_free(&arr);
        return bunny_db_sqlite_rc_to_result(rc);
    }

    out_list->items = arr.items;
    out_list->count = arr.count;
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_search_touch_last_run(bunny_db_t *db, int64_t search_id)
{
    if (!db) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }

    const char *sql = "UPDATE searches SET last_run_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = ?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, search_id);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
}

bunny_db_result_t bunny_db_search_touch_last_viewed(bunny_db_t *db, int64_t search_id)
{
    if (!db) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }

    /* view_count (M40) tracks visit frequency for the stats report's
     * "most-visited searches" section -- last_viewed_at alone only has the
     * most recent visit, not how many there have been. */
    const char *sql = "UPDATE searches SET last_viewed_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), view_count = view_count + 1 WHERE id = ?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, search_id);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
}

bunny_db_result_t bunny_db_search_set_pinned(bunny_db_t *db, int64_t search_id, bool pinned)
{
    if (!db) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }

    const char *sql = "UPDATE searches SET pinned = ? WHERE id = ?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int(stmt, 1, pinned ? 1 : 0);
    sqlite3_bind_int64(stmt, 2, search_id);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
}

bunny_db_result_t bunny_db_search_set_group(bunny_db_t *db, int64_t search_id, int64_t group_id)
{
    if (!db) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }

    const char *sql = "UPDATE searches SET group_id = ? WHERE id = ?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    if (group_id > 0) {
        sqlite3_bind_int64(stmt, 1, group_id);
    } else {
        sqlite3_bind_null(stmt, 1);
    }
    sqlite3_bind_int64(stmt, 2, search_id);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
}

bunny_db_result_t bunny_db_search_update_sync_progress(bunny_db_t *db, int64_t search_id, int64_t highest_external_id)
{
    if (!db) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }

    const char *sql = "UPDATE searches SET initial_sync_done = 1, highest_synced_external_id = ? WHERE id = ?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, highest_external_id);
    sqlite3_bind_int64(stmt, 2, search_id);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
}

bunny_db_result_t bunny_db_search_update(bunny_db_t *db, int64_t search_id, const char *label, const char *query, int interval_hours, const bunny_db_search_options_t *options)
{
    if (!db || !label || !query || !options) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    const char *sql = "UPDATE searches SET label = ?, query = ?, interval_hours = ?, auto_favorite = ?, auto_favorite_stars = ?, auto_upvote = ?, uses_default_interval = ? WHERE id = ?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_text(stmt, 1, label, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 2, query, -1, SQLITE_STATIC);
    sqlite3_bind_int(stmt, 3, interval_hours > 0 ? interval_hours : 24);
    sqlite3_bind_int(stmt, 4, options->auto_favorite ? 1 : 0);
    sqlite3_bind_int(stmt, 5, options->auto_favorite_stars);
    sqlite3_bind_int(stmt, 6, options->auto_upvote ? 1 : 0);
    sqlite3_bind_int(stmt, 7, options->uses_default_interval ? 1 : 0);
    sqlite3_bind_int64(stmt, 8, search_id);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
}
