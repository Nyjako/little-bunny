#ifndef BUNNY_SERVER_TASK_QUEUE_H
#define BUNNY_SERVER_TASK_QUEUE_H

#include <bunny_core/core.h>

#include <stdbool.h>
#include <stdint.h>
#include <time.h>

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
 * task_queue fixes this by moving every blocking bunny_core_sync_search/
 * bunny_core_process_queue call off civetweb's threads AND off the
 * scheduler's own thread (M20's original sync_worker only handled the
 * former) onto a single dedicated background thread, dispatched by
 * priority rather than strict FIFO (M24): HIGH for anything a user directly
 * asked for right now (a single search's "sync" button, "check for
 * updates", pull-to-refresh), MEDIUM for the favorite/vote/comment action
 * queue's background drain (someone's still waiting on this, just not
 * synchronously), LOW for the scheduler's own periodic due-search sync
 * (nobody's actively waiting on this one). Within a priority level, jobs
 * run in the order they were enqueued. Routes just enqueue a job and return
 * immediately (202); GET /tasks exposes the live pending+running list (in
 * the order they'll actually run) for an in-app task queue view, and GET
 * /sync/status (unchanged) keeps reporting just the one currently-running
 * job's fine-grained progress. bunny_core_queue_favorite_add/vote/comment's
 * own synchronous drain via POST /queue/process deliberately does NOT go
 * through this -- see the comment on handle_queue_process in
 * routes_queue.c for why. */
typedef struct task_queue task_queue_t;

typedef enum
{
    TASK_PRIORITY_LOW = 0,
    TASK_PRIORITY_MEDIUM = 1,
    TASK_PRIORITY_HIGH = 2,
} task_priority_t;

typedef enum
{
    TASK_TYPE_SYNC_SEARCH,
    TASK_TYPE_SYNC_ALL,
    TASK_TYPE_SYNC_DUE,
    TASK_TYPE_PROCESS_ACTION_QUEUE,
} task_type_t;

typedef enum
{
    TASK_STATUS_PENDING,
    TASK_STATUS_RUNNING,
} task_status_t;

/* status is not owned by the returned queue -- caller creates/destroys it
 * and may also pass it to scheduler_start so both report into the same
 * place. */
task_queue_t *task_queue_start(bunny_core_t *core, server_sync_status_t *status);

/* Signals the loop to exit after its current job (if any) finishes, and
 * joins the thread. Safe to call on a NULL queue. */
void task_queue_stop(task_queue_t *queue);

/* HIGH priority -- direct, explicit user interactions. Always succeeds
 * (duplicate requests for the same search id just run back-to-back) unless
 * the internal slot table is completely full, in which case it returns
 * false and the caller should ask the client to retry shortly. */
bool task_queue_enqueue_sync_search(task_queue_t *queue, int64_t search_id);

/* HIGH priority -- the server-side equivalent of the old client-driven
 * "check for updates" loop, forcing every search regardless of due status.
 * If the scheduler's own LOW-priority background pass (see
 * task_queue_enqueue_background_due_sync) is already pending/running, this
 * promotes it to HIGH in place rather than queuing a redundant second pass,
 * and still reports success. Returns false (409 at the route level) only
 * for a genuine duplicate -- another HIGH-priority sync-all already
 * pending/running, same as the plain FIFO queue this replaced. */
bool task_queue_enqueue_sync_all(task_queue_t *queue);

/* HIGH priority -- only searches actually due get synced (used by the
 * pull-to-refresh action on a single search's grid, which blunt-refreshes
 * every due search server-side rather than just the one being viewed).
 * Same promote-existing-background-job-or-reject-genuine-duplicate
 * behavior as task_queue_enqueue_sync_all, against
 * task_queue_enqueue_background_due_sync's LOW-priority job. */
bool task_queue_enqueue_sync_due(task_queue_t *queue);

/* LOW priority -- the scheduler's own periodic due-search pass (M20).
 * No-op (returns true without enqueuing) if a HIGH-priority due-sync from
 * task_queue_enqueue_sync_due is already pending/running -- that one will
 * cover this pass too, and downgrading it to LOW would be a regression. */
bool task_queue_enqueue_background_due_sync(task_queue_t *queue);

/* MEDIUM priority -- the scheduler's own periodic drain of the favorite/
 * vote/comment action queue (bunny_core_process_queue), previously run
 * in-line on the scheduler's own thread. No-op if a drain of this type is
 * already pending/running. */
bool task_queue_enqueue_background_action_queue(task_queue_t *queue);

typedef struct
{
    int64_t id;
    task_type_t type;
    task_priority_t priority;
    task_status_t status;
    char *label; /* owned, human-readable, never NULL */
    time_t enqueued_at;
} task_queue_entry_t;

typedef struct
{
    task_queue_entry_t *items;
    size_t count;
} task_queue_snapshot_t;

/* Every pending + currently-running task, ordered highest priority first
 * (then FIFO within a priority) -- this ordering IS the order the worker
 * will actually process them in, not just a display convenience. */
void task_queue_snapshot_get(task_queue_t *queue, task_queue_snapshot_t *out);
void task_queue_snapshot_free(task_queue_snapshot_t *snapshot);

#endif /* BUNNY_SERVER_TASK_QUEUE_H */
