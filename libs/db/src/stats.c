#include "bunny_db/db.h"

#include <stdlib.h>
#include <string.h>

#include "internal.h"

bunny_db_result_t bunny_db_top_favorited_tags(bunny_db_t *db, int limit, bunny_db_tag_stat_list_t *out_list) {
    if (!db || !out_list) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));

    const char *sql = "SELECT t.name, COUNT(*) AS n "
                       "FROM tags t "
                       "JOIN post_tags pt ON pt.tag_id = t.id "
                       "JOIN favorites f ON f.post_id = pt.post_id "
                       "GROUP BY t.id "
                       "ORDER BY n DESC, t.name ASC "
                       "LIMIT ?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int(stmt, 1, limit > 0 ? limit : 10);

    size_t capacity = 0;
    size_t count = 0;
    bunny_db_tag_stat_t *items = NULL;
    int rc;
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        if (count == capacity) {
            capacity = capacity == 0 ? 16 : capacity * 2;
            bunny_db_tag_stat_t *new_items = realloc(items, capacity * sizeof(bunny_db_tag_stat_t));
            if (!new_items) {
                sqlite3_finalize(stmt);
                for (size_t i = 0; i < count; i++) {
                    bunny_db_tag_stat_free(&items[i]);
                }
                free(items);
                return BUNNY_DB_ERR_UNKNOWN;
            }
            items = new_items;
        }
        items[count].name = bunny_db_column_text_dup(stmt, 0);
        items[count].count = sqlite3_column_int(stmt, 1);
        count++;
    }
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        for (size_t i = 0; i < count; i++) {
            bunny_db_tag_stat_free(&items[i]);
        }
        free(items);
        return bunny_db_sqlite_rc_to_result(rc);
    }

    out_list->items = items;
    out_list->count = count;
    return BUNNY_DB_OK;
}
