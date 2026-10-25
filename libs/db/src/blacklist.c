#include "bunny_db/db.h"

#include <goblin/dyn_array.h>

#include <stdlib.h>
#include <string.h>

#include "internal.h"

GOBLIN_DYN_ARRAY_DECL(bunny_db_blacklist_string, char *)

bunny_db_result_t bunny_db_blacklist_list(bunny_db_t *db, bunny_db_site_t site, bunny_db_string_list_t *out_list)
{
    if (!db || !out_list) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));

    const char *sql = "SELECT tag FROM blacklist_tags WHERE site = ? ORDER BY tag ASC;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_text(stmt, 1, bunny_db_site_to_string(site), -1, SQLITE_STATIC);

    bunny_db_blacklist_string_array arr;
    bunny_db_blacklist_string_array_init(&arr);

    int rc;
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        char *tag = bunny_db_column_text_dup(stmt, 0);
        if (!bunny_db_blacklist_string_array_push(&arr, tag)) {
            sqlite3_finalize(stmt);
            free(tag);
            for (size_t i = 0; i < arr.count; i++) {
                free(arr.items[i]);
            }
            bunny_db_blacklist_string_array_free(&arr);
            return BUNNY_DB_ERR_UNKNOWN;
        }
    }
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        for (size_t i = 0; i < arr.count; i++) {
            free(arr.items[i]);
        }
        bunny_db_blacklist_string_array_free(&arr);
        return bunny_db_sqlite_rc_to_result(rc);
    }

    out_list->items = arr.items;
    out_list->count = arr.count;
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_blacklist_add(bunny_db_t *db, bunny_db_site_t site, const char *tag)
{
    if (!db || !tag || !*tag) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    const char *sql = "INSERT OR IGNORE INTO blacklist_tags (site, tag) VALUES (?, ?);";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_text(stmt, 1, bunny_db_site_to_string(site), -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 2, tag, -1, SQLITE_TRANSIENT);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
}

bunny_db_result_t bunny_db_blacklist_remove(bunny_db_t *db, bunny_db_site_t site, const char *tag)
{
    if (!db || !tag || !*tag) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    const char *sql = "DELETE FROM blacklist_tags WHERE site = ? AND tag = ?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_text(stmt, 1, bunny_db_site_to_string(site), -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 2, tag, -1, SQLITE_TRANSIENT);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
}

bunny_db_result_t bunny_db_post_is_blacklisted(bunny_db_t *db, int64_t post_id, bool *out_is_blacklisted)
{
    if (!db || !out_is_blacklisted) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    const char *sql = "SELECT 1 FROM post_tags pt JOIN tags t ON t.id = pt.tag_id "
                      "JOIN blacklist_tags bl ON bl.site = t.site AND bl.tag = t.name "
                      "WHERE pt.post_id = ? LIMIT 1;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, post_id);
    int rc = sqlite3_step(stmt);
    *out_is_blacklisted = rc == SQLITE_ROW;
    sqlite3_finalize(stmt);
    return (rc == SQLITE_ROW || rc == SQLITE_DONE) ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
}
