#include "bunny_db/db.h"

#include <stdlib.h>
#include <string.h>

#include "internal.h"

bunny_db_result_t bunny_db_download_record(bunny_db_t *db, int64_t post_id, const char *file_path, const char *checksum_md5, bool verified, int64_t *out_id)
{
    if (!db || !file_path) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    const char *sql = "INSERT INTO downloads (post_id, file_path, checksum_md5, checksum_verified) VALUES (?, ?, ?, ?);";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, post_id);
    sqlite3_bind_text(stmt, 2, file_path, -1, SQLITE_TRANSIENT);
    bunny_db_bind_text_or_null(stmt, 3, checksum_md5);
    sqlite3_bind_int(stmt, 4, verified ? 1 : 0);

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

static void fill_download_from_row(sqlite3_stmt *stmt, bunny_db_download_t *out)
{
    out->id = sqlite3_column_int64(stmt, 0);
    out->post_id = sqlite3_column_int64(stmt, 1);
    out->file_path = bunny_db_column_text_dup(stmt, 2);
    out->checksum_md5 = bunny_db_column_text_dup(stmt, 3);
    out->checksum_verified = sqlite3_column_int(stmt, 4) != 0;
    out->downloaded_at = bunny_db_column_text_dup(stmt, 5);
}

bunny_db_result_t bunny_db_download_list_for_post(bunny_db_t *db, int64_t post_id, bunny_db_download_list_t *out_list)
{
    if (!db || !out_list) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));

    const char *sql = "SELECT id, post_id, file_path, checksum_md5, checksum_verified, downloaded_at "
                      "FROM downloads WHERE post_id = ? ORDER BY downloaded_at DESC;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, post_id);

    size_t capacity = 0;
    size_t count = 0;
    bunny_db_download_t *items = NULL;
    int rc;
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        if (count == capacity) {
            capacity = capacity == 0 ? 8 : capacity * 2;
            bunny_db_download_t *new_items = realloc(items, capacity * sizeof(bunny_db_download_t));
            if (!new_items) {
                sqlite3_finalize(stmt);
                for (size_t i = 0; i < count; i++) {
                    bunny_db_download_free(&items[i]);
                }
                free(items);
                return BUNNY_DB_ERR_UNKNOWN;
            }
            items = new_items;
        }
        memset(&items[count], 0, sizeof(items[count]));
        fill_download_from_row(stmt, &items[count]);
        count++;
    }
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        for (size_t i = 0; i < count; i++) {
            bunny_db_download_free(&items[i]);
        }
        free(items);
        return bunny_db_sqlite_rc_to_result(rc);
    }

    out_list->items = items;
    out_list->count = count;
    return BUNNY_DB_OK;
}
