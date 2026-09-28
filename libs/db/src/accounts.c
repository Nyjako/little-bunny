#include "bunny_db/db.h"

#include <string.h>

#include "internal.h"

bunny_db_result_t bunny_db_account_set(bunny_db_t *db, bunny_db_site_t site, const char *username, const char *secret)
{
    if (!db || !username || !secret) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }

    const char *sql = "INSERT INTO accounts (site, username, secret) VALUES (?, ?, ?) "
                      "ON CONFLICT(site) DO UPDATE SET username = excluded.username, secret = excluded.secret;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_text(stmt, 1, bunny_db_site_to_string(site), -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 2, username, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 3, secret, -1, SQLITE_TRANSIENT);

    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
}

bunny_db_result_t bunny_db_account_get(bunny_db_t *db, bunny_db_site_t site, bunny_db_account_t *out_account)
{
    if (!db || !out_account) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    memset(out_account, 0, sizeof(*out_account));

    const char *sql = "SELECT id, username, secret, created_at FROM accounts WHERE site = ?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_text(stmt, 1, bunny_db_site_to_string(site), -1, SQLITE_STATIC);

    int rc = sqlite3_step(stmt);
    if (rc == SQLITE_ROW) {
        out_account->id = sqlite3_column_int64(stmt, 0);
        out_account->site = site;
        out_account->username = bunny_db_column_text_dup(stmt, 1);
        out_account->secret = bunny_db_column_text_dup(stmt, 2);
        out_account->created_at = bunny_db_column_text_dup(stmt, 3);
        sqlite3_finalize(stmt);
        return BUNNY_DB_OK;
    }
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? BUNNY_DB_ERR_NOT_FOUND : bunny_db_sqlite_rc_to_result(rc);
}

bunny_db_result_t bunny_db_account_delete(bunny_db_t *db, bunny_db_site_t site)
{
    if (!db) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }

    const char *sql = "DELETE FROM accounts WHERE site = ?;";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_text(stmt, 1, bunny_db_site_to_string(site), -1, SQLITE_STATIC);

    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
}
