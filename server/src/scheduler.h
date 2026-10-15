#ifndef BUNNY_SERVER_SCHEDULER_H
#define BUNNY_SERVER_SCHEDULER_H

#include <pthread.h>
#include <stdbool.h>

#include "context.h"
#include "sync_status.h"

typedef struct
{
    pthread_t thread;
    server_context_t *ctx;
    server_sync_status_t *status;
    int poll_interval_sec;
    char *backups_dir;
    volatile bool stop_requested;
    bool running;
} server_scheduler_t;

/* Starts a background thread that periodically calls
 * bunny_core_sync_due_searches() + bunny_core_process_queue() directly --
 * bunny_core is internally thread-safe (see context.h), and this thread is
 * entirely separate from civetweb's worker-thread pool, so there's no
 * worker-thread-starvation concern here the way there is for routes (see
 * sync_worker.h). `status` (may be NULL) is updated with a coarse
 * "scheduler" source around each pass so GET /sync/status reflects automatic
 * runs too, not just manually-triggered ones. Also checks once per loop
 * whether a daily backup is due (M14.5) -- see scheduler.c's
 * backup_due_and_prune() -- and if so, backs up into `<data_dir>/backups/`,
 * creating that directory if it doesn't exist yet, then prunes down to the 5
 * newest backups. poll_interval_sec <= 0 disables the scheduler entirely --
 * this still succeeds, it just doesn't spawn a thread (used by tests that
 * don't want a background pass racing their own explicit /sync or
 * /queue/process calls, and also skips the backup check). Returns false only
 * on an actual pthread_create failure. */
bool server_scheduler_start(server_scheduler_t *scheduler, server_context_t *ctx, server_sync_status_t *status, const char *data_dir, int poll_interval_sec);

/* Signals the loop to exit and joins the thread (within ~1s, not a full
 * poll interval). Safe to call even if the scheduler was never started. */
void server_scheduler_stop(server_scheduler_t *scheduler);

#endif /* BUNNY_SERVER_SCHEDULER_H */
