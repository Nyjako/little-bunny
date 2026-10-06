#include "bunny_db/db.h"

#include "internal.h"

bunny_db_result_t bunny_db_vote_set(bunny_db_t *db, int64_t post_id, int score)
{
    if (!db || (score != -1 && score != 1)) {
        return BUNNY_DB_ERR_INVALID_ARG;
    }
    const char *sql = "INSERT INTO votes (post_id, score) VALUES (?, ?) "
                      "ON CONFLICT(post_id) DO UPDATE SET score = excluded.score, voted_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now');";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db->handle, sql, -1, &stmt, NULL) != SQLITE_OK) {
        return BUNNY_DB_ERR_QUERY_FAILED;
    }
    sqlite3_bind_int64(stmt, 1, post_id);
    sqlite3_bind_int(stmt, 2, score);
    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE ? BUNNY_DB_OK : bunny_db_sqlite_rc_to_result(rc);
}
