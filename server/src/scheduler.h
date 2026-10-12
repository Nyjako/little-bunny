#ifndef BUNNY_SERVER_SCHEDULER_H
#define BUNNY_SERVER_SCHEDULER_H

#include <pthread.h>
#include <stdbool.h>

#include "context.h"

typedef struct
{
    pthread_t thread;
    server_context_t *ctx;
    int poll_interval_sec;
    char *backups_dir;
    volatile bool stop_requested;
    bool running;
} server_scheduler_t;

/* Starts a background thread that periodically calls
 * bunny_core_sync_due_searches() + bunny_core_process_queue(), each
 * serialized through ctx->core_mutex just like every route handler. Also
 * checks once per loop whether a daily backup is due (M14.5) -- see
 * scheduler.c's backup_due_and_prune() -- and if so, backs up into
 * `<data_dir>/backups/`, creating that directory if it doesn't exist yet,
 * then prunes down to the 5 newest backups. poll_interval_sec <= 0 disables
 * the scheduler entirely -- this still succeeds, it just doesn't spawn a
 * thread (used by tests that don't want a background pass racing their own
 * explicit /sync or /queue/process calls, and also skips the backup check).
 * Returns false only on an actual pthread_create failure. */
bool server_scheduler_start(server_scheduler_t *scheduler, server_context_t *ctx, const char *data_dir, int poll_interval_sec);

/* Signals the loop to exit and joins the thread (within ~1s, not a full
 * poll interval). Safe to call even if the scheduler was never started. */
void server_scheduler_stop(server_scheduler_t *scheduler);

#endif /* BUNNY_SERVER_SCHEDULER_H */
