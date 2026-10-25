#include "bunny_db/db.h"

#include <goblin/dyn_array.h>

#include <stdlib.h>
#include <string.h>

#include "internal.h"

GOBLIN_DYN_ARRAY_DECL(bunny_db_tag_stat, bunny_db_tag_stat_t)

bunny_db_result_t bunny_db_top_favorited_tags(bunny_db_t *db, bunny_db_site_t site, int limit, bunny_db_tag_stat_list_t *out_list)
{
    if (!db || !out_list) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));

    const char *sql = "SELECT t.name, COUNT(*) AS n "
                      "FROM tags t "
                      "JOIN post_tags pt ON pt.tag_id = t.id "
                      "JOIN favorites f ON f.post_id = pt.post_id "
                      "WHERE t.site = ? "
                      "GROUP BY t.id "
                      "ORDER BY n DESC, t.name ASC "
                      "LIMIT ?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_text(stmt, 1, bunny_db_site_to_string(site), -1, SQLITE_STATIC);
    sqlite3_bind_int(stmt, 2, limit > 0 ? limit : 10);

    bunny_db_tag_stat_array arr;
    bunny_db_tag_stat_array_init(&arr);

    int rc;
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        bunny_db_tag_stat_t item;
        item.name = bunny_db_column_text_dup(stmt, 0);
        item.count = sqlite3_column_int(stmt, 1);
        if (!bunny_db_tag_stat_array_push(&arr, item)) {
            sqlite3_finalize(stmt);
            bunny_db_tag_stat_free(&item);
            for (size_t i = 0; i < arr.count; i++) {
                bunny_db_tag_stat_free(&arr.items[i]);
            }
            bunny_db_tag_stat_array_free(&arr);
            return BUNNY_DB_ERR_UNKNOWN;
        }
    }
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        for (size_t i = 0; i < arr.count; i++) {
            bunny_db_tag_stat_free(&arr.items[i]);
        }
        bunny_db_tag_stat_array_free(&arr);
        return bunny_db_sqlite_rc_to_result(rc);
    }

    out_list->items = arr.items;
    out_list->count = arr.count;
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_top_used_tags(bunny_db_t *db, bunny_db_site_t site, int limit, bunny_db_tag_stat_list_t *out_list)
{
    if (!db || !out_list) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));

    /* Same shape as bunny_db_top_favorited_tags, minus the JOIN favorites --
     * ranks every synced post's tags, not just favorited ones (M14.4). */
    const char *sql = "SELECT t.name, COUNT(*) AS n "
                      "FROM tags t "
                      "JOIN post_tags pt ON pt.tag_id = t.id "
                      "WHERE t.site = ? "
                      "GROUP BY t.id "
                      "ORDER BY n DESC, t.name ASC "
                      "LIMIT ?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_text(stmt, 1, bunny_db_site_to_string(site), -1, SQLITE_STATIC);
    sqlite3_bind_int(stmt, 2, limit > 0 ? limit : 10);

    bunny_db_tag_stat_array arr;
    bunny_db_tag_stat_array_init(&arr);

    int rc;
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        bunny_db_tag_stat_t item;
        item.name = bunny_db_column_text_dup(stmt, 0);
        item.count = sqlite3_column_int(stmt, 1);
        if (!bunny_db_tag_stat_array_push(&arr, item)) {
            sqlite3_finalize(stmt);
            bunny_db_tag_stat_free(&item);
            for (size_t i = 0; i < arr.count; i++) {
                bunny_db_tag_stat_free(&arr.items[i]);
            }
            bunny_db_tag_stat_array_free(&arr);
            return BUNNY_DB_ERR_UNKNOWN;
        }
    }
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        for (size_t i = 0; i < arr.count; i++) {
            bunny_db_tag_stat_free(&arr.items[i]);
        }
        bunny_db_tag_stat_array_free(&arr);
        return bunny_db_sqlite_rc_to_result(rc);
    }

    out_list->items = arr.items;
    out_list->count = arr.count;
    return BUNNY_DB_OK;
}

