#ifndef BUNNY_SERVER_SYNC_WORKER_H
#define BUNNY_SERVER_SYNC_WORKER_H

#include <bunny_core/core.h>

#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>

#include "sync_status.h"

/* civetweb runs a small, fixed-size worker-thread pool (4 -- see app.c). A
 * sync can legitimately run for many minutes against a large search, and
 * bunny_core serializes all site-facing syncs against each other via its own
 * internal sync_mutex (libs/core/src/internal.h) -- so a route handler that
 * calls bunny_core_sync_search directly and blocks on the HTTP response
 * until it returns ties up one of those 4 threads for the sync's entire
 * duration. Pile up a few such requests (manual syncs, retries, multiple
 * devices) and the whole server -- including completely unrelated GET
 * requests that don't even touch sync_mutex -- can run out of worker
 * threads to service them with.
 *
 * sync_worker fixes this by moving every blocking bunny_core_sync_search
 * call off civetweb's threads entirely: routes just enqueue a job and
 * return immediately (202), and a single dedicated background thread (same
 * pattern as scheduler.c) works through the queue one job at a time,
 * updating the shared server_sync_status_t as it goes so any device can see
 * live progress via GET /sync/status regardless of which device (or the
 * scheduler) triggered it. bunny_core_process_queue deliberately does NOT
 * go through this -- see the comment on handle_queue_process in
 * routes_queue.c for why. */
typedef struct sync_worker sync_worker_t;

/* status is not owned by the returned worker -- caller creates/destroys it
 * and may also pass it to scheduler_start so both report into the same
 * place. */
sync_worker_t *sync_worker_start(bunny_core_t *core, server_sync_status_t *status);

/* Signals the loop to exit after its current job (if any) finishes, and
 * joins the thread. Safe to call on a NULL worker. */
void sync_worker_stop(sync_worker_t *worker);

/* Enqueues a sync of one search. Always succeeds (duplicate requests for the
 * same id just run back-to-back) unless the internal queue is completely
 * full, in which case it returns false and the caller should ask the client
 * to retry shortly. */
bool sync_worker_enqueue_search(sync_worker_t *worker, int64_t search_id);

/* Enqueues a forced sync of every search, regardless of due status (the
 * server-side equivalent of the old client-driven "check for updates" loop).
 * Returns false (no-op) if an ALL job is already queued or running -- no
 * point piling up duplicate full passes from a mashed button. */
bool sync_worker_enqueue_all(sync_worker_t *worker);

/* Enqueues bunny_core_sync_due_searches -- only searches that are actually
 * due get synced, same as a scheduler tick (used by the pull-to-refresh
 * action on a single search's grid, which blunt-refreshes every due search
 * server-side rather than just the one being viewed). Same dedupe behavior
 * as sync_worker_enqueue_all. */
bool sync_worker_enqueue_due(sync_worker_t *worker);

#endif /* BUNNY_SERVER_SYNC_WORKER_H */
