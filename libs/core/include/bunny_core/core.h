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

bunny_core_result_t bunny_core_search_create(bunny_core_t *core, bunny_db_site_t site, const char *label, const char *query, int interval_hours, const bunny_db_search_options_t *options, int64_t *out_id);
bunny_core_result_t bunny_core_search_delete(bunny_core_t *core, int64_t search_id);
bunny_core_result_t bunny_core_search_list(bunny_core_t *core, bunny_db_search_list_t *out_list);
bunny_core_result_t bunny_core_search_list_posts(bunny_core_t *core, int64_t search_id, bool unseen_only, bunny_db_post_list_t *out_list);

/* Pin/unpin a search, toggled directly from the searches list row (M14.1)
 * rather than through the full edit form -- see bunny_db_search_set_pinned. */
bunny_core_result_t bunny_core_search_set_pinned(bunny_core_t *core, int64_t search_id, bool pinned);

/* Marks a search/pool as opened right now -- see bunny_db_search_touch_last_viewed. */
bunny_core_result_t bunny_core_search_touch_last_viewed(bunny_core_t *core, int64_t search_id);

/* Updates a search's editable fields in place (M9.7.2) -- replaces
 * bunny_core_search_set_auto_favorite, so a search's label/query/interval/
 * auto-favorite/auto-upvote settings can all be changed from one edit screen
 * without deleting and recreating the search. The site itself is not
 * editable (not a param here). */
bunny_core_result_t bunny_core_search_update(bunny_core_t *core, int64_t search_id, const char *label, const char *query, int interval_hours, const bunny_db_search_options_t *options);

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

/* Tags of currently-favorited posts on `site`, ranked by how many favorited
 * posts carry them -- a thin pass-through to bunny_db, feeding a "most
 * favorited tags" browse screen (M10.2). Same shape as bunny_core_tag_
 * autocomplete above. */
bunny_core_result_t bunny_core_top_favorited_tags(bunny_core_t *core, bunny_db_site_t site, int limit, bunny_db_tag_stat_list_t *out_list);

/* Same ranking across every synced post on `site`, not just favorited ones
 * (M14.4) -- the Tag Stats screen's "All" view, alongside its "Favorites"
 * view above. */
bunny_core_result_t bunny_core_top_used_tags(bunny_core_t *core, bunny_db_site_t site, int limit, bunny_db_tag_stat_list_t *out_list);

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

/* Records that a file was downloaded for a post -- a thin pass-through to
 * bunny_db_download_record. The actual HTTP fetch, disk write, and checksum
 * computation are entirely client-side (never proxied through the server);
 * this call only persists the bookkeeping row afterward. */
bunny_core_result_t bunny_core_record_download(bunny_core_t *core, int64_t post_id, const char *file_path, const char *checksum_md5, bool verified, int64_t *out_id);

/* A post's download history, newest first -- a thin pass-through to
 * bunny_db_download_list_for_post. Empty for a post never downloaded. */
bunny_core_result_t bunny_core_list_downloads_for_post(bunny_core_t *core, int64_t post_id, bunny_db_download_list_t *out_list);

/* --- Tag blacklist (M13.3) -- thin pass-throughs to bunny_db_blacklist_*.
 * See bunny_db/db.h for which post-listing query the blacklist does (and
 * deliberately does not) apply to. */
bunny_core_result_t bunny_core_blacklist_list(bunny_core_t *core, bunny_db_site_t site, bunny_db_string_list_t *out_list);
bunny_core_result_t bunny_core_blacklist_add(bunny_core_t *core, bunny_db_site_t site, const char *tag);
bunny_core_result_t bunny_core_blacklist_remove(bunny_core_t *core, bunny_db_site_t site, const char *tag);

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

/* Runs a single page (1-indexed) of `query` live against `site` and upserts
 * whatever comes back into the local post cache (so thumbnails/ids are
 * immediately usable), *without* creating a searches/search_results row -- a
 * stateless "fetch and cache posts matching this query" call, used for the
 * tag/artist click-through browse screen's infinite scroll rather than a
 * saved search. Returns BUNNY_CORE_ERR_INVALID_ARG for page < 1. */
bunny_core_result_t bunny_core_preview_search(bunny_core_t *core, bunny_db_site_t site, const char *query, int page, bunny_db_post_list_t *out_list);

/* Inkbunny only -- e621's equivalent is just `fav:<username>` as a literal
 * bunny_core_preview_search query, since e621's tag search already supports
 * it natively. Inkbunny has no equivalent query syntax; it needs the
 * logged-in account's own numeric user id in a dedicated search param
 * (inkbunny_search_params_t.favorited_by_user_id) instead, resolved here via
 * the already-logged-in client bunny_core_build_inkbunny_client returns (M10.3)
 * -- no bunny_db changes, no caching, resolved fresh on every call. Same
 * "stateless fetch and cache" shape as bunny_core_preview_search otherwise:
 * upserts results without creating a searches/search_results row. Returns
 * BUNNY_CORE_ERR_INVALID_ARG for page < 1. */
bunny_core_result_t bunny_core_list_my_inkbunny_favorites(bunny_core_t *core, int page, bunny_db_post_list_t *out_list);

/* A post's existing comments, fetched live (e621 only -- no persistence, no
 * equivalent on Inkbunny, same reasoning as bunny_core_pool_info_t above).
 * Takes the local post id (not the site's external id) and looks up the
 * post's own site/external_id internally, matching every other per-post
 * read wrapper in this header. */
typedef struct
{
    int64_t id;
    char *creator_name;
    char *body;
    char *created_at;
} bunny_core_comment_t;

typedef struct
{
    bunny_core_comment_t *items;
    size_t count;
} bunny_core_comment_list_t;

void bunny_core_comment_list_free(bunny_core_comment_list_t *list);

bunny_core_result_t bunny_core_list_comments(bunny_core_t *core, int64_t post_id, bunny_core_comment_list_t *out_list);

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

/* Syncs exactly one search by id, unconditionally -- unlike
 * bunny_core_sync_due_searches, this ignores search_is_due() entirely, so a
 * search that was just synced a minute ago still gets checked again. Used
 * by a manual "check for updates" action that wants per-search progress
 * (M13.2), which a single batched bunny_core_sync_due_searches call can't
 * give a caller mid-flight. Returns BUNNY_CORE_ERR_NOT_FOUND if no search
 * with that id exists; out_stats (searches_checked/searches_synced always
 * 0 or 1 here) may be NULL. */
bunny_core_result_t bunny_core_sync_search(bunny_core_t *core, int64_t search_id, bunny_core_sync_stats_t *out_stats);

/* Writes a timestamped backup (`<backups_dir>/bunny_<unix_ts>.db`) of the
 * live database into `backups_dir` via bunny_db_backup -- the server's own
 * periodic backup job (M14.5, server/src/scheduler.c), never called from the
 * Flutter app. `backups_dir` must already exist. */
bunny_core_result_t bunny_core_backup_database(bunny_core_t *core, const char *backups_dir);

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