/* Escapes '\', '%', and '_' (in that order, so the escape char introduced for
 * '%'/'_' isn't itself re-escaped) so `prefix` is matched literally by SQL
 * LIKE, then appends a trailing '%' for the "starts with" match. Caller owns
 * the returned buffer. */
static char *build_like_prefix_pattern(const char *prefix)
{
    size_t len = strlen(prefix);
    char *pattern = malloc(len * 2 + 2); /* worst case: every char escaped, plus trailing '%' and NUL */
    if (!pattern) {
        return NULL;
    }

    size_t j = 0;
    for (size_t i = 0; i < len; i++) {
        char c = prefix[i];
        if (c == '\\' || c == '%' || c == '_') {
            pattern[j++] = '\\';
        }
        pattern[j++] = c;
    }
    pattern[j++] = '%';
    pattern[j] = '\0';
    return pattern;
}

/* Steps `stmt` (already bound, SELECT <name>, <count> ... in that column
 * order) to completion, collecting rows into *out_list. Shared by
 * bunny_db_top_favorited_pools/bunny_db_top_viewed_searches below -- the
 * step-and-collect loop is otherwise identical to every other function in
 * this file, but those predate this helper and aren't worth the churn of
 * retrofitting. Always finalizes `stmt`, even on error. */
static bunny_db_result_t collect_tag_stat_rows(sqlite3_stmt *stmt, bunny_db_tag_stat_list_t *out_list)
{
    bunny_db_tag_stat_array arr;
    bunny_db_tag_stat_array_init(&arr);

    int rc;
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        bunny_db_tag_stat_t item;
        item.name = bunny_db_column_text_dup(stmt, 0);
        item.count = sqlite3_column_int(stmt, 1);
        if (!bunny_db_tag_stat_array_push(&arr, item)) {
            sqlite3_finalize(stmt);
            bunny_db_tag_stat_free(&item);
            for (size_t i = 0; i < arr.count; i++) {
                bunny_db_tag_stat_free(&arr.items[i]);
            }
            bunny_db_tag_stat_array_free(&arr);
            return BUNNY_DB_ERR_UNKNOWN;
        }
    }
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        for (size_t i = 0; i < arr.count; i++) {
            bunny_db_tag_stat_free(&arr.items[i]);
        }
        bunny_db_tag_stat_array_free(&arr);
        return bunny_db_sqlite_rc_to_result(rc);
    }

    out_list->items = arr.items;
    out_list->count = arr.count;
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_top_favorited_pools(bunny_db_t *db, bunny_db_site_t site, int limit, bunny_db_tag_stat_list_t *out_list)
{
    if (!db || !out_list) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));

    /* The 'pool:' || ... concatenation produces the same sentinel query
     * string TagBrowseScreen/bunny_core_parse_pool_id_from_query already
     * use everywhere else a pool is addressed by query text, so the report
     * consumer can hand `name` straight to a live pool browse with no
     * further formatting. */
    const char *sql = "SELECT 'pool:' || pp.pool_id, COUNT(*) AS n "
                      "FROM post_pools pp "
                      "JOIN favorites f ON f.post_id = pp.post_id "
                      "JOIN posts p ON p.id = pp.post_id "
                      "WHERE p.site = ? "
                      "GROUP BY pp.pool_id "
                      "ORDER BY n DESC "
                      "LIMIT ?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_text(stmt, 1, bunny_db_site_to_string(site), -1, SQLITE_STATIC);
    sqlite3_bind_int(stmt, 2, limit > 0 ? limit : 10);

    return collect_tag_stat_rows(stmt, out_list);
}

