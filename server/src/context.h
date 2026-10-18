#ifndef BUNNY_SERVER_CONTEXT_H
#define BUNNY_SERVER_CONTEXT_H

#include <bunny_core/core.h>

#include "auth.h"
#include "sync_status.h"
#include "task_queue.h"

/* Shared state every request handler and the background scheduler (M5.3)
 * need. bunny_core is internally thread-safe -- every bunny_core_* call
 * serializes its own access to core->db via a lock it owns itself
 * (libs/core/src/internal.h's db_mutex), and never holds that lock across a
 * network call. The server does no locking of its own around bunny_core_*
 * calls; civetweb's worker-thread pool calls straight into bunny_core with
 * no external synchronization needed.
 *
 * task_queue/sync_status are the one exception to "just call bunny_core
 * directly": route handlers that would otherwise block a civetweb worker
 * thread for an entire sync's duration (POST /searches/{id}/sync, POST
 * /searches/sync-all, POST /sync) go through task_queue instead, as does the
 * scheduler's own periodic due-search sync and action-queue drain (M24) --
 * see task_queue.h for why. POST /queue/process is the one deliberate
 * exception -- see routes_queue.c's handle_queue_process. */
typedef struct
{
    bunny_core_t *core;
    const server_auth_t *auth;
    task_queue_t *task_queue;
    server_sync_status_t *sync_status;
} server_context_t;

#endif /* BUNNY_SERVER_CONTEXT_H */
