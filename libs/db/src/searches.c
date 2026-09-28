#include "bunny_db/db.h"

#include <stdlib.h>
#include <string.h>

#include "internal.h"

bunny_db_result_t bunny_db_search_create(bunny_db_t *db, bunny_db_site_t site, const char *label, const char *query, int interval_hours, int64_t *out_id)
{
    if (!db || !label || !query) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }

    const char *sql = "INSERT INTO searches (site, label, query, interval_hours) VALUES (?, ?, ?, ?);";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }

    sqlite3_bind_text(stmt, 1, bunny_db_site_to_string(site), -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 2, label, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 3, query, -1, SQLITE_STATIC);
    sqlite3_bind_int(stmt, 4, interval_hours > 0 ? interval_hours : 24);

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

static void fill_search_from_row(sqlite3_stmt *stmt, bunny_db_search_t *out)
{
    out->id = sqlite3_column_int64(stmt, 0);
    out->site = bunny_db_site_from_text((const char *)sqlite3_column_text(stmt, 1));
    out->label = bunny_db_column_text_dup(stmt, 2);
    out->query = bunny_db_column_text_dup(stmt, 3);
    out->interval_hours = sqlite3_column_int(stmt, 4);
    out->created_at = bunny_db_column_text_dup(stmt, 5);
    out->last_run_at = bunny_db_column_text_dup(stmt, 6);
}

bunny_db_result_t bunny_db_search_list(bunny_db_t *db, bunny_db_search_list_t *out_list)
{
    if (!db || !out_list) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));

    const char *sql = "SELECT id, site, label, query, interval_hours, created_at, last_run_at FROM searches ORDER BY id;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }

    size_t capacity = 0;
    bunny_db_search_t *items = NULL;
    size_t count = 0;

    int rc;
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        if (count == capacity) {
            capacity = capacity == 0 ? 8 : capacity * 2;
            bunny_db_search_t *new_items = realloc(items, capacity * sizeof(bunny_db_search_t));
            if (!new_items) {
                sqlite3_finalize(stmt);
                for (size_t i = 0; i < count; i++) {
                    bunny_db_search_free(&items[i]);
                }
                free(items);
                return BUNNY_DB_ERR_UNKNOWN;
            }
            items = new_items;
        }
        memset(&items[count], 0, sizeof(items[count]));
        fill_search_from_row(stmt, &items[count]);
        count++;
    }
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        for (size_t i = 0; i < count; i++) {
            bunny_db_search_free(&items[i]);
        }
        free(items);
        return bunny_db_sqlite_rc_to_result(rc);
    }

    out_list->items = items;
    out_list->count = count;
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
