#ifndef BUNNY_SERVER_CONTEXT_H
#define BUNNY_SERVER_CONTEXT_H

#include <bunny_core/core.h>

#include "auth.h"

/* Shared state every request handler and the background scheduler (M5.3)
 * need. bunny_core is internally thread-safe -- every bunny_core_* call
 * serializes its own access to core->db via a lock it owns itself
 * (libs/core/src/internal.h's db_mutex), and never holds that lock across a
 * network call. The server does no locking of its own around bunny_core_*
 * calls; civetweb's worker-thread pool and the scheduler thread call
 * straight into bunny_core with no external synchronization needed. */
typedef struct
{
    bunny_core_t *core;
    const server_auth_t *auth;
} server_context_t;

#endif /* BUNNY_SERVER_CONTEXT_H */
