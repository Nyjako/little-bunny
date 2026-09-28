#include "bunny_db/db.h"

#include <stdlib.h>

#include "internal.h"
#include "schema.h"

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
