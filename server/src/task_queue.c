#include "task_queue.h"

#include <bunny_common/thread.h>
#include <goblin/cstr.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "log.h"

#define TASK_QUEUE_CAPACITY 64

typedef struct
{
    bool in_use;
    int64_t id;
    task_type_t type;
    task_priority_t priority;
    task_status_t status;
    char *label;       /* owned */
    time_t enqueued_at;
    int64_t search_id; /* valid for TASK_TYPE_SYNC_SEARCH only */
} task_slot_t;

struct task_queue
{
    bunny_thread_t thread;
    bunny_core_t *core;
    server_sync_status_t *status;

    bunny_mutex_t mutex;
    bunny_cond_t cond;
    task_slot_t slots[TASK_QUEUE_CAPACITY];
    int64_t next_id;

    volatile bool stop_requested;
};

/* label_or_null: a best-effort search label -- NULL if the search was
 * deleted out from under a still-queued job, which is harmless
 * (bunny_core_sync_search below just returns NOT_FOUND). */
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

static char *make_search_sync_label(bunny_core_t *core, int64_t search_id)
{
    char *search_label = find_search_label(core, search_id);
    char buf[256];
    if (search_label) {
        snprintf(buf, sizeof(buf), "Sync: %s", search_label);
        free(search_label);
    } else {
        snprintf(buf, sizeof(buf), "Sync: search #%lld", (long long)search_id);
    }
    return goblin_copy_cstr(buf);
}

/* Caller must hold queue->mutex. */
static int find_slot_by_type(task_queue_t *queue, task_type_t type)
{
    for (int i = 0; i < TASK_QUEUE_CAPACITY; i++) {
        if (queue->slots[i].in_use && queue->slots[i].type == type) {
            return i;
        }
    }
    return -1;
}

/* Caller must hold queue->mutex. */
static int find_free_slot(task_queue_t *queue)
{
    for (int i = 0; i < TASK_QUEUE_CAPACITY; i++) {
        if (!queue->slots[i].in_use) {
            return i;
        }
    }
    return -1;
}

/* Caller must hold queue->mutex. Takes ownership of label on success; frees
 * it on failure (slot table full). */
static bool insert_slot(task_queue_t *queue, task_type_t type, task_priority_t priority, char *label, int64_t search_id)
{
    int idx = find_free_slot(queue);
    if (idx < 0) {
        free(label);
        return false;
    }
    task_slot_t *slot = &queue->slots[idx];
    slot->in_use = true;
    slot->id = ++queue->next_id;
    slot->type = type;
    slot->priority = priority;
    slot->status = TASK_STATUS_PENDING;
    slot->label = label;
    slot->enqueued_at = time(NULL);
    slot->search_id = search_id;
    bunny_cond_signal(&queue->cond);
    return true;
}

typedef enum
{
    TASK_DEDUPE_INSERT_NEW, /* no existing slot of this type -- caller must insert one */
    TASK_DEDUPE_MERGED,     /* an existing lower-priority (background) slot was promoted -- treat as success, nothing to insert */
    TASK_DEDUPE_DUPLICATE,  /* an existing slot already at/above this priority -- a genuine duplicate request, reject it */
} task_dedupe_result_t;

/* Caller must hold queue->mutex. Shared by the two HIGH-priority,
 * one-of-this-type-at-a-time job types (sync-all, user-triggered sync-due):
 * an existing LOW-priority slot of the same type is the scheduler's own
 * background version of the same work, so it gets promoted in place rather
 * than duplicated -- but an existing slot already at HIGH priority means a
 * second explicit user request raced the first, which stays a rejected
 * (409) duplicate, same as before this priority queue existed. */
static task_dedupe_result_t dedupe_or_promote(task_queue_t *queue, task_type_t type, task_priority_t priority)
{
    int idx = find_slot_by_type(queue, type);
    if (idx < 0) {
        return TASK_DEDUPE_INSERT_NEW;
    }
    if (queue->slots[idx].priority < priority) {
        queue->slots[idx].priority = priority;
        return TASK_DEDUPE_MERGED;
    }
    return TASK_DEDUPE_DUPLICATE;
}

