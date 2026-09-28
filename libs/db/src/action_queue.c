#include "bunny_db/db.h"

#include <goblin/dyn_array.h>

#include <stdlib.h>
#include <string.h>

#include "internal.h"

GOBLIN_DYN_ARRAY_DECL(bunny_db_action, bunny_db_action_t)

bunny_db_result_t bunny_db_action_queue_add(bunny_db_t *db, int64_t post_id, bunny_db_action_type_t action_type, const char *payload, int64_t *out_id)
{
    if (!db) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }

    const char *sql = "INSERT INTO action_queue (post_id, action_type, payload) VALUES (?, ?, ?);";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, post_id);
    sqlite3_bind_text(stmt, 2, bunny_db_action_type_to_string(action_type), -1, SQLITE_STATIC);
    bunny_db_bind_text_or_null(stmt, 3, payload);

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

static void fill_action_from_row(sqlite3_stmt *stmt, bunny_db_action_t *out)
{
    out->id = sqlite3_column_int64(stmt, 0);
    out->post_id = sqlite3_column_int64(stmt, 1);
    out->action_type = bunny_db_action_type_from_text((const char *)sqlite3_column_text(stmt, 2));
    out->payload = bunny_db_column_text_dup(stmt, 3);
    out->status = bunny_db_action_status_from_text((const char *)sqlite3_column_text(stmt, 4));
    out->created_at = bunny_db_column_text_dup(stmt, 5);
    out->attempted_at = bunny_db_column_text_dup(stmt, 6);
    out->error_message = bunny_db_column_text_dup(stmt, 7);
}

bunny_db_result_t bunny_db_action_queue_list_pending(bunny_db_t *db, bunny_db_action_list_t *out_list)
{
    if (!db || !out_list) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));

    const char *sql = "SELECT id, post_id, action_type, payload, status, created_at, attempted_at, error_message "
                      "FROM action_queue WHERE status = 'pending' ORDER BY id;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }

    bunny_db_action_array arr;
    bunny_db_action_array_init(&arr);

    int rc;
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        bunny_db_action_t item;
        memset(&item, 0, sizeof(item));
        fill_action_from_row(stmt, &item);
        if (!bunny_db_action_array_push(&arr, item)) {
            sqlite3_finalize(stmt);
            bunny_db_action_free(&item);
            for (size_t i = 0; i < arr.count; i++) {
                bunny_db_action_free(&arr.items[i]);
            }
            bunny_db_action_array_free(&arr);
            return BUNNY_DB_ERR_UNKNOWN;
        }
    }
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        for (size_t i = 0; i < arr.count; i++) {
            bunny_db_action_free(&arr.items[i]);
        }
        bunny_db_action_array_free(&arr);
        return bunny_db_sqlite_rc_to_result(rc);
    }

    out_list->items = arr.items;
    out_list->count = arr.count;
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_action_queue_mark_done(bunny_db_t *db, int64_t action_id)
{
    if (!db) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }

    const char *sql = "UPDATE action_queue SET status = 'done', attempted_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = ?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, action_id);

    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
}

bunny_db_result_t bunny_db_action_queue_mark_failed(bunny_db_t *db, int64_t action_id, const char *error_message)
{
    if (!db) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }

    const char *sql = "UPDATE action_queue SET status = 'failed', attempted_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), error_message = ? WHERE id = ?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    bunny_db_bind_text_or_null(stmt, 1, error_message);
    sqlite3_bind_int64(stmt, 2, action_id);

    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
}
