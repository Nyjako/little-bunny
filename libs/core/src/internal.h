#ifndef BUNNY_CORE_INTERNAL_H
#define BUNNY_CORE_INTERNAL_H

#include <bunny_common/thread.h>
#include <e621/client.h>
#include <inkbunny/client.h>

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bunny_core/core.h"
#include "bunny_core/error.h"
#include "bunny_db/db.h"

/* Read pool size (M25): matches civetweb's own num_threads (server/src/app.c)
 * so up to that many concurrent GET requests (searches list, tag stats, a
 * second device's own requests, ...) can each get their own connection
 * instead of queuing behind one another -- see bunny_core_db_read_lock
 * below for why this exists at all. */
#define BUNNY_CORE_READ_POOL_SIZE 4

struct bunny_core
{
    bunny_db_t *db;
    bunny_mutex_t db_mutex; /* serializes every WRITE to core->db; NEVER held
                             * across a network call (e621_/inkbunny_
                             * functions or curl) -- see sync.c/queue.c/site_clients.c/
                             * backup.c/accounts.c/searches.c/blacklist.c/
                             * downloads.c for the lock-only-around-db-ops
                             * pattern every write-touching bunny_core_*
                             * function follows. verify.c is the one
                             * exception: it never touches core->db at all,
                             * so it needs no lock. Pure reads go through
                             * read_dbs/bunny_core_db_read_lock instead --
                             * see the comment there. */
    /* M25: a small pool of extra connections to the same database file,
     * used by every pure-read bunny_core_* function (bunny_core_search_list,
     * bunny_core_top_used_tags, ...) instead of db_mutex/db. Before this,
     * EVERY db access -- reads and writes alike -- serialized through the
     * single db_mutex above, so a slow write (a big sync's batched insert)
     * or a slow read (an unindexed tag-stats aggregate over a large table)
     * blocked every other request for its entire duration, including a
     * second device's plain GET /searches. WAL mode (enabled in
     * bunny_db_open) is what makes this actually work: separate connections
     * to the same WAL database don't block each other for reads, and don't
     * block the one writer either. NULL/unused (has_read_pool false) for
     * ":memory:" databases (every test's db_path) -- SQLite gives each
     * ":memory:" open its own independent, empty database, so a pool of
     * them wouldn't see the writer's data at all; those fall back to
     * db/db_mutex for reads too, same as before this existed. Each slot's
     * own mutex (not one shared read mutex) is what lets multiple reads
     * actually run in parallel instead of just moving the serialization
     * point from db_mutex to a single shared read lock. */
    bool has_read_pool;
    bunny_db_t *read_dbs[BUNNY_CORE_READ_POOL_SIZE];
    bunny_mutex_t read_mutexes[BUNNY_CORE_READ_POOL_SIZE];
    bunny_mutex_t read_rr_mutex; /* guards next_read_slot only, held very briefly */
    size_t next_read_slot;
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

/* Every bunny_core_* function that only READS core->db (never INSERT/UPDATE/
 * DELETE) uses this pair instead of bunny_core_db_lock/unlock -- picks the
 * next read connection round-robin, locks just that slot's own mutex (not a
 * single shared one, so concurrent reads can actually run in parallel
 * instead of queuing), and returns which bunny_db_t* to call the matching
 * bunny_db_* read function on. *out_slot is BUNNY_CORE_READ_POOL_SIZE as a
 * sentinel meaning "fell back to db_mutex/db" (the :memory: case, see
 * has_read_pool above) -- bunny_core_db_read_unlock checks for that same
 * sentinel, so callers never need to branch on it themselves. Not
 * re-entrant, same rule as bunny_core_db_lock. */
static inline bunny_db_t *bunny_core_db_read_lock(bunny_core_t *core, size_t *out_slot)
{
    if (!core->has_read_pool) {
        bunny_mutex_lock(&core->db_mutex);
        *out_slot = BUNNY_CORE_READ_POOL_SIZE;
        return core->db;
    }
    bunny_mutex_lock(&core->read_rr_mutex);
    size_t slot = core->next_read_slot;
    core->next_read_slot = (slot + 1) % BUNNY_CORE_READ_POOL_SIZE;
    bunny_mutex_unlock(&core->read_rr_mutex);

    bunny_mutex_lock(&core->read_mutexes[slot]);
    *out_slot = slot;
    return core->read_dbs[slot];
}

static inline void bunny_core_db_read_unlock(bunny_core_t *core, size_t slot)
{
    if (slot == BUNNY_CORE_READ_POOL_SIZE) {
        bunny_mutex_unlock(&core->db_mutex);
        return;
    }
    bunny_mutex_unlock(&core->read_mutexes[slot]);
}

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

/* "pool:<id>" is the literal query string every pool search is created with
 * (bunny_core_search_create, see the app's BunnySearch.isPool) -- true only
 * when `query` is exactly that shape, writing the numeric id to
 * *out_pool_id. Shared by sync.c (which pool to sync the order of) and
 * searches.c (which pool to order a search's posts by, M26). */
static inline bool bunny_core_parse_pool_id_from_query(const char *query, int64_t *out_pool_id)
{
    if (strncmp(query, "pool:", 5) != 0) {
        return false;
    }
    char *endptr = NULL;
    long long value = strtoll(query + 5, &endptr, 10);
    if (endptr == query + 5 || *endptr != '\0') {
        return false;
    }
    *out_pool_id = (int64_t)value;
    return true;
}

/* Same "fav:<username>"/"favorited_by:me" sentinel-query convention the app
 * side's BunnySearch.isFavorites already documents -- mirrors it exactly so
 * a favorites search is recognizable server/core-side too (M37: favorites
 * and pool searches are both exempt from blacklist filtering, which needs
 * to tell them apart from an ordinary search). */
static inline bool bunny_core_is_favorites_query(bunny_db_site_t site, const char *query)
{
    if (site == BUNNY_DB_SITE_E621) {
        return strncmp(query, "fav:", 4) == 0;
    }
    return strcmp(query, "favorited_by:me") == 0;
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