static void run_slot(task_queue_t *queue, const task_slot_t *slot)
{
    const char *source = slot->priority == TASK_PRIORITY_HIGH ? "manual" : "scheduler";

    switch (slot->type) {
        case TASK_TYPE_SYNC_SEARCH: {
            server_sync_status_set_active(queue->status, source, slot->label, 0, 0);
            bunny_core_sync_stats_t stats;
            bunny_core_sync_search(queue->core, slot->search_id, &stats);
            server_sync_status_clear(queue->status);
            break;
        }
        case TASK_TYPE_SYNC_ALL: {
            bunny_db_search_list_t list;
            memset(&list, 0, sizeof(list));
            bunny_core_result_t result = bunny_core_search_list(queue->core, &list);
            if (result == BUNNY_CORE_OK) {
                server_log("INFO", "task queue: starting a forced sync of all %zu searches", list.count);
                for (size_t i = 0; i < list.count; i++) {
                    server_sync_status_set_active(queue->status, source, list.items[i].label, (int)(i + 1), (int)list.count);
                    bunny_core_sync_stats_t stats;
                    bunny_core_sync_search(queue->core, list.items[i].id, &stats);
                }
                server_log("INFO", "task queue: finished forced sync of all %zu searches", list.count);
                bunny_db_search_list_free(&list);
            }
            server_sync_status_clear(queue->status);
            break;
        }
        case TASK_TYPE_SYNC_DUE: {
            server_sync_status_set_active(queue->status, source, NULL, 0, 0);
            bunny_core_sync_stats_t stats;
            bunny_core_sync_due_searches(queue->core, &stats);
            server_log("INFO", "task queue: synced %d/%d due searches (%d posts upserted)", stats.searches_synced, stats.searches_checked, stats.posts_upserted);
            server_sync_status_clear(queue->status);
            break;
        }
        case TASK_TYPE_PROCESS_ACTION_QUEUE: {
            server_sync_status_set_active(queue->status, source, NULL, 0, 0);
            bunny_core_queue_stats_t stats;
            bunny_core_process_queue(queue->core, &stats);
            server_log("INFO", "task queue: processed %d queued actions (%d succeeded, %d failed)", stats.actions_processed, stats.actions_succeeded, stats.actions_failed);
            server_sync_status_clear(queue->status);
            break;
        }
    }
}

/* Caller must hold queue->mutex. Highest priority first, then earliest
 * enqueued_at within a priority level -- this IS the dispatch order, not
 * just a display convenience (task_queue_snapshot_get sorts the same way). */
static int pick_next_pending_slot(task_queue_t *queue)
{
    int best = -1;
    for (int i = 0; i < TASK_QUEUE_CAPACITY; i++) {
        task_slot_t *slot = &queue->slots[i];
        if (!slot->in_use || slot->status != TASK_STATUS_PENDING) {
            continue;
        }
        if (best < 0) {
            best = i;
            continue;
        }
        task_slot_t *best_slot = &queue->slots[best];
        if (slot->priority > best_slot->priority || (slot->priority == best_slot->priority && slot->enqueued_at < best_slot->enqueued_at)) {
            best = i;
        }
    }
    return best;
}

static void *task_queue_loop(void *arg)
{
    task_queue_t *queue = (task_queue_t *)arg;

    for (;;) {
        bunny_mutex_lock(&queue->mutex);
        int idx;
        while ((idx = pick_next_pending_slot(queue)) < 0 && !queue->stop_requested) {
            bunny_cond_wait(&queue->cond, &queue->mutex);
        }
        if (idx < 0 && queue->stop_requested) {
            bunny_mutex_unlock(&queue->mutex);
            break;
        }
        queue->slots[idx].status = TASK_STATUS_RUNNING;
        task_slot_t slot_copy = queue->slots[idx];
        bunny_mutex_unlock(&queue->mutex);

        run_slot(queue, &slot_copy);

        bunny_mutex_lock(&queue->mutex);
        free(queue->slots[idx].label);
        queue->slots[idx].in_use = false;
        bunny_mutex_unlock(&queue->mutex);
    }
    return NULL;
}

task_queue_t *task_queue_start(bunny_core_t *core, server_sync_status_t *status)
{
    task_queue_t *queue = calloc(1, sizeof(task_queue_t));
    if (!queue) {
        return NULL;
    }
    queue->core = core;
    queue->status = status;

    if (bunny_mutex_init(&queue->mutex) != 0) {
        free(queue);
        return NULL;
    }
    if (bunny_cond_init(&queue->cond) != 0) {
        bunny_mutex_destroy(&queue->mutex);
        free(queue);
        return NULL;
    }
    if (bunny_thread_create(&queue->thread, task_queue_loop, queue) != 0) {
        bunny_cond_destroy(&queue->cond);
        bunny_mutex_destroy(&queue->mutex);
        free(queue);
        return NULL;
    }
    return queue;
}

void task_queue_stop(task_queue_t *queue)
{
    if (!queue) {
        return;
    }
    bunny_mutex_lock(&queue->mutex);
    queue->stop_requested = true;
    bunny_cond_broadcast(&queue->cond);
    bunny_mutex_unlock(&queue->mutex);

    bunny_thread_join(queue->thread);
    bunny_cond_destroy(&queue->cond);
    bunny_mutex_destroy(&queue->mutex);

    for (int i = 0; i < TASK_QUEUE_CAPACITY; i++) {
        if (queue->slots[i].in_use) {
            free(queue->slots[i].label);
        }
    }
    free(queue);
}

bool task_queue_enqueue_sync_search(task_queue_t *queue, int64_t search_id)
{
    char *label = make_search_sync_label(queue->core, search_id);
    bunny_mutex_lock(&queue->mutex);
    bool ok = insert_slot(queue, TASK_TYPE_SYNC_SEARCH, TASK_PRIORITY_HIGH, label, search_id);
    bunny_mutex_unlock(&queue->mutex);
    return ok;
}

