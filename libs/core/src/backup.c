#include "bunny_core/core.h"

#include <stdio.h>
#include <time.h>

#include "internal.h"

bunny_core_result_t bunny_core_backup_database(bunny_core_t *core, const char *backups_dir)
{
    if (!core || !backups_dir) {
        return BUNNY_CORE_ERR_INVALID_ARG;
    }

    /* A unix-timestamp-embedding filename sorts lexicographically the same
     * as chronologically, so the caller can prune to the N newest with a
     * plain directory listing + sort, no separate mtime bookkeeping (M14.5). */
    char path[1024];
    int written = snprintf(path, sizeof(path), "%s/bunny_%lld.db", backups_dir, (long long)time(NULL));
    if (written < 0 || (size_t)written >= sizeof(path)) {
        return BUNNY_CORE_ERR_UNKNOWN;
    }

    /* Online Backup API reads source pages -- read pool (M25), not
     * db_mutex, so the daily backup (scheduler.c) no longer blocks every
     * other request against the live server for its whole duration, which
     * used to grow with database size right along with the freezes this
     * fixes elsewhere. */
    size_t slot;
    bunny_db_t *read_db = bunny_core_db_read_lock(core, &slot);
    bunny_db_result_t result = bunny_db_backup(read_db, path);
    bunny_core_db_read_unlock(core, slot);
    return bunny_core_map_db_result(result);
}
