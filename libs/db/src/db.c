#include "bunny_db/db.h"

#include <stdbool.h>
#include <stdlib.h>

#include "internal.h"
#include "schema.h"

/* Schema changes to a table that already shipped can't go through schema.h's
 * CREATE TABLE IF NOT EXISTS (SQLite won't add columns to an existing table
 * that way) -- they go here instead, tracked in schema_migrations so each
 * runs exactly once regardless of how many times bunny_db_open() is called
 * against the same database. */
typedef struct
{
    int version;
    const char *sql;
} bunny_db_migration_t;

static const bunny_db_migration_t BUNNY_DB_MIGRATIONS[] = {
    {1, "ALTER TABLE posts ADD COLUMN score_up INTEGER NOT NULL DEFAULT 0;"},
    {2, "ALTER TABLE posts ADD COLUMN score_down INTEGER NOT NULL DEFAULT 0;"},
};

static bunny_db_result_t bunny_db_apply_migrations(sqlite3 *handle)
{
    for (size_t i = 0; i < sizeof(BUNNY_DB_MIGRATIONS) / sizeof(BUNNY_DB_MIGRATIONS[0]); i++) {
        const bunny_db_migration_t *migration = &BUNNY_DB_MIGRATIONS[i];

        sqlite3_stmt *check_stmt = NULL;
        if (sqlite3_prepare_v2(handle, "SELECT 1 FROM schema_migrations WHERE version = ?;", -1, &check_stmt, NULL) != SQLITE_OK) {
            return BUNNY_DB_ERR_QUERY_FAILED;
        }
        sqlite3_bind_int(check_stmt, 1, migration->version);
        bool already_applied = sqlite3_step(check_stmt) == SQLITE_ROW;
        sqlite3_finalize(check_stmt);
        if (already_applied) {
            continue;
        }

        char *errmsg = NULL;
        if (sqlite3_exec(handle, migration->sql, NULL, NULL, &errmsg) != SQLITE_OK) {
            sqlite3_free(errmsg);
            return BUNNY_DB_ERR_QUERY_FAILED;
        }

        sqlite3_stmt *record_stmt = NULL;
        if (sqlite3_prepare_v2(handle, "INSERT INTO schema_migrations (version) VALUES (?);", -1, &record_stmt, NULL) != SQLITE_OK) {
            return BUNNY_DB_ERR_QUERY_FAILED;
        }
        sqlite3_bind_int(record_stmt, 1, migration->version);
        int rc = sqlite3_step(record_stmt);
        sqlite3_finalize(record_stmt);
        if (rc != SQLITE_DONE) {
            return bunny_db_sqlite_rc_to_result(rc);
        }
    }
    return BUNNY_DB_OK;
}

bunny_db_result_t bunny_db_open(const char *path, bunny_db_t **out_db)
{
    if (!path || !out_db) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }

    bunny_db_t *db = calloc(1, sizeof(bunny_db_t));
    if (!db) {
        return BUNNY_DB_ERR_UNKNOWN;
    }

    if (sqlite3_open(path, &db->handle) != SQLITE_OK) {
        sqlite3_close(db->handle);
        free(db);
        return BUNNY_DB_ERR_OPEN_FAILED;
    }

    /* BUNNY_DB_SCHEMA_SQL's first statement enables foreign_keys, which is a
     * per-connection setting SQLite doesn't persist -- every open needs it. */
    char *errmsg = NULL;
    int rc = sqlite3_exec(db->handle, BUNNY_DB_SCHEMA_SQL, NULL, NULL, &errmsg);
    if (rc != SQLITE_OK) {
        sqlite3_free(errmsg);
        sqlite3_close(db->handle);
        free(db);
        return BUNNY_DB_ERR_OPEN_FAILED;
    }

    if (bunny_db_apply_migrations(db->handle) != BUNNY_DB_OK) {
        sqlite3_close(db->handle);
        free(db);
        return BUNNY_DB_ERR_OPEN_FAILED;
    }

    *out_db = db;
    return BUNNY_DB_OK;
}

void bunny_db_close(bunny_db_t *db)
{
    if (!db) {
        return;
    }
    sqlite3_close(db->handle);
    free(db);
}
