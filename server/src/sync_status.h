#ifndef BUNNY_SERVER_SYNC_STATUS_H
#define BUNNY_SERVER_SYNC_STATUS_H

#include <stdbool.h>
#include <time.h>

/* Shared, mutex-guarded "what's syncing right now" state, read by any device
 * via GET /sync/status and written by both scheduler.c (automatic due-search
 * runs) and sync_worker.c (manually-triggered single-search/all-search/
 * queue-process jobs) -- the single place that answers "is a sync in
 * progress, and what's it doing" regardless of who started it. The lock here
 * only ever guards this small struct; it's never held across a network call
 * or a blocking bunny_core_* call, so reading/writing it is always fast. */
typedef struct server_sync_status server_sync_status_t;

server_sync_status_t *server_sync_status_create(void);
void server_sync_status_destroy(server_sync_status_t *status);

/* source is a short literal like "scheduler", "manual", "queue" -- not
 * copied, so callers must pass a string that outlives the call (a string
 * literal is the only expected usage). search_label may be NULL (e.g. the
 * scheduler's coarse "something is running" state, or a job not yet down to
 * a specific search). position/total are 0 when not applicable. */
void server_sync_status_set_active(server_sync_status_t *status, const char *source, const char *search_label, int position, int total);
void server_sync_status_clear(server_sync_status_t *status);

typedef struct
{
    bool active;
    char *source;       /* owned copy, NULL when !active; caller must free */
    char *search_label; /* owned copy, may be NULL even when active */
    int position;
    int total;
    time_t started_at; /* only meaningful when active */
} server_sync_status_snapshot_t;

/* Always succeeds; *out is zeroed (active = false) if no sync is running. */
void server_sync_status_get(server_sync_status_t *status, server_sync_status_snapshot_t *out);
void server_sync_status_snapshot_free(server_sync_status_snapshot_t *snapshot);

#endif /* BUNNY_SERVER_SYNC_STATUS_H */
