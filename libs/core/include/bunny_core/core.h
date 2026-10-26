#ifndef BUNNY_CORE_CORE_H
#define BUNNY_CORE_CORE_H

#include <bunny_common/http.h>

#include "bunny_core/error.h"
#include "bunny_db/types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct bunny_core bunny_core_t;

/* Optional sink for human-readable progress/summary lines emitted during
 * bunny_core_sync_due_searches/bunny_core_sync_search (e.g. "Starting full
 * scan for ... (12/700)", "Scanned ... -- found 8 posts, 3 new"). NULL (the
 * default, e.g. standalone/FFI mode) means these lines are simply dropped --
 * there's no log viewer for standalone mode anyway. The server installs one
 * that forwards into its own ring-buffer logger (see server/src/app.c,
 * server/src/log.h). `level` is a short tag like "INFO"; neither pointer is
 * owned by bunny_core. */
typedef void (*bunny_core_log_fn)(void *user_data, const char *level, const char *message);

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

    bunny_core_log_fn log_callback; /* see bunny_core_log_fn above; NULL = no-op */
    void *log_user_data;
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

/* Folds a pre-existing (site, query) duplicate into keeper_id (M41) -- a thin
 * pass-through to bunny_db_search_merge_duplicate. */
bunny_core_result_t bunny_core_search_merge_duplicate(bunny_core_t *core, int64_t keeper_id, int64_t duplicate_id);

bunny_core_result_t bunny_core_search_list(bunny_core_t *core, bunny_db_search_list_t *out_list);
/* page is 1-indexed -- see bunny_db_search_list_posts' own doc comment for
 * why this is paginated at all (an unbounded response for a search with
 * thousands of posts routinely timed out client-side). */
bunny_core_result_t bunny_core_search_list_posts(bunny_core_t *core, int64_t search_id, bool unseen_only, int page, bunny_db_post_list_t *out_list);

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

/* Server-wide default sync interval (hours) -- what a search with
 * uses_default_interval set actually follows for scheduling, re-resolved on
 * every due-check rather than frozen at creation time. See
 * bunny_db_search_options_t.uses_default_interval and search_is_due()
 * (sync.c). Seeded to 24 on first db open. */
bunny_core_result_t bunny_core_get_default_sync_interval_hours(bunny_core_t *core, int *out_hours);
bunny_core_result_t bunny_core_set_default_sync_interval_hours(bunny_core_t *core, int hours);

/* --- Search groups (M21) ---------------------------------------------------
 * A flat, non-nested way to organize saved searches into folder-like groups
 * in SearchesScreen's tree view -- see bunny_db_group_t. */

/* Moves a search into group_id's group, or ungroups it when group_id is 0 --
 * see bunny_db_search_set_group. */
bunny_core_result_t bunny_core_search_set_group(bunny_core_t *core, int64_t search_id, int64_t group_id);

bunny_core_result_t bunny_core_group_create(bunny_core_t *core, const char *name, bool pinned, int64_t *out_id);
bunny_core_result_t bunny_core_group_list(bunny_core_t *core, bunny_db_group_list_t *out_list);
bunny_core_result_t bunny_core_group_update(bunny_core_t *core, int64_t group_id, const char *name, bool pinned);

/* Deletes the group; member searches are ungrouped, not deleted (enforced
 * by the DB's own ON DELETE SET NULL foreign key -- see bunny_db_group_delete). */
bunny_core_result_t bunny_core_group_delete(bunny_core_t *core, int64_t group_id);

/* Fetches a single cached post by its local id -- a thin pass-through to
 * bunny_db, used when a post detail view needs to open a *different* post
 * it doesn't already have a BunnyPost for (e.g. after bunny_core_fetch_and_
 * cache_post caches a parent/child/pool-mate post by external id, this is
 * how its full data gets loaded for display). */
bunny_core_result_t bunny_core_post_get_by_id(bunny_core_t *core, int64_t post_id, bunny_db_post_t *out_post);

/* Ranks cached tags (from already-synced posts) by usage count, for a
 * search box's autocomplete. `prefix`'s characters are matched literally,
 * not as SQL LIKE wildcards. A `prefix` shorter than 5 characters returns an
 * empty list without querying the database at all, and the result count is
 * always capped at 5 regardless of `limit` -- both throttles exist because a
 * short prefix matches far too many tags for the LIKE index to narrow
 * usefully, which could otherwise hang the server on a single keystroke
 * (M39). */
bunny_core_result_t bunny_core_tag_autocomplete(bunny_core_t *core, bunny_db_site_t site, const char *prefix, int limit, bunny_db_tag_stat_list_t *out_list);

/* Tags of currently-favorited posts on `site`, ranked by how many favorited
 * posts carry them -- a thin pass-through to bunny_db, feeding a "most
 * favorited tags" browse screen (M10.2). Same shape as bunny_core_tag_
 * autocomplete above. */
