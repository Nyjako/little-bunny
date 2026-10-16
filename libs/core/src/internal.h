#ifndef BUNNY_CORE_INTERNAL_H
#define BUNNY_CORE_INTERNAL_H

#include <bunny_common/thread.h>
#include <e621/client.h>
#include <inkbunny/client.h>

#include <stdarg.h>
#include <stdio.h>

#include "bunny_core/core.h"
#include "bunny_core/error.h"
#include "bunny_db/db.h"

struct bunny_core
{
    bunny_db_t *db;
    bunny_mutex_t db_mutex; /* serializes every core->db access; NEVER held
                             * across a network call (e621_/inkbunny_
                             * functions or curl) -- see sync.c/queue.c/site_clients.c/
                             * backup.c/accounts.c/searches.c/blacklist.c/
                             * downloads.c for the lock-only-around-db-ops
                             * pattern every bunny_core_* function follows.
                             * verify.c is the one exception: it never
                             * touches core->db at all, so it needs no lock. */
    bunny_mutex_t sync_mutex; /* serializes the site-facing sync operations
                               * against EACH OTHER (sync_e621_search/
                               * sync_inkbunny_search, bunny_core_process_
                               * queue -- see sync.c/queue.c) so the server
                               * never has more than one of these talking to
                               * e621/Inkbunny at once, whether triggered by
                               * the scheduler or a manual request. This is
                               * separate from db_mutex on purpose: it's
                               * held across network I/O deliberately (that
                               * IS the point), while db_mutex never is.
                               * Interactive one-off calls (preview_search,
                               * fetch_pool, account_verify, ...) do NOT take
                               * this lock, so browsing stays responsive
                               * even while a long sync is in progress. */
    char *user_agent;
    const bunny_http_transport_t *e621_transport;
    const bunny_http_transport_t *inkbunny_transport;
    double min_request_interval_sec;
    bunny_core_log_fn log_callback;
    void *log_user_data;
};

/* Every bunny_core_* function that touches core->db locks/unlocks through
 * these -- never bunny_mutex_lock/unlock(&core->db_mutex) directly -- so
 * the intent is explicit and grep-able at every call site. Not re-entrant:
 * never call a function that takes this lock itself (e.g.
 * bunny_core_queue_favorite_add) while already holding it, or the calling
 * thread deadlocks against itself. */
static inline void bunny_core_db_lock(bunny_core_t *core) { bunny_mutex_lock(&core->db_mutex); }
static inline void bunny_core_db_unlock(bunny_core_t *core) { bunny_mutex_unlock(&core->db_mutex); }

/* See sync_mutex above -- held around the entire body of a site-syncing
 * function (network calls included), never nested with another call that
 * also takes it. */
static inline void bunny_core_sync_lock(bunny_core_t *core) { bunny_mutex_lock(&core->sync_mutex); }
static inline void bunny_core_sync_unlock(bunny_core_t *core) { bunny_mutex_unlock(&core->sync_mutex); }

/* printf-style wrapper around core->log_callback -- no-op if none is set
 * (standalone/FFI mode). Used by sync.c to report per-search sync progress. */
#if defined(__GNUC__) || defined(__clang__)
__attribute__((format(printf, 3, 4)))
#endif
static inline void
bunny_core_log(bunny_core_t *core, const char *level, const char *fmt, ...)
{
    if (!core->log_callback) {
        return;
    }
    char message[512];
    va_list args;
    va_start(args, fmt);
    vsnprintf(message, sizeof(message), fmt, args);
    va_end(args);
    core->log_callback(core->log_user_data, level, message);
}

static inline bunny_core_result_t bunny_core_map_db_result(bunny_db_result_t result)
{
    switch (result) {
        case BUNNY_DB_OK:
            return BUNNY_CORE_OK;
        case BUNNY_DB_ERR_INVALID_ARG:
            return BUNNY_CORE_ERR_INVALID_ARG;
        case BUNNY_DB_ERR_NOT_FOUND:
            return BUNNY_CORE_ERR_NOT_FOUND;
        case BUNNY_DB_ERR_CONSTRAINT:
            /* e.g. a foreign-key violation from an id that doesn't exist --
             * that's bad caller input, not a server-side failure. */
            return BUNNY_CORE_ERR_INVALID_ARG;
        default:
            return BUNNY_CORE_ERR_DB;
    }
}

/* Shared by sync.c and queue.c (libs/core/src/site_clients.c). Both build a
 * client for a search/action's site using the stored account if present. */

/* NULL only on allocation failure -- e621_client_create never touches the
 * network itself. */
e621_client_t *bunny_core_build_e621_client(bunny_core_t *core);

/* Builds a client and logs it in (guest login if no account is stored).
 * NULL if either step fails; the client is destroyed internally on login
 * failure so callers never get a half-usable handle. */
inkbunny_client_t *bunny_core_build_inkbunny_client(bunny_core_t *core);

#endif /* BUNNY_CORE_INTERNAL_H */
