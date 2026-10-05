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

/* Tests username/secret against the real site without persisting anything --
 * builds a throwaway client (never touches bunny_db, unlike the three
 * functions above). e621 has no dedicated login endpoint (auth is per-request
 * Basic auth), so this makes one real authenticated call
 * (e621_list_favorites) and checks it doesn't fail; Inkbunny has an explicit
 * login call, used directly. Returns BUNNY_CORE_ERR_SITE if the site rejected
 * the credentials or the request otherwise failed (network, etc.) -- use
 * bunny_core_result_to_string for a message, same as every other site-facing
 * function here. */
bunny_core_result_t bunny_core_account_verify(bunny_core_t *core, bunny_db_site_t site, const char *username, const char *secret);

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

/* Fetches a single cached post by its local id -- a thin pass-through to
 * bunny_db, used when a post detail view needs to open a *different* post
 * it doesn't already have a BunnyPost for (e.g. after bunny_core_fetch_and_
 * cache_post caches a parent/child/pool-mate post by external id, this is
 * how its full data gets loaded for display). */
bunny_core_result_t bunny_core_post_get_by_id(bunny_core_t *core, int64_t post_id, bunny_db_post_t *out_post);

/* Ranks cached tags (from already-synced posts) by usage count, for a
 * search box's autocomplete -- a thin pass-through to bunny_db, same shape
 * as the search CRUD above. `prefix`'s characters are matched literally, not
 * as SQL LIKE wildcards. */
bunny_core_result_t bunny_core_tag_autocomplete(bunny_core_t *core, bunny_db_site_t site, const char *prefix, int limit, bunny_db_tag_stat_list_t *out_list);

/* Marks a post seen (global per post, not per search) -- lets a post detail
 * view clear the unseen marker bunny_core_search_list_posts's unseen_only
 * filter and bunny_db_post_t.is_seen are based on. Returns
 * BUNNY_CORE_ERR_INVALID_ARG for a post_id that doesn't exist in the local
 * post cache (a foreign-key violation, not a "not found" in the usual
 * sense -- see bunny_core_map_db_result). */
bunny_core_result_t bunny_core_post_mark_seen(bunny_core_t *core, int64_t post_id);

/* Bulk counterpart to bunny_core_post_mark_seen -- marks every post
 * currently linked to `search_id` as seen in one call, for a post grid's
 * "mark all as seen" action. */
bunny_core_result_t bunny_core_search_mark_all_seen(bunny_core_t *core, int64_t search_id);

/* A post's tags with their categories, for a post detail view's sectioned
 * tag display (Artists/Characters/Copyrights/Species/General/Meta for e621;
 * a single uncategorized group for Inkbunny, whose keywords have no category
 * concept at all) -- a thin pass-through to bunny_db. */
bunny_core_result_t bunny_core_post_get_tags_by_category(bunny_core_t *core, int64_t post_id, bunny_db_post_tag_list_t *out_list);

/* A post's source URLs, in the site's own order -- a thin pass-through to
 * bunny_db. Empty for a post with none (e.g. every Inkbunny submission). */
bunny_core_result_t bunny_core_post_get_sources(bunny_core_t *core, int64_t post_id, bunny_db_string_list_t *out_list);

/* A post's parent/child relationships (e621 only) -- a thin pass-through to
 * bunny_db. See bunny_db_post_get_relationships's doc comment for the
 * "no row = all-empty/OK, not NOT_FOUND" convention this follows. */
bunny_core_result_t bunny_core_post_get_relationships(bunny_core_t *core, int64_t post_id, bunny_db_post_relationships_t *out_relationships);

/* The e621 pool ids a post belongs to (empty for Inkbunny, or an e621 post
 * in no pools) -- a thin pass-through to bunny_db. */
bunny_core_result_t bunny_core_post_get_pool_ids(bunny_core_t *core, int64_t post_id, bunny_db_int64_list_t *out_list);

