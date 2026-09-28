#include "scheduler.h"

#include <bunny_core/core.h>

#include <stdio.h>
#include <unistd.h>

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
    }
    return NULL;
}

bool server_scheduler_start(server_scheduler_t *scheduler, server_context_t *ctx, int poll_interval_sec)
{
    scheduler->ctx = ctx;
    scheduler->poll_interval_sec = poll_interval_sec;
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
    if (!scheduler->running) {
        return;
    }
    scheduler->stop_requested = true;
    pthread_join(scheduler->thread, NULL);
    scheduler->running = false;
}
