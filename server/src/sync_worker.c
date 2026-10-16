#include "sync_worker.h"

#include <bunny_common/thread.h>
#include <goblin/cstr.h>

#include <stdlib.h>
#include <string.h>

#include "log.h"

#define SYNC_WORKER_QUEUE_CAPACITY 64

typedef enum
{
    SYNC_WORKER_JOB_SEARCH,
    SYNC_WORKER_JOB_ALL,
    SYNC_WORKER_JOB_DUE,
} sync_worker_job_type_t;

typedef struct
{
    sync_worker_job_type_t type;
    int64_t search_id; /* valid for SYNC_WORKER_JOB_SEARCH only */
} sync_worker_job_t;

struct sync_worker
{
    bunny_thread_t thread;
    bunny_core_t *core;
    server_sync_status_t *status;

    bunny_mutex_t queue_mutex;
    bunny_cond_t queue_cond;
    sync_worker_job_t queue[SYNC_WORKER_QUEUE_CAPACITY];
    size_t queue_head;
    size_t queue_count;
    bool all_job_pending; /* see sync_worker_enqueue_all */
    bool due_job_pending; /* see sync_worker_enqueue_due */

    volatile bool stop_requested;
};

/* label_or_null: a best-effort search label for the status display -- NULL
 * if the search was deleted out from under a still-queued job, which is
 * harmless (bunny_core_sync_search below just returns NOT_FOUND). */
static char *find_search_label(bunny_core_t *core, int64_t search_id)
{
    bunny_db_search_list_t list;
    if (bunny_core_search_list(core, &list) != BUNNY_CORE_OK) {
        return NULL;
    }
    char *label = NULL;
    for (size_t i = 0; i < list.count; i++) {
        if (list.items[i].id == search_id) {
            label = goblin_copy_cstr(list.items[i].label);
            break;
        }
    }
    bunny_db_search_list_free(&list);
    return label;
}

static void run_search_job(sync_worker_t *worker, int64_t search_id)
{
    char *label = find_search_label(worker->core, search_id);
    server_sync_status_set_active(worker->status, "manual", label, 0, 0);
    free(label);

    bunny_core_sync_stats_t stats;
    bunny_core_sync_search(worker->core, search_id, &stats);

    server_sync_status_clear(worker->status);
}

static void run_all_job(sync_worker_t *worker)
{
    bunny_db_search_list_t list;
    memset(&list, 0, sizeof(list));
    bunny_core_result_t result = bunny_core_search_list(worker->core, &list);
    if (result == BUNNY_CORE_OK) {
        server_log("INFO", "sync worker: starting a forced sync of all %zu searches", list.count);
        for (size_t i = 0; i < list.count; i++) {
            server_sync_status_set_active(worker->status, "manual", list.items[i].label, (int)(i + 1), (int)list.count);
            bunny_core_sync_stats_t stats;
            bunny_core_sync_search(worker->core, list.items[i].id, &stats);
        }
        server_log("INFO", "sync worker: finished forced sync of all %zu searches", list.count);
        bunny_db_search_list_free(&list);
    }
    server_sync_status_clear(worker->status);

    bunny_mutex_lock(&worker->queue_mutex);
    worker->all_job_pending = false;
    bunny_mutex_unlock(&worker->queue_mutex);
}

/* Coarse status reporting (no per-search label/position) -- deliberately
 * mirrors the scheduler's own treatment in scheduler.c rather than
 * duplicating bunny_core_sync_due_searches' internal due-filtering loop here
 * just to get per-search granularity. */
static void run_due_job(sync_worker_t *worker)
{
    server_sync_status_set_active(worker->status, "manual", NULL, 0, 0);
    bunny_core_sync_stats_t stats;
    bunny_core_sync_due_searches(worker->core, &stats);
    server_log("INFO", "sync worker: synced %d/%d due searches (%d posts upserted)", stats.searches_synced, stats.searches_checked, stats.posts_upserted);
    server_sync_status_clear(worker->status);

    bunny_mutex_lock(&worker->queue_mutex);
    worker->due_job_pending = false;
    bunny_mutex_unlock(&worker->queue_mutex);
}

