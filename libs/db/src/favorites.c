#include "bunny_db/db.h"

#include <stdlib.h>
#include <string.h>

#include "internal.h"

bunny_db_result_t bunny_db_favorite_add(bunny_db_t *db, int64_t post_id, int stars)
{
    if (!db) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    const char *sql = "INSERT INTO favorites (post_id, stars) VALUES (?, ?) "
                      "ON CONFLICT(post_id) DO UPDATE SET stars = excluded.stars;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, post_id);
    if (stars >= 0) {
        sqlite3_bind_int(stmt, 2, stars);
    } else {
        sqlite3_bind_null(stmt, 2);
    }
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
}

bunny_db_result_t bunny_db_favorite_remove(bunny_db_t *db, int64_t post_id)
{
    if (!db) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    const char *sql = "DELETE FROM favorites WHERE post_id = ?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, post_id);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
}

bunny_db_result_t bunny_db_favorite_list(bunny_db_t *db, bunny_db_post_list_t *out_list)
{
    if (!db || !out_list) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));

    const char *sql = "SELECT " BUNNY_DB_POST_SELECT_COLUMNS BUNNY_DB_POST_SELECT_FROM_JOIN "WHERE fav.post_id IS NOT NULL "
                      "ORDER BY fav.favorited_at DESC;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }

    size_t capacity = 0;
    size_t count = 0;
    bunny_db_post_t *items = NULL;
    int rc;
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        if (count == capacity) {
            capacity = capacity == 0 ? 16 : capacity * 2;
            bunny_db_post_t *new_items = realloc(items, capacity * sizeof(bunny_db_post_t));
            if (!new_items) {
                sqlite3_finalize(stmt);
                for (size_t i = 0; i < count; i++) {
                    bunny_db_post_free(&items[i]);
                }
                free(items);
                return BUNNY_DB_ERR_UNKNOWN;
            }
            items = new_items;
        }
        memset(&items[count], 0, sizeof(items[count]));
        bunny_db_fill_post_from_row(stmt, &items[count]);
        count++;
    }
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        for (size_t i = 0; i < count; i++) {
            bunny_db_post_free(&items[i]);
        }
        free(items);
        return bunny_db_sqlite_rc_to_result(rc);
    }

    out_list->items = items;
    out_list->count = count;
    return BUNNY_DB_OK;
}
