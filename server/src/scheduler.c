#include "scheduler.h"

#include <bunny_core/core.h>
#include <goblin/appdirs.h>
#include <goblin/cstr.h>

#include <dirent.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define BUNNY_BACKUP_INTERVAL_SEC (24 * 60 * 60)
#define BUNNY_BACKUP_KEEP_COUNT 5
#define BUNNY_BACKUP_PREFIX "bunny_"

static bool is_backup_filename(const char *name)
{
    return strncmp(name, BUNNY_BACKUP_PREFIX, strlen(BUNNY_BACKUP_PREFIX)) == 0;
}

/* Lists `backups_dir`'s own backup files (already-timestamped filenames
 * sort lexicographically the same as chronologically, so no separate mtime
 * bookkeeping is needed -- M14.5). Returns the count found and fills
 * `out_names` (caller-owned, each entry malloc'd) up to `max_names`. */
static size_t list_backup_files(const char *backups_dir, char **out_names, size_t max_names)
{
    DIR *dir = opendir(backups_dir);
    if (!dir) {
        return 0;
    }

    size_t count = 0;
    struct dirent *entry;
    while (count < max_names && (entry = readdir(dir)) != NULL) {
        if (!is_backup_filename(entry->d_name)) {
            continue;
        }
        out_names[count] = goblin_copy_cstr(entry->d_name);
        if (out_names[count]) {
            count++;
        }
    }
    closedir(dir);

    for (size_t i = 1; i < count; i++) {
        char *key = out_names[i];
        size_t j = i;
        while (j > 0 && strcmp(out_names[j - 1], key) > 0) {
            out_names[j] = out_names[j - 1];
            j--;
        }
        out_names[j] = key;
    }
    return count;
}

/* Backs up into `backups_dir` if the newest existing backup (if any) is at
 * least a day old, then prunes down to the BUNNY_BACKUP_KEEP_COUNT newest. */
static void backup_due_and_prune(server_context_t *ctx, const char *backups_dir)
{
    if (mkdir(backups_dir, 0700) != 0 && errno != EEXIST) {
        fprintf(stderr, "scheduler: couldn't create backups dir %s\n", backups_dir);
        return;
    }

    char *names[1024];
    size_t count = list_backup_files(backups_dir, names, sizeof(names) / sizeof(names[0]));

    bool due = count == 0;
    if (!due) {
        char newest_path[1200];
        snprintf(newest_path, sizeof(newest_path), "%s/%s", backups_dir, names[count - 1]);
        struct stat st;
        due = stat(newest_path, &st) != 0 || (time(NULL) - st.st_mtime) >= BUNNY_BACKUP_INTERVAL_SEC;
    }

    if (due) {
        pthread_mutex_lock(&ctx->core_mutex);
        bunny_core_result_t result = bunny_core_backup_database(ctx->core, backups_dir);
        pthread_mutex_unlock(&ctx->core_mutex);
        if (result == BUNNY_CORE_OK) {
            fprintf(stdout, "scheduler: backed up database to %s\n", backups_dir);
        } else {
            fprintf(stderr, "scheduler: database backup failed\n");
        }

        for (size_t i = 0; i < count; i++) {
            free(names[i]);
        }
        count = list_backup_files(backups_dir, names, sizeof(names) / sizeof(names[0]));
    }

    while (count > BUNNY_BACKUP_KEEP_COUNT) {
        char path[1200];
        snprintf(path, sizeof(path), "%s/%s", backups_dir, names[0]);
        remove(path);
        free(names[0]);
        memmove(&names[0], &names[1], (count - 1) * sizeof(names[0]));
        count--;
    }

    for (size_t i = 0; i < count; i++) {
        free(names[i]);
    }
}

static void *scheduler_loop(void *arg)
{
    server_scheduler_t *scheduler = (server_scheduler_t *)arg;

    while (!scheduler->stop_requested) {
        /* Sleep in 1-second increments so a shutdown request is picked up
         * quickly instead of waiting out the full poll interval. */
        for (int i = 0; i < scheduler->poll_interval_sec && !scheduler->stop_requested; i++) {
            sleep(1);
        }
        if (scheduler->stop_requested) {
            break;
        }

        bunny_core_sync_stats_t sync_stats;
        bunny_core_queue_stats_t queue_stats;
        pthread_mutex_lock(&scheduler->ctx->core_mutex);
        bunny_core_sync_due_searches(scheduler->ctx->core, &sync_stats);
        bunny_core_process_queue(scheduler->ctx->core, &queue_stats);
        pthread_mutex_unlock(&scheduler->ctx->core_mutex);

        fprintf(stdout, "scheduler: synced %d/%d due searches (%d posts upserted), processed %d queued actions (%d succeeded, %d failed)\n", sync_stats.searches_synced, sync_stats.searches_checked, sync_stats.posts_upserted, queue_stats.actions_processed, queue_stats.actions_succeeded, queue_stats.actions_failed);

        if (scheduler->backups_dir) {
            backup_due_and_prune(scheduler->ctx, scheduler->backups_dir);
        }
    }
    return NULL;
}

bool server_scheduler_start(server_scheduler_t *scheduler, server_context_t *ctx, const char *data_dir, int poll_interval_sec)
{
    scheduler->ctx = ctx;
    scheduler->poll_interval_sec = poll_interval_sec;
    scheduler->backups_dir = data_dir ? goblin_appdir_join(data_dir, "backups") : NULL;
    scheduler->stop_requested = false;
    scheduler->running = false;

    if (poll_interval_sec <= 0) {
        return true; /* disabled, not an error */
    }

    if (pthread_create(&scheduler->thread, NULL, scheduler_loop, scheduler) != 0) {
        return false;
    }
    scheduler->running = true;
    return true;
}

void server_scheduler_stop(server_scheduler_t *scheduler)
{
    if (scheduler->running) {
        scheduler->stop_requested = true;
        pthread_join(scheduler->thread, NULL);
        scheduler->running = false;
    }
    free(scheduler->backups_dir);
    scheduler->backups_dir = NULL;
}
