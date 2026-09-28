#ifndef BUNNY_CORE_CORE_H
#define BUNNY_CORE_CORE_H

#include <bunny_common/http.h>

#include "bunny_core/error.h"
#include "bunny_db/types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct bunny_core bunny_core_t;

typedef struct
{
    const char *db_path;    /* required; a filesystem path, or ":memory:" for tests */
    const char *user_agent; /* required; e621's API etiquette needs a descriptive UA string */

    /* Overrides the HTTP transport used for e621/Inkbunny clients built internally
     * by bunny_core_sync_due_searches and the action queue. Pass NULL to use the
     * real curl-backed transport for that site; tests inject fakes here. */
    const bunny_http_transport_t *e621_transport;
    const bunny_http_transport_t *inkbunny_transport;

    /* Passed straight through to e621_config_t/inkbunny_config_t's own field
     * of the same name; 0 => each library's built-in default (~0.5s, real
     * rate limiting). Tests set a negligible value so a sync pass that
     * touches both sites doesn't take the better part of a second. */
    double min_request_interval_sec;
} bunny_core_config_t;

/* Opens (creating if needed) the underlying bunny_db database and applies its
 * schema. */
bunny_core_result_t bunny_core_open(const bunny_core_config_t *config, bunny_core_t **out_core);
void bunny_core_close(bunny_core_t *core);

/* --- Account credentials ----------------------------------------------------
 * One account per site (e621 API key, or Inkbunny username/password), stored
 * as plain text via bunny_db: the server reads these unattended to run
 * scheduled syncs, so there's no passphrase-gated encryption layer here.
 * App-lock (password/PIN/fingerprint), if used, is a separate per-device
 * client concern (M7) with no relationship to this storage -- see
 * docs/architecture.md. Setting an account again for the same site replaces
 * it (upsert). */

bunny_core_result_t bunny_core_account_set(bunny_core_t *core, bunny_db_site_t site, const char *username, const char *secret);
bunny_core_result_t bunny_core_account_get(bunny_core_t *core, bunny_db_site_t site, bunny_db_account_t *out_account);
bunny_core_result_t bunny_core_account_delete(bunny_core_t *core, bunny_db_site_t site);

/* --- Searches -----------------------------------------------------------------
 * Thin pass-throughs to bunny_db's search CRUD: bunny_core is the single
 * entry point apps use (standalone FFI or networked server), so it needs to
 * expose these even though bunny_core itself only ever reads searches (via
 * bunny_core_sync_due_searches below). bunny_core_search_list_posts is what
 * a search's synced results (see below) are read back through. */

bunny_core_result_t bunny_core_search_create(bunny_core_t *core, bunny_db_site_t site, const char *label, const char *query, int interval_hours, int64_t *out_id);
bunny_core_result_t bunny_core_search_delete(bunny_core_t *core, int64_t search_id);
bunny_core_result_t bunny_core_search_list(bunny_core_t *core, bunny_db_search_list_t *out_list);
bunny_core_result_t bunny_core_search_list_posts(bunny_core_t *core, int64_t search_id, bool unseen_only, bunny_db_post_list_t *out_list);

/* --- Scheduled search sync --------------------------------------------------- */

typedef struct
{
    int searches_checked; /* how many saved searches bunny_core_sync_due_searches looked at */
    int searches_synced;  /* how many were due and synced successfully */
    int posts_upserted;   /* total posts cached/updated across all synced searches */
} bunny_core_sync_stats_t;

/* Runs every saved search whose last run is NULL or older than its
 * interval_hours: builds a client for that search's site (authenticated via
 * the stored account if one exists, or anonymous/guest otherwise), fetches
 * results, upserts them into the post cache, links them to the search, and
 * touches last_run_at. A search that fails to sync (network error, no
 * Inkbunny guest access, etc.) is simply left due and retried on the next
 * call -- there's no retry scheduling in M4. Always returns BUNNY_CORE_OK
 * unless `core` itself or listing the searches fails; out_stats may be NULL. */
bunny_core_result_t bunny_core_sync_due_searches(bunny_core_t *core, bunny_core_sync_stats_t *out_stats);

#ifdef __cplusplus
}
#endif

#endif /* BUNNY_CORE_CORE_H */