bunny_core_result_t bunny_core_top_favorited_tags(bunny_core_t *core, bunny_db_site_t site, int limit, bunny_db_tag_stat_list_t *out_list);

/* Same ranking across every synced post on `site`, not just favorited ones
 * (M14.4) -- feeds bunny_core_get_stats_report below, merged across both
 * sites. No longer surfaced as its own per-site screen (M40 removed the
 * tag-stats screen's site tabs). */
bunny_core_result_t bunny_core_top_used_tags(bunny_core_t *core, bunny_db_site_t site, int limit, bunny_db_tag_stat_list_t *out_list);

/* The tag-stats screen's unified report (M40), replacing what used to be
 * four separate per-site/per-kind queries run fresh on every page open --
 * each of those is a full-table aggregate (bunny_db_top_favorited_tags,
 * bunny_db_top_used_tags, bunny_db_top_favorited_pools,
 * bunny_db_top_viewed_searches), and running all four live every time the
 * screen opened is what hung it. A section's name/count entries use the
 * generic bunny_db_tag_stat_t shape even for pools/searches (see
 * bunny_db_top_favorited_pools/bunny_db_top_viewed_searches' own doc
 * comments for what `name` means in each) -- `top_pools` is e621-only
 * (Inkbunny has no pool concept), the other three sections merge both
 * sites' own rankings into one combined top-N, each `name` prefixed with
 * its site ("e621: ", "inkbunny: ") since the same tag/label text can
 * legitimately exist on both. */
typedef struct
{
    bunny_db_tag_stat_list_t top_favorited_tags;
    bunny_db_tag_stat_list_t top_used_tags;
    bunny_db_tag_stat_list_t top_pools;
    bunny_db_tag_stat_list_t top_viewed_searches;
    char *computed_at; /* ISO 8601 UTC; NULL if no report has ever been built yet */
} bunny_core_stats_report_t;

void bunny_core_stats_report_free(bunny_core_stats_report_t *report);

/* Reads whatever report is currently cached WITHOUT ever building or
 * recomputing one (M55) -- each section is a full-table aggregate, and on
 * a large enough database bunny_core_refresh_stats_report below can run for
 * minutes, which is exactly what hung the server when this used to build
 * synchronously on a cache miss. `*out_has_cache` is false (and `*out_report`
 * left zeroed) if nothing has ever been cached; `*out_is_stale` is true
 * whenever there's no cache at all, or the cached one is 24+ hours old --
 * callers that want the report kept warm should check `*out_is_stale` and
 * enqueue a `bunny_core_refresh_stats_report` call on a background worker
 * themselves (see server/src/task_queue.c's TASK_TYPE_BUILD_STATS_REPORT),
 * never call it inline on whatever thread is answering a live request. */
bunny_core_result_t bunny_core_get_cached_stats_report(bunny_core_t *core, bunny_core_stats_report_t *out_report, bool *out_has_cache, bool *out_is_stale);

/* Recomputes the report from scratch and caches the fresh result,
 * regardless of the previously-cached one's age -- this is the slow,
 * potentially multi-minute call bunny_core_get_cached_stats_report's own
 * doc comment warns about. Only ever call this from a background worker
 * thread, never from a thread that's also expected to answer other
 * requests promptly. */
bunny_core_result_t bunny_core_refresh_stats_report(bunny_core_t *core, bunny_core_stats_report_t *out_report);

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

/* --- Tag blacklist (M13.3) -- thin pass-throughs to bunny_db_blacklist_*.
 * See bunny_db/db.h for which post-listing query the blacklist does (and
 * deliberately does not) apply to. */
bunny_core_result_t bunny_core_blacklist_list(bunny_core_t *core, bunny_db_site_t site, bunny_db_string_list_t *out_list);
bunny_core_result_t bunny_core_blacklist_add(bunny_core_t *core, bunny_db_site_t site, const char *tag);
bunny_core_result_t bunny_core_blacklist_remove(bunny_core_t *core, bunny_db_site_t site, const char *tag);

typedef struct
{
    int added;             /* new single-tag entries imported */
    int already_present;   /* entries that matched an existing local tag */
    int skipped_multi_tag; /* e621 "AND" lines (e.g. "rating:e young") -- not yet a local blacklist concept */
} bunny_core_blacklist_sync_stats_t;

/* Pulls the e621 account's own blacklist (My Account -> Blacklisted Tags on
 * e621.net, see tools/e621_blacklist_experiment/e621_blacklist.py for the
 * API this mirrors) and imports every single-tag line that isn't already
 * present locally. Read-only on e621's side -- never writes anything back
 * to the site. Requires an e621 account to already be configured
 * (bunny_core_account_set), since e621 only returns blacklisted_tags when
 * authenticated as that same account -- returns BUNNY_CORE_ERR_SITE
 * otherwise (same as any other e621 call with no usable client). Lines with
 * more than one space-separated tag are e621's "AND" groups (match only
 * when every tag on that line matches a post); the local blacklist has no
 * such concept yet, so those are skipped and counted separately in
 * out_stats rather than silently dropped or misinterpreted as one literal
 * (space-containing) tag. */
