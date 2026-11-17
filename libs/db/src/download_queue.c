#include "bunny_db/db.h"

#include <goblin/dyn_array.h>

#include <stdlib.h>
#include <string.h>

#include "internal.h"

GOBLIN_DYN_ARRAY_DECL(bunny_db_download_queue_item, bunny_db_download_queue_item_t)

bunny_db_result_t bunny_db_download_queue_add(bunny_db_t *db, int64_t post_id, int64_t pool_id, const char *pool_name, int pool_page, int64_t *out_id)
{
    if (!db) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }

    const char *sql = "INSERT INTO download_queue (post_id, pool_id, pool_name, pool_page) VALUES (?, ?, ?, ?);";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, post_id);
    sqlite3_bind_int64(stmt, 2, pool_id);
    bunny_db_bind_text_or_null(stmt, 3, pool_name);
    sqlite3_bind_int(stmt, 4, pool_page);

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
    out->pool_id = sqlite3_column_int64(stmt, 5);
    out->pool_name = bunny_db_column_text_dup(stmt, 6);
    out->pool_page = sqlite3_column_int(stmt, 7);
}

bunny_db_result_t bunny_db_download_queue_list(bunny_db_t *db, bunny_db_download_queue_list_t *out_list)
{
    if (!db || !out_list) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));

    const char *sql = "SELECT id, post_id, status, failure_reason, created_at, pool_id, pool_name, pool_page FROM download_queue ORDER BY id;";
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

bunny_db_result_t bunny_db_download_queue_claim_next(bunny_db_t *db, bunny_db_download_queue_item_t *out_item, bool *out_found)
{
    if (!db || !out_item || !out_found) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_item, 0, sizeof(*out_item));
    *out_found = false;

    const char *select_sql = "SELECT id, post_id, status, failure_reason, created_at, pool_id, pool_name, pool_page FROM download_queue WHERE status = 'queued' ORDER BY id LIMIT 1;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, select_sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }

    int rc = sqlite3_step(stmt);
    if (rc == SQLITE_ROW) {
        fill_download_queue_item_from_row(stmt, out_item);
        *out_found = true;
    }
    sqlite3_finalize(stmt);

    if (!*out_found) {
        return rc == SQLITE_DONE ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
    }

    bunny_db_result_t set_result = bunny_db_download_queue_set_status(db, out_item->id, BUNNY_DB_DOWNLOAD_QUEUE_DOWNLOADING, NULL);
    if (set_result != BUNNY_DB_OK) {
        bunny_db_download_queue_item_free(out_item);
        *out_found = false;
        return set_result;
    }
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_download_queue_count_queued(bunny_db_t *db, int *out_count)
{
    if (!db || !out_count) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    *out_count = 0;

    const char *sql = "SELECT COUNT(*) FROM download_queue WHERE status = 'queued';";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }

    int rc = sqlite3_step(stmt);
    if (rc == SQLITE_ROW) {
        *out_count = sqlite3_column_int(stmt, 0);
    }
    sqlite3_finalize(stmt);

    return rc == SQLITE_ROW ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
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
