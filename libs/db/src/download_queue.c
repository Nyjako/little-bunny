#include "bunny_db/db.h"

#include <goblin/dyn_array.h>

#include <stdlib.h>
#include <string.h>

#include "internal.h"

GOBLIN_DYN_ARRAY_DECL(bunny_db_download_queue_item, bunny_db_download_queue_item_t)

bunny_db_result_t bunny_db_download_queue_add(bunny_db_t *db, int64_t post_id, int64_t *out_id)
{
    if (!db) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }

    const char *sql = "INSERT INTO download_queue (post_id) VALUES (?);";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, post_id);

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

bunny_db_result_t bunny_db_download_queue_set_status(bunny_db_t *db, int64_t id, bunny_db_download_queue_status_t status, const char *failure_reason)
{
    if (!db) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }

    const char *sql = "UPDATE download_queue SET status = ?, failure_reason = ? WHERE id = ?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_text(stmt, 1, bunny_db_download_queue_status_to_string(status), -1, SQLITE_STATIC);
    bunny_db_bind_text_or_null(stmt, 2, failure_reason);
    sqlite3_bind_int64(stmt, 3, id);

    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
}

static void fill_download_queue_item_from_row(sqlite3_stmt *stmt, bunny_db_download_queue_item_t *out)
{
    out->id = sqlite3_column_int64(stmt, 0);
    out->post_id = sqlite3_column_int64(stmt, 1);
    out->status = bunny_db_download_queue_status_from_text((const char *)sqlite3_column_text(stmt, 2));
    out->failure_reason = bunny_db_column_text_dup(stmt, 3);
    out->created_at = bunny_db_column_text_dup(stmt, 4);
}

bunny_db_result_t bunny_db_download_queue_list(bunny_db_t *db, bunny_db_download_queue_list_t *out_list)
{
    if (!db || !out_list) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));

    const char *sql = "SELECT id, post_id, status, failure_reason, created_at FROM download_queue ORDER BY id;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }

    bunny_db_download_queue_item_array arr;
    bunny_db_download_queue_item_array_init(&arr);

    int rc;
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        bunny_db_download_queue_item_t item;
        memset(&item, 0, sizeof(item));
        fill_download_queue_item_from_row(stmt, &item);
        if (!bunny_db_download_queue_item_array_push(&arr, item)) {
            sqlite3_finalize(stmt);
            bunny_db_download_queue_item_free(&item);
            for (size_t i = 0; i < arr.count; i++) {
                bunny_db_download_queue_item_free(&arr.items[i]);
            }
            bunny_db_download_queue_item_array_free(&arr);
            return BUNNY_DB_ERR_UNKNOWN;
        }
    }
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        for (size_t i = 0; i < arr.count; i++) {
            bunny_db_download_queue_item_free(&arr.items[i]);
        }
        bunny_db_download_queue_item_array_free(&arr);
        return bunny_db_sqlite_rc_to_result(rc);
    }

    out_list->items = arr.items;
    out_list->count = arr.count;
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_download_queue_clear_finished(bunny_db_t *db)
{
    if (!db) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }

    const char *sql = "DELETE FROM download_queue WHERE status IN ('succeeded', 'checksum_mismatch', 'failed');";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }

    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
}
