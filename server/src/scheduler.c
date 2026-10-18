#include "scheduler.h"

#include <bunny_common/http.h>
#include <bunny_common/thread.h>
#include <bunny_core/core.h>
#include <goblin/appdirs.h>
#include <goblin/cstr.h>
#include <goblin/fileio.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <dirent.h>
#endif

#include "log.h"
#include "task_queue.h"
#include "updater.h"

#define BUNNY_BACKUP_INTERVAL_SEC (24 * 60 * 60)
#define BUNNY_BACKUP_KEEP_COUNT 5
#define BUNNY_BACKUP_PREFIX "bunny_"

static bool is_backup_filename(const char *name)
{
    return strncmp(name, BUNNY_BACKUP_PREFIX, strlen(BUNNY_BACKUP_PREFIX)) == 0;
}

/* Insertion sort (the lists here are at most a few dozen entries, so O(n^2)
 * is irrelevant) -- shared by both list_backup_files() implementations
 * below. */
static void sort_backup_names(char **names, size_t count)
{
    for (size_t i = 1; i < count; i++) {
        char *key = names[i];
        size_t j = i;
        while (j > 0 && strcmp(names[j - 1], key) > 0) {
            names[j] = names[j - 1];
            j--;
        }
        names[j] = key;
    }
}

/* Lists `backups_dir`'s own backup files (already-timestamped filenames
 * sort lexicographically the same as chronologically, so no separate mtime
 * bookkeeping is needed -- M14.5). Returns the count found and fills
 * `out_names` (caller-owned, each entry malloc'd) up to `max_names`. */
#ifdef _WIN32
static size_t list_backup_files(const char *backups_dir, char **out_names, size_t max_names)
{
    char pattern[1024];
    snprintf(pattern, sizeof(pattern), "%s\\*", backups_dir);

    WIN32_FIND_DATAA find_data;
    HANDLE handle = FindFirstFileA(pattern, &find_data);
    if (handle == INVALID_HANDLE_VALUE) {
        return 0;
    }

    size_t count = 0;
    do {
        if (count >= max_names || !is_backup_filename(find_data.cFileName)) {
            continue;
        }
        out_names[count] = goblin_copy_cstr(find_data.cFileName);
        if (out_names[count]) {
            count++;
        }
    } while (FindNextFileA(handle, &find_data));
    FindClose(handle);

    sort_backup_names(out_names, count);
    return count;
}
#else
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

    sort_backup_names(out_names, count);
    return count;
}
#endif

/* Backs up into `backups_dir` if the newest existing backup (if any) is at
 * least a day old, then prunes down to the BUNNY_BACKUP_KEEP_COUNT newest. */
static void backup_due_and_prune(server_context_t *ctx, const char *backups_dir)
{
    if (!goblin_mkdir(backups_dir)) {
        server_log("ERROR", "scheduler: couldn't create backups dir %s", backups_dir);
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
        bunny_core_result_t result = bunny_core_backup_database(ctx->core, backups_dir);
        if (result == BUNNY_CORE_OK) {
            server_log("INFO", "scheduler: backed up database to %s", backups_dir);
        } else {
            server_log("ERROR", "scheduler: database backup failed");
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
            bunny_sleep_seconds(1);
        }
        if (scheduler->stop_requested) {
            break;
        }

        server_log("INFO", "scheduler: tick started, enqueuing due-search sync + action-queue drain");

        task_queue_enqueue_background_due_sync(scheduler->ctx->task_queue);
        task_queue_enqueue_background_action_queue(scheduler->ctx->task_queue);

        if (scheduler->backups_dir) {
            backup_due_and_prune(scheduler->ctx, scheduler->backups_dir);
        }

        /* Checked last, and only acted on at the very end of a tick (never
         * mid-sync/mid-backup) -- bunny_updater_scheduler_tick itself
         * self-throttles (at most once a day, see updater.c), so calling it
         * every tick is cheap on every tick that isn't actually due. A
         * restart request just means "a verified update is staged and
         * ready" -- exiting cleanly here, with the unit's Restart=always
         * (deploy/bunny-server.service, M23), is what actually applies it
         * on the next start via ExecStartPre=+'s root-run helper script
         * (deploy/bunny-server-update-apply.sh) -- never this (sandboxed,
         * unprivileged) process writing to /usr/local/bin itself. */
        if (scheduler->data_dir) {
            bool restart_requested = false;
            bunny_http_transport_t transport = bunny_http_curl_transport();
            bunny_updater_scheduler_tick(&transport, scheduler->data_dir, scheduler->user_agent, &restart_requested);
            if (restart_requested) {
                server_log("INFO", "scheduler: exiting for the staged update to take effect on restart");
                exit(0);
            }
        }
    }
    return NULL;
}

bool server_scheduler_start(server_scheduler_t *scheduler, server_context_t *ctx, const char *data_dir, int poll_interval_sec, const char *user_agent)
{
    scheduler->ctx = ctx;
    scheduler->poll_interval_sec = poll_interval_sec;
    scheduler->backups_dir = data_dir ? goblin_appdir_join(data_dir, "backups") : NULL;
    scheduler->data_dir = data_dir ? goblin_copy_cstr(data_dir) : NULL;
    scheduler->user_agent = user_agent ? goblin_copy_cstr(user_agent) : NULL;
    scheduler->stop_requested = false;
    scheduler->running = false;

    if (poll_interval_sec <= 0) {
        return true; /* disabled, not an error */
    }

    if (bunny_thread_create(&scheduler->thread, scheduler_loop, scheduler) != 0) {
        return false;
    }
    scheduler->running = true;
    return true;
}

void server_scheduler_stop(server_scheduler_t *scheduler)
{
    if (scheduler->running) {
        scheduler->stop_requested = true;
        bunny_thread_join(scheduler->thread);
        scheduler->running = false;
    }
    free(scheduler->backups_dir);
    scheduler->backups_dir = NULL;
    free(scheduler->data_dir);
    scheduler->data_dir = NULL;
    free(scheduler->user_agent);
    scheduler->user_agent = NULL;
}
