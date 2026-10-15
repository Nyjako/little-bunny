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

// clang-format off
static const bunny_db_migration_t BUNNY_DB_MIGRATIONS[] = {
    {1, "ALTER TABLE posts ADD COLUMN score_up INTEGER NOT NULL DEFAULT 0;"},
    {2, "ALTER TABLE posts ADD COLUMN score_down INTEGER NOT NULL DEFAULT 0;"},
    {3, "ALTER TABLE searches ADD COLUMN auto_favorite INTEGER NOT NULL DEFAULT 0;"},
    {4, "ALTER TABLE searches ADD COLUMN auto_favorite_stars INTEGER NOT NULL DEFAULT 1;"},
    {5, "ALTER TABLE searches ADD COLUMN auto_upvote INTEGER NOT NULL DEFAULT 0;"},
    {6, "ALTER TABLE searches ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0;"},
    {7, "ALTER TABLE searches ADD COLUMN last_viewed_at TEXT;"},
    {8, "ALTER TABLE searches ADD COLUMN initial_sync_done INTEGER NOT NULL DEFAULT 0;"},
    {9, "ALTER TABLE searches ADD COLUMN highest_synced_external_id INTEGER NOT NULL DEFAULT 0;"},
    /* uses_default_interval seeds to 1 for every search currently sitting at
     * interval_hours = 24 -- that value was both this column's own DEFAULT
     * and the app's hardcoded default before this migration, so a search at
     * exactly 24 almost certainly got there via "default", never having had
     * a real per-search override. Scheduling behavior for those rows is
     * unchanged by this (server_settings.default_sync_interval_hours also
     * seeds to 24) -- they just now track the live default going forward
     * instead of a value frozen at creation time. */
    {10, "ALTER TABLE searches ADD COLUMN uses_default_interval INTEGER NOT NULL DEFAULT 0;"
         "UPDATE searches SET uses_default_interval = 1 WHERE interval_hours = 24;"},
};
// clang-format on

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

bunny_db_result_t bunny_db_backup(bunny_db_t *db, const char *dest_path)
{
    if (!db || !dest_path) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }

    sqlite3 *dest_handle = NULL;
    if (sqlite3_open(dest_path, &dest_handle) != SQLITE_OK) {
        sqlite3_close(dest_handle);
        return BUNNY_DB_ERR_OPEN_FAILED;
    }

    /* The Online Backup API, not a raw file copy -- safe to run against a
     * source database the server may have open and writing to concurrently
     * (M14.5), unlike copying the .db file directly. */
    sqlite3_backup *backup = sqlite3_backup_init(dest_handle, "main", db->handle, "main");
    if (!backup) {
        sqlite3_close(dest_handle);
        return BUNNY_DB_ERR_UNKNOWN;
    }

    int rc = sqlite3_backup_step(backup, -1);
    sqlite3_backup_finish(backup);
    sqlite3_close(dest_handle);

    return rc == SQLITE_DONE ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
}
