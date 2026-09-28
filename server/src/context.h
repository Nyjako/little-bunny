#ifndef BUNNY_SERVER_CONTEXT_H
#define BUNNY_SERVER_CONTEXT_H

#include <pthread.h>

#include <bunny_core/core.h>

#include "auth.h"

/* Shared state every request handler and the background scheduler (M5.3)
 * need. `core_mutex` serializes access to `core`, since neither bunny_core
 * nor bunny_db were designed for concurrent access, and civetweb runs a
 * worker-thread pool. Every bunny_core_* call from a handler or the
 * scheduler must be wrapped in pthread_mutex_lock/unlock(&core_mutex). */
typedef struct
{
    bunny_core_t *core;
    pthread_mutex_t core_mutex;
    const server_auth_t *auth;
} server_context_t;

#endif /* BUNNY_SERVER_CONTEXT_H */