bunny_db_result_t bunny_db_top_viewed_searches(bunny_db_t *db, bunny_db_site_t site, int limit, bunny_db_tag_stat_list_t *out_list)
{
    if (!db || !out_list) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));

    const char *sql = "SELECT label, view_count AS n "
                      "FROM searches "
                      "WHERE site = ? AND view_count > 0 "
                      "ORDER BY n DESC, label ASC "
                      "LIMIT ?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_text(stmt, 1, bunny_db_site_to_string(site), -1, SQLITE_STATIC);
    sqlite3_bind_int(stmt, 2, limit > 0 ? limit : 10);

    return collect_tag_stat_rows(stmt, out_list);
}

bunny_db_result_t bunny_db_get_cached_stats_report(bunny_db_t *db, char **out_json, char **out_computed_at)
{
    if (!db || !out_json || !out_computed_at) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    *out_json = NULL;
    *out_computed_at = NULL;

    const char *sql = "SELECT report_json, computed_at FROM stats_report_cache WHERE id = 1;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    int rc = sqlite3_step(stmt);
    if (rc == SQLITE_ROW) {
        *out_json = bunny_db_column_text_dup(stmt, 0);
        *out_computed_at = bunny_db_column_text_dup(stmt, 1);
    }
    sqlite3_finalize(stmt);
    return (rc == SQLITE_ROW || rc == SQLITE_DONE) ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
}

bunny_db_result_t bunny_db_set_cached_stats_report(bunny_db_t *db, const char *json, const char *computed_at)
{
    if (!db || !json || !computed_at) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }

    const char *sql = "INSERT INTO stats_report_cache (id, computed_at, report_json) VALUES (1, ?, ?) "
                      "ON CONFLICT(id) DO UPDATE SET computed_at = excluded.computed_at, report_json = excluded.report_json;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_text(stmt, 1, computed_at, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 2, json, -1, SQLITE_STATIC);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
}

bunny_db_result_t bunny_db_tag_autocomplete(bunny_db_t *db, bunny_db_site_t site, const char *prefix, int limit, bunny_db_tag_stat_list_t *out_list)
{
    if (!db || !prefix || !out_list) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));

    char *pattern = build_like_prefix_pattern(prefix);
    if (!pattern) {
        return BUNNY_DB_ERR_UNKNOWN;
    }

    const char *sql = "SELECT t.name, COUNT(pt.post_id) AS n "
                      "FROM tags t "
                      "LEFT JOIN post_tags pt ON pt.tag_id = t.id "
                      "WHERE t.site = ? AND t.name LIKE ? ESCAPE '\\' "
                      "GROUP BY t.id "
                      "ORDER BY n DESC, t.name ASC "
                      "LIMIT ?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        free(pattern);
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_text(stmt, 1, bunny_db_site_to_string(site), -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 2, pattern, -1, SQLITE_TRANSIENT);
    sqlite3_bind_int(stmt, 3, limit > 0 ? limit : 10);
    free(pattern);

    bunny_db_tag_stat_array arr;
    bunny_db_tag_stat_array_init(&arr);

    int rc;
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        bunny_db_tag_stat_t item;
        item.name = bunny_db_column_text_dup(stmt, 0);
        item.count = sqlite3_column_int(stmt, 1);
        if (!bunny_db_tag_stat_array_push(&arr, item)) {
            sqlite3_finalize(stmt);
            bunny_db_tag_stat_free(&item);
            for (size_t i = 0; i < arr.count; i++) {
                bunny_db_tag_stat_free(&arr.items[i]);
            }
            bunny_db_tag_stat_array_free(&arr);
            return BUNNY_DB_ERR_UNKNOWN;
        }
    }
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        for (size_t i = 0; i < arr.count; i++) {
            bunny_db_tag_stat_free(&arr.items[i]);
        }
        bunny_db_tag_stat_array_free(&arr);
        return bunny_db_sqlite_rc_to_result(rc);
    }

    out_list->items = arr.items;
    out_list->count = arr.count;
    return BUNNY_DB_OK;
}
