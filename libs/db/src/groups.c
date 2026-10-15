#include "bunny_db/db.h"

#include <goblin/dyn_array.h>

#include <stdlib.h>
#include <string.h>

#include "internal.h"

GOBLIN_DYN_ARRAY_DECL(bunny_db_group, bunny_db_group_t)

bunny_db_result_t bunny_db_group_create(bunny_db_t *db, const char *name, bool pinned, int64_t *out_id)
{
    if (!db || !name || !*name) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }

    const char *sql = "INSERT INTO search_groups (name, pinned) VALUES (?, ?);";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_text(stmt, 1, name, -1, SQLITE_STATIC);
    sqlite3_bind_int(stmt, 2, pinned ? 1 : 0);

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

bunny_db_result_t bunny_db_group_list(bunny_db_t *db, bunny_db_group_list_t *out_list)
{
    if (!db || !out_list) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_list, 0, sizeof(*out_list));

    const char *sql = "SELECT id, name, pinned, created_at FROM search_groups ORDER BY id;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }

    bunny_db_group_array arr;
    bunny_db_group_array_init(&arr);

    int rc;
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        bunny_db_group_t item;
        memset(&item, 0, sizeof(item));
        item.id = sqlite3_column_int64(stmt, 0);
        item.name = bunny_db_column_text_dup(stmt, 1);
        item.pinned = sqlite3_column_int(stmt, 2) != 0;
        item.created_at = bunny_db_column_text_dup(stmt, 3);
        if (!bunny_db_group_array_push(&arr, item)) {
            sqlite3_finalize(stmt);
            bunny_db_group_free(&item);
            for (size_t i = 0; i < arr.count; i++) {
                bunny_db_group_free(&arr.items[i]);
            }
            bunny_db_group_array_free(&arr);
            return BUNNY_DB_ERR_UNKNOWN;
        }
    }
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        for (size_t i = 0; i < arr.count; i++) {
            bunny_db_group_free(&arr.items[i]);
        }
        bunny_db_group_array_free(&arr);
        return bunny_db_sqlite_rc_to_result(rc);
    }

    out_list->items = arr.items;
    out_list->count = arr.count;
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_group_update(bunny_db_t *db, int64_t group_id, const char *name, bool pinned)
{
    if (!db || !name || !*name) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }

    const char *sql = "UPDATE search_groups SET name = ?, pinned = ? WHERE id = ?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_text(stmt, 1, name, -1, SQLITE_STATIC);
    sqlite3_bind_int(stmt, 2, pinned ? 1 : 0);
    sqlite3_bind_int64(stmt, 3, group_id);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
}

bunny_db_result_t bunny_db_group_delete(bunny_db_t *db, int64_t group_id)
{
    if (!db) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }

    /* searches.group_id's ON DELETE SET NULL foreign key (see the schema.h/
     * db.c migration comments) ungroups every member search automatically
     * -- nothing extra to do here. */
    const char *sql = "DELETE FROM search_groups WHERE id = ?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, group_id);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
}