bool task_queue_enqueue_sync_all(task_queue_t *queue)
{
    bunny_mutex_lock(&queue->mutex);
    bool ok;
    switch (dedupe_or_promote(queue, TASK_TYPE_SYNC_ALL, TASK_PRIORITY_HIGH)) {
        case TASK_DEDUPE_MERGED:
            ok = true;
            break;
        case TASK_DEDUPE_DUPLICATE:
            ok = false;
            break;
        case TASK_DEDUPE_INSERT_NEW:
        default:
            ok = insert_slot(queue, TASK_TYPE_SYNC_ALL, TASK_PRIORITY_HIGH, goblin_copy_cstr("Sync: all searches"), 0);
            break;
    }
    bunny_mutex_unlock(&queue->mutex);
    return ok;
}

bool task_queue_enqueue_sync_due(task_queue_t *queue)
{
    bunny_mutex_lock(&queue->mutex);
    bool ok;
    switch (dedupe_or_promote(queue, TASK_TYPE_SYNC_DUE, TASK_PRIORITY_HIGH)) {
        case TASK_DEDUPE_MERGED:
            ok = true;
            break;
        case TASK_DEDUPE_DUPLICATE:
            ok = false;
            break;
        case TASK_DEDUPE_INSERT_NEW:
        default:
            ok = insert_slot(queue, TASK_TYPE_SYNC_DUE, TASK_PRIORITY_HIGH, goblin_copy_cstr("Sync: due searches"), 0);
            break;
    }
    bunny_mutex_unlock(&queue->mutex);
    return ok;
}

bool task_queue_enqueue_background_due_sync(task_queue_t *queue)
{
    bunny_mutex_lock(&queue->mutex);
    /* Unlike the HIGH-priority variants above, a background pass never
     * promotes an existing slot -- it only needs to exist, not to escalate
     * whatever's already covering the same work. */
    bool already_covered = find_slot_by_type(queue, TASK_TYPE_SYNC_DUE) >= 0;
    bool ok = already_covered || insert_slot(queue, TASK_TYPE_SYNC_DUE, TASK_PRIORITY_LOW, goblin_copy_cstr("Sync: due searches (scheduled)"), 0);
    bunny_mutex_unlock(&queue->mutex);
    return ok;
}

bool task_queue_enqueue_background_action_queue(task_queue_t *queue)
{
    bunny_mutex_lock(&queue->mutex);
    bool already_covered = find_slot_by_type(queue, TASK_TYPE_PROCESS_ACTION_QUEUE) >= 0;
    bool ok = already_covered || insert_slot(queue, TASK_TYPE_PROCESS_ACTION_QUEUE, TASK_PRIORITY_MEDIUM, goblin_copy_cstr("Process favorite/vote/comment queue"), 0);
    bunny_mutex_unlock(&queue->mutex);
    return ok;
}

static int compare_entries(const void *a, const void *b)
{
    const task_queue_entry_t *ea = (const task_queue_entry_t *)a;
    const task_queue_entry_t *eb = (const task_queue_entry_t *)b;
    if (ea->priority != eb->priority) {
        return (int)eb->priority - (int)ea->priority; /* higher priority first */
    }
    if (ea->enqueued_at != eb->enqueued_at) {
        return ea->enqueued_at < eb->enqueued_at ? -1 : 1;
    }
    return ea->id < eb->id ? -1 : (ea->id > eb->id ? 1 : 0);
}

void task_queue_snapshot_get(task_queue_t *queue, task_queue_snapshot_t *out)
{
    memset(out, 0, sizeof(*out));
    task_queue_entry_t *items = calloc(TASK_QUEUE_CAPACITY, sizeof(task_queue_entry_t));
    if (!items) {
        return;
    }
    size_t count = 0;

    bunny_mutex_lock(&queue->mutex);
    for (int i = 0; i < TASK_QUEUE_CAPACITY; i++) {
        task_slot_t *slot = &queue->slots[i];
        if (!slot->in_use) {
            continue;
        }
        items[count].id = slot->id;
        items[count].type = slot->type;
        items[count].priority = slot->priority;
        items[count].status = slot->status;
        items[count].label = goblin_copy_cstr(slot->label);
        items[count].enqueued_at = slot->enqueued_at;
        count++;
    }
    bunny_mutex_unlock(&queue->mutex);

    qsort(items, count, sizeof(task_queue_entry_t), compare_entries);

    out->items = items;
    out->count = count;
}

void task_queue_snapshot_free(task_queue_snapshot_t *snapshot)
{
    if (!snapshot || !snapshot->items) {
        return;
    }
    for (size_t i = 0; i < snapshot->count; i++) {
        free(snapshot->items[i].label);
    }
    free(snapshot->items);
    snapshot->items = NULL;
    snapshot->count = 0;
}
