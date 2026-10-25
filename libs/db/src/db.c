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
    /* NULL (not 0) is "ungrouped" at the SQL level, since this is a real FK
     * with ON DELETE SET NULL (deleting a group ungroups its searches
     * rather than deleting them) -- SQLite would reject a non-NULL value
     * that doesn't exist in search_groups once foreign_keys is on, so 0
     * can't double as the sentinel here the way it does for e.g.
     * highest_synced_external_id. searches.c translates application-level
     * 0 <-> SQL NULL at the bind/read boundary, same public-API shape as
     * every other "0 means none" column in this codebase. */
    {11, "ALTER TABLE searches ADD COLUMN group_id INTEGER REFERENCES search_groups(id) ON DELETE SET NULL;"},
    /* -1 ("not yet determined") rather than 0, since 0 is itself a valid,
     * meaningful position (the first post in the pool) -- a freshly-synced
     * membership row seeds to -1 until the next pool-order sync
     * (bunny_core_sync_pool_order) fills in e621's real post_ids order
     * (M26). Existing rows all seed to -1 too; the one-time backfill
     * (server_settings.pool_positions_backfilled below) fixes those up
     * without waiting for each pool's own search to sync again. */
    {12, "ALTER TABLE post_pools ADD COLUMN position INTEGER NOT NULL DEFAULT -1;"},
    /* Tracks whether the one-time backfill (M26) that re-fetches every
     * pool already in post_pools from e621, to populate `position` for
     * data that predates this column, has run yet -- a network operation,
     * so it can't be part of this SQL migration itself. Checked/set by
     * bunny_core_backfill_pool_positions_once, called once from the
     * scheduler's first tick (server mode) or FfiBunnyRepository.open
     * (standalone mode). */
    {13, "ALTER TABLE server_settings ADD COLUMN pool_positions_backfilled INTEGER NOT NULL DEFAULT 0;"},
    /* Feeds the "most-visited searches" section of the cached stats report
     * (M40) -- last_viewed_at (migration 7) only has the most recent view,
     * not how many there have been, so ranking by visit frequency needs its
     * own counter. bunny_db_search_mark_viewed increments this in the same
     * UPDATE that already sets last_viewed_at. */
    {14, "ALTER TABLE searches ADD COLUMN view_count INTEGER NOT NULL DEFAULT 0;"},
    /* bunny_db_search_list_posts previously sorted by COALESCE(p.created_at_site,
     * p.cached_at) -- a two-column expression on `posts`, with no index that could
     * cover it. Since the query's own WHERE clause (sr.search_id = ?) scopes to
     * `search_results`, not `posts`, SQLite had no way to use an index for the ORDER
     * BY either: it had to materialize and sort *every* row matching that search_id
     * before LIMIT/OFFSET could apply, no matter how small a page was actually
     * requested. Confirmed live (M46's audit) at 12-14s for a single page of a
     * 58k-post search, scaling with the search's total size, not the requested page
     * -- page 1 and page 500 took the same time. Denormalizing the sort key onto
     * search_results itself (this column, backfilled below) lets a composite index
     * on (search_id, post_sort_key) satisfy both the WHERE and the ORDER BY directly,
     * so SQLite can walk straight to the requested page instead of sorting
     * everything first. bunny_db_search_add_result populates this for every row
     * added from here on; it's effectively immutable after that (see its own doc
     * comment for why that's fine). */
    {15, "ALTER TABLE search_results ADD COLUMN post_sort_key TEXT;"
         "UPDATE search_results SET post_sort_key = "
         "(SELECT COALESCE(p.created_at_site, p.cached_at) FROM posts p WHERE p.id = search_results.post_id);"
         "CREATE INDEX IF NOT EXISTS idx_search_results_search_id_sort_key ON search_results(search_id, post_sort_key);"},
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

    /* WAL mode commits don't need the exclusive-lock-plus-fsync-the-whole-
     * rollback-journal dance that the default (DELETE) journal mode does on
     * every commit -- cheap, persists in the database file itself (set once,
     * stays set), and directly cuts per-commit latency for exactly the
     * many-small-writes pattern sync.c's batched upserts rely on. Ignored
     * (not fatal) for ":memory:" databases, which don't support WAL. */
    sqlite3_exec(db->handle, "PRAGMA journal_mode=WAL;", NULL, NULL, NULL);

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

bunny_db_result_t bunny_db_begin_transaction(bunny_db_t *db)
{
    if (!db) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    return bunny_db_sqlite_rc_to_result(sqlite3_exec(db->handle, "BEGIN;", NULL, NULL, NULL));
}

bunny_db_result_t bunny_db_commit_transaction(bunny_db_t *db)
{
    if (!db) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    return bunny_db_sqlite_rc_to_result(sqlite3_exec(db->handle, "COMMIT;", NULL, NULL, NULL));
}

bunny_db_result_t bunny_db_rollback_transaction(bunny_db_t *db)
{
    if (!db) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    return bunny_db_sqlite_rc_to_result(sqlite3_exec(db->handle, "ROLLBACK;", NULL, NULL, NULL));
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
