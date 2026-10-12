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

    return bunny_core_map_db_result(bunny_db_backup(core->db, path));
}