bunny_core_result_t bunny_core_sync_e621_blacklist(bunny_core_t *core, bunny_core_blacklist_sync_stats_t *out_stats);

/* Fetches a single post live from its site and caches it (upserting into the
 * local post cache exactly like a sync pass would for one post), without
 * requiring it to already be linked to any saved search. Used when a
 * parent/child/pool chip on the detail page points at a post that was never
 * independently synced. Returns the (possibly pre-existing) local post id. */
bunny_core_result_t bunny_core_fetch_and_cache_post(bunny_core_t *core, bunny_db_site_t site, int64_t external_id, int64_t *out_post_id);

/* A pool's own metadata, fetched live (e621 only -- no persistence, no
 * equivalent on Inkbunny). Used to auto-fill a pool search's label at
 * creation time, and to show the pool's own description (M26) -- the
 * pool's posts themselves are fetched via a normal tag search for
 * "pool:<id>" (bunny_core_search_create), not through this. */
typedef struct
{
    int64_t id;
    char *name;
    char *description; /* e621's own dtext markup, verbatim; NULL if empty */
    int64_t post_count;

    /* Every "pool #<N>" mention found in `description` (M26) -- e621 pool
     * descriptions routinely cross-reference related/continuation pools
     * this way (see bunny_core_fetch_pool's doc comment). In first-seen
     * order, duplicates included. Empty when description has none or is
     * NULL. */
    int64_t *referenced_pool_ids;
    size_t referenced_pool_id_count;
} bunny_core_pool_info_t;

void bunny_core_pool_info_free(bunny_core_pool_info_t *info);

/* referenced_pool_ids (above) is populated by scanning the fetched
 * description for e621's own "pool #<N>" dtext convention -- callers don't
 * need to parse it themselves. */
bunny_core_result_t bunny_core_fetch_pool(bunny_core_t *core, int64_t pool_id, bunny_core_pool_info_t *out_info);

/* Fetches `pool_id`'s own post_ids from e621 (its real, authoritative
 * reading order) and writes each entry's index as its `position` in
 * post_pools for any of those posts already cached locally (M26) -- called
 * once per sync of a "pool:<id>" search (see sync_e621_search) so
 * PostGridScreen can show a pool in the order e621 itself intends instead
 * of guessing from upload date, which is wrong whenever pages were
 * uploaded out of order (a common occurrence for ongoing comics). A
 * network + db call, same shape as bunny_core_fetch_and_cache_post. */
bunny_core_result_t bunny_core_sync_pool_order(bunny_core_t *core, int64_t pool_id);

/* One-time backfill (M26): re-fetches every pool_id already present in
 * post_pools (from before the `position` column existed) via
 * bunny_core_sync_pool_order, so already-synced pools get correct order
 * immediately rather than waiting for their search's own next sync. No-op
 * (BUNNY_CORE_OK immediately) if server_settings.pool_positions_backfilled
 * is already set; sets it once this completes, successfully or not --
 * see the call sites (scheduler.c's first tick, standalone's FfiBunnyRepository.open)
 * for why "never retry automatically" is the right call here: a handful of
 * stale pools is a much smaller problem than this blocking startup or
 * burning e621 rate-limit budget on every single launch. */
bunny_core_result_t bunny_core_backfill_pool_positions_once(bunny_core_t *core);

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

    /* Seconds until the soonest not-yet-due search (across every search
     * bunny_core_sync_due_searches looked at) actually becomes due, or -1 if
     * there were no searches to check at all (M28) -- diagnoses "0 synced"
     * from the logs alone: confirms whether that's simply because nothing's
     * due yet (a large positive value here) versus a potential scheduling
     * bug (a value near/below 0 despite 0 synced would be a contradiction
     * worth investigating). Always 0 from bunny_core_sync_search, which
     * forces a sync regardless of due-ness -- "time until due" doesn't apply
     * there. */
    double seconds_until_next_due;
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

/* --- Diagnostics ----------------------------------------------------------
 * Backs `bunny_server --db-stats`/`--health` (server/src/main.c) -- thin
 * read-locked pass-throughs to bunny_db_table_stats/bunny_db_integrity_check,
 * same pattern as bunny_core_search_list -> bunny_db_search_list. */
bunny_core_result_t bunny_core_table_stats(bunny_core_t *core, bunny_db_tag_stat_list_t *out_list);
bunny_core_result_t bunny_core_integrity_check(bunny_core_t *core, bool *out_ok);

#ifdef __cplusplus
}
#endif

#endif /* BUNNY_CORE_CORE_H */