static void *sync_worker_loop(void *arg)
{
    sync_worker_t *worker = (sync_worker_t *)arg;

    for (;;) {
        bunny_mutex_lock(&worker->queue_mutex);
        while (worker->queue_count == 0 && !worker->stop_requested) {
            bunny_cond_wait(&worker->queue_cond, &worker->queue_mutex);
        }
        if (worker->queue_count == 0 && worker->stop_requested) {
            bunny_mutex_unlock(&worker->queue_mutex);
            break;
        }
        sync_worker_job_t job = worker->queue[worker->queue_head];
        worker->queue_head = (worker->queue_head + 1) % SYNC_WORKER_QUEUE_CAPACITY;
        worker->queue_count--;
        bunny_mutex_unlock(&worker->queue_mutex);

        switch (job.type) {
            case SYNC_WORKER_JOB_SEARCH:
                run_search_job(worker, job.search_id);
                break;
            case SYNC_WORKER_JOB_ALL:
                run_all_job(worker);
                break;
            case SYNC_WORKER_JOB_DUE:
                run_due_job(worker);
                break;
        }
    }
    return NULL;
}

sync_worker_t *sync_worker_start(bunny_core_t *core, server_sync_status_t *status)
{
    sync_worker_t *worker = calloc(1, sizeof(sync_worker_t));
    if (!worker) {
        return NULL;
    }
    worker->core = core;
    worker->status = status;

    if (bunny_mutex_init(&worker->queue_mutex) != 0) {
        free(worker);
        return NULL;
    }
    if (bunny_cond_init(&worker->queue_cond) != 0) {
        bunny_mutex_destroy(&worker->queue_mutex);
        free(worker);
        return NULL;
    }
    if (bunny_thread_create(&worker->thread, sync_worker_loop, worker) != 0) {
        bunny_cond_destroy(&worker->queue_cond);
        bunny_mutex_destroy(&worker->queue_mutex);
        free(worker);
        return NULL;
    }
    return worker;
}

void sync_worker_stop(sync_worker_t *worker)
{
    if (!worker) {
        return;
    }
    bunny_mutex_lock(&worker->queue_mutex);
    worker->stop_requested = true;
    bunny_cond_broadcast(&worker->queue_cond);
    bunny_mutex_unlock(&worker->queue_mutex);

    bunny_thread_join(worker->thread);
    bunny_cond_destroy(&worker->queue_cond);
    bunny_mutex_destroy(&worker->queue_mutex);
    free(worker);
}

static bool enqueue_job(sync_worker_t *worker, sync_worker_job_t job)
{
    bunny_mutex_lock(&worker->queue_mutex);
    bool has_room = worker->queue_count < SYNC_WORKER_QUEUE_CAPACITY;
    if (has_room) {
        size_t tail = (worker->queue_head + worker->queue_count) % SYNC_WORKER_QUEUE_CAPACITY;
        worker->queue[tail] = job;
        worker->queue_count++;
        bunny_cond_signal(&worker->queue_cond);
    }
    bunny_mutex_unlock(&worker->queue_mutex);
    return has_room;
}

bool sync_worker_enqueue_search(sync_worker_t *worker, int64_t search_id)
{
    sync_worker_job_t job = {SYNC_WORKER_JOB_SEARCH, search_id};
    return enqueue_job(worker, job);
}

bool sync_worker_enqueue_all(sync_worker_t *worker)
{
    bunny_mutex_lock(&worker->queue_mutex);
    if (worker->all_job_pending) {
        bunny_mutex_unlock(&worker->queue_mutex);
        return false;
    }
    worker->all_job_pending = true;
    bunny_mutex_unlock(&worker->queue_mutex);

    sync_worker_job_t job = {SYNC_WORKER_JOB_ALL, 0};
    if (!enqueue_job(worker, job)) {
        bunny_mutex_lock(&worker->queue_mutex);
        worker->all_job_pending = false;
        bunny_mutex_unlock(&worker->queue_mutex);
        return false;
    }
    return true;
}

bool sync_worker_enqueue_due(sync_worker_t *worker)
{
    bunny_mutex_lock(&worker->queue_mutex);
    if (worker->due_job_pending) {
        bunny_mutex_unlock(&worker->queue_mutex);
        return false;
    }
    worker->due_job_pending = true;
    bunny_mutex_unlock(&worker->queue_mutex);

    sync_worker_job_t job = {SYNC_WORKER_JOB_DUE, 0};
    if (!enqueue_job(worker, job)) {
        bunny_mutex_lock(&worker->queue_mutex);
        worker->due_job_pending = false;
        bunny_mutex_unlock(&worker->queue_mutex);
        return false;
    }
    return true;
}