/* Fetches a single post live from its site and caches it (upserting into the
 * local post cache exactly like a sync pass would for one post), without
 * requiring it to already be linked to any saved search. Used when a
 * parent/child/pool chip on the detail page points at a post that was never
 * independently synced. Returns the (possibly pre-existing) local post id. */
bunny_core_result_t bunny_core_fetch_and_cache_post(bunny_core_t *core, bunny_db_site_t site, int64_t external_id, int64_t *out_post_id);

/* A pool's own metadata, fetched live (e621 only -- no persistence, no
 * equivalent on Inkbunny). Used only to auto-fill a pool search's label at
 * creation time; the pool's posts themselves are fetched via a normal
 * tag search for "pool:<id>" (bunny_core_search_create), not through this. */
typedef struct
{
    int64_t id;
    char *name;
    int64_t post_count;
} bunny_core_pool_info_t;

void bunny_core_pool_info_free(bunny_core_pool_info_t *info);

bunny_core_result_t bunny_core_fetch_pool(bunny_core_t *core, int64_t pool_id, bunny_core_pool_info_t *out_info);

/* Runs a single page of `query` live against `site` and upserts whatever
 * comes back into the local post cache (so thumbnails/ids are immediately
 * usable), *without* creating a searches/search_results row -- a stateless
 * "fetch and cache posts matching this query" call, used for the tag/artist
 * click-through browse screen rather than a saved search. */
bunny_core_result_t bunny_core_preview_search(bunny_core_t *core, bunny_db_site_t site, const char *query, bunny_db_post_list_t *out_list);

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

/* --- Action queue --------------------------------------------------------------
 * Proxies favorite/vote/comment calls to the sites: enqueue now (fast, no
 * network), process later via bunny_core_process_queue (typically on a
 * schedule, alongside bunny_core_sync_due_searches). `post_id` is the local
 * bunny_db post id, matching bunny_db_favorite_add/download_record's own
 * convention. Inkbunny has no vote or comment API at all (see
 * libs/inkbunny/include/inkbunny/client.h) -- queuing one against an
 * Inkbunny post is accepted (bunny_core doesn't know a post's site until
 * processing) but always fails when processed, with a clear error. Inkbunny
 * favoriting also always fails if no Inkbunny account is configured: the
 * unofficial favorite route (libs/inkbunny/include/inkbunny/
 * unofficial_favorites.h) has no guest mode. */

/* stars: Inkbunny's 1-3 rating, or -1 if not applicable (e621's plain favorite). */
bunny_core_result_t bunny_core_queue_favorite_add(bunny_core_t *core, int64_t post_id, int stars);
bunny_core_result_t bunny_core_queue_favorite_remove(bunny_core_t *core, int64_t post_id);
bunny_core_result_t bunny_core_queue_vote(bunny_core_t *core, int64_t post_id, int score, bool no_unvote);
bunny_core_result_t bunny_core_queue_comment(bunny_core_t *core, int64_t post_id, const char *body, bool anonymous);

typedef struct
{
    int actions_processed;
    int actions_succeeded;
    int actions_failed;
} bunny_core_queue_stats_t;

/* Drains all pending queued actions in order: resolves each to its post's
 * (site, external_id), builds a client for that site (same account lookup as
 * bunny_core_sync_due_searches; e621 clients are built once and reused across
 * a pass, Inkbunny actions each build/login their own since the unofficial
 * favorite route needs its own website session per client), calls the
 * matching site function, updates the local favorites mirror on success, and
 * marks the row done/failed. Always returns BUNNY_CORE_OK unless `core`
 * itself or listing pending actions fails; out_stats may be NULL. No retry
 * scheduling -- a failed action stays failed. */
bunny_core_result_t bunny_core_process_queue(bunny_core_t *core, bunny_core_queue_stats_t *out_stats);

#ifdef __cplusplus
}
#endif

#endif /* BUNNY_CORE_CORE_H */
