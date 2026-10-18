#include "bunny_db/db.h"

#include "internal.h"

bunny_db_result_t bunny_db_settings_get_default_interval_hours(bunny_db_t *db, int *out_hours)
{
    if (!db || !out_hours) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }

    const char *sql = "SELECT default_sync_interval_hours FROM server_settings WHERE id = 1;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }

    int rc = sqlite3_step(stmt);
    if (rc == SQLITE_ROW) {
        *out_hours = sqlite3_column_int(stmt, 0);
        sqlite3_finalize(stmt);
        return BUNNY_DB_OK;
    }
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? BUNNY_DB_ERR_NOT_FOUND : bunny_db_sqlite_rc_to_result(rc);
}

bunny_db_result_t bunny_db_settings_set_default_interval_hours(bunny_db_t *db, int hours)
{
    if (!db || hours <= 0) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }

    const char *sql = "UPDATE server_settings SET default_sync_interval_hours = ? WHERE id = 1;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int(stmt, 1, hours);

    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
}

bunny_db_result_t bunny_db_settings_get_pool_positions_backfilled(bunny_db_t *db, bool *out_done)
{
    if (!db || !out_done) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }

    const char *sql = "SELECT pool_positions_backfilled FROM server_settings WHERE id = 1;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }

    int rc = sqlite3_step(stmt);
    if (rc == SQLITE_ROW) {
        *out_done = sqlite3_column_int(stmt, 0) != 0;
        sqlite3_finalize(stmt);
        return BUNNY_DB_OK;
    }
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? BUNNY_DB_ERR_NOT_FOUND : bunny_db_sqlite_rc_to_result(rc);
}

bunny_db_result_t bunny_db_settings_set_pool_positions_backfilled(bunny_db_t *db, bool done)
{
    if (!db) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }

    const char *sql = "UPDATE server_settings SET pool_positions_backfilled = ? WHERE id = 1;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int(stmt, 1, done ? 1 : 0);

    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
}
