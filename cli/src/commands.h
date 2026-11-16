#ifndef BUNNY_CLI_COMMANDS_H
#define BUNNY_CLI_COMMANDS_H

#include "handshake.h" /* bunny_cli_mode_t -- reused as-is rather than a second mode enum */
#include "rest_client.h"

#include <bunny_core/core.h>
#include <bunny_db/types.h>

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* What every bunny_cli_cmd_* below actually operates against -- resolved
 * once in main.c right after the handshake and passed down instead of each
 * command re-deciding which mode it's in from scratch. `mode` is never
 * BUNNY_CLI_MODE_NONE here -- main.c already exits before building a
 * context in that case.
 *
 * `core` is the LOCAL download-queue database -- always used for queue
 * bookkeeping (claim/list/set_status), in both modes: in
 * BUNNY_CLI_MODE_STANDALONE it's the one real database (posts, searches,
 * the queue, everything); in BUNNY_CLI_MODE_NETWORKED it's the app's own
 * small queue-only db (handshake's download_queue_db_path), since the
 * server never proxies downloads or stores this queue itself
 * (docs/architecture.md's "Downloads are client-side" section). It may
 * still be NULL in networked mode if the handshake didn't report a queue
 * db path (an older app build) -- bunny_cli_cmd_download/_queue_list check
 * for that themselves rather than crashing.
 *
 * `rest` is non-NULL only in BUNNY_CLI_MODE_NETWORKED -- the REST client
 * used for everything that actually needs the server (search, pool,
 * favorite/vote, blacklist, sync, and resolving a post's own metadata
 * before downloading it, since the local queue db above only ever stores
 * post ids, never post data).
 *
 * `auto_favorite_on_download`/`auto_upvote_on_download` mirror the app's
 * own global Settings toggles of the same name (DownloadSettingsStore) --
 * reported by the handshake for both modes, default false if the app
 * build doesn't report them. bunny_cli_cmd_download applies them to every
 * post it downloads, exactly like DownloadQueueService's own worker does
 * (queues the action only, never drains per item -- see that function's
 * own doc comment for why), the same as the app itself. */
typedef struct
{
    bunny_cli_mode_t mode;
    bunny_core_t *core;            /* the local download-queue db, both modes (see above) -- may be NULL in networked mode */
    bunny_cli_rest_client_t *rest; /* BUNNY_CLI_MODE_NETWORKED only */
    bool auto_favorite_on_download;
    bool auto_upvote_on_download;
} bunny_cli_context_t;

/* A single `--download` spec argument, parsed from its raw CLI text (e.g.
 * "pool:115522", "search:12", or a bare tag query like "female standing")
 * -- see bunny_cli_cmd_download's own doc comment for what each kind
 * resolves to. Exposed (rather than kept static in commands.c) purely so
 * the parsing itself -- id extraction, malformed input -- has direct unit
 * test coverage without needing a real core/rest client. */
typedef enum
{
    BUNNY_CLI_SPEC_POOL,   /* "pool:<id>" -- e621 only */
    BUNNY_CLI_SPEC_SEARCH, /* "search:<id>" -- one of the app's own saved searches, by id */
    BUNNY_CLI_SPEC_TAGS,   /* anything else -- a plain ad-hoc tag query */
} bunny_cli_spec_kind_t;

/* Parses `spec`'s kind and, for BUNNY_CLI_SPEC_POOL/BUNNY_CLI_SPEC_SEARCH,
 * the id that follows the prefix. Returns false for a malformed
 * "pool:"/"search:" prefix (no id, a non-numeric id, or id <= 0) -- a
 * caller should report that as a clear per-spec error, not silently fall
 * back to treating it as a tag query (a typo'd id prefix almost certainly
 * wasn't meant as a literal tag). Any string not starting with "pool:" or
 * "search:" is always BUNNY_CLI_SPEC_TAGS and always returns true;
 * *out_id is untouched for that case. */
bool bunny_cli_parse_download_spec(const char *spec, bunny_cli_spec_kind_t *out_kind, int64_t *out_id);

/* Every bunny_cli_cmd_* function returns a process exit code (0 success,
 * non-zero failure) and does its own logging via log.h -- main.c just
 * dispatches to one of these and returns what it returns. None of them
 * touch the handshake directly; main.c resolves `ctx`/the download folder
 * once up front and passes them in. --stats is the only command that
 * stays standalone-only (see its own doc comment below) -- every other
 * command works in both modes. */

/* Live e621/Inkbunny query + cache (bunny_core_preview_search locally, or
 * POST /search/preview over REST), dumping the resulting posts as a JSON
 * array to stdout -- byte-for-byte the server's own JSON shape either way
 * (json_helpers.h's own doc comment), so networked mode just forwards the
 * response body instead of re-serializing it. */
int bunny_cli_cmd_search(bunny_cli_context_t *ctx, bunny_db_site_t site, const char *query, int page);

/* A pool's own metadata (e621 only) as a JSON object to stdout. */
int bunny_cli_cmd_pool(bunny_cli_context_t *ctx, int64_t pool_id);

/* Row counts per database table, colored human-readable summary to stdout
 * (not JSON -- this one's for a human, not a pipe). Same shape as
 * `bunny_server --db-stats`. Standalone only -- the server has no REST
 * endpoint exposing table row counts/integrity (its own /health only
 * smoke-tests the HTTPS listener itself, docs/architecture.md's "C server
 * (M5)" section). */
int bunny_cli_cmd_stats(bunny_cli_context_t *ctx);

/* Drains the whole download queue (ctx->core, both modes -- see
 * bunny_cli_context_t's own doc comment) using up to `jobs` concurrent
 * worker threads (clamped to [1, 8], matching bunny_core's own fixed
 * download-slot table) -- each claims the next still-queued row, resolves
 * the post's own metadata (bunny_core_post_get_by_id in standalone mode,
 * GET /posts/{id} over REST in networked mode -- the local queue db never
 * stores post data itself, only the queue rows), resolves its real
 * destination (destination.h, mirroring the app's own scheme exactly),
 * downloads it via bunny_core_download_start/_poll/_release, and updates
 * the row's status. `download_folder` is the app's own configured
 * destination (from the handshake payload) -- NULL fails immediately with
 * a clear error rather than guessing a location. In networked mode with no
 * local queue db available (ctx->core is NULL -- an app build from before
 * the handshake reported one), fails with a clear error instead of
 * guessing.
 *
 * `specs`/`spec_count` (optional -- 0/NULL for the plain "just drain
 * what's already queued" behavior above) are resolved and queued *before*
 * draining starts, so they're included in the same drain pass -- each one
 * is one of (bunny_cli_parse_download_spec's own doc comment):
 * - "pool:<id>" -- an e621 pool: its real name is fetched
 *   (bunny_core_fetch_pool/GET /pools/{id}), then every one of its posts is
 *   found via a live, fully-paginated tag search for that literal string
 *   (e621 supports "pool:<id>" as a search tag -- there is no separate
 *   "list a pool's posts" API/bunny_core call) and queued as a pool
 *   download (sequential 1-indexed page numbers in fetch order, same
 *   convention PostGridScreen._massDownload/_poolPageByPostId uses on the
 *   Dart side) so destination.h files them under a pool-named folder.
 * - "search:<id>" -- one of the app's own saved searches: its site/query/
 *   label are looked up (bunny_core_search_list/GET /searches, by id --
 *   there is no single-search GET), then every post *already cached* for
 *   it is read back (bunny_core_search_list_posts/GET
 *   /searches/{id}/posts, fully paginated -- a saved search's own posts
 *   are never re-fetched live here, same as SearchesScreen
 *   ._downloadSelectedSearches's own "download selected searches" action).
 *   If that search's own query itself starts with "pool:" (a pool-tracking
 *   search, `create_pool_search_dialog.dart`'s own convention), this
 *   queues a pool download too, using the search's own label as the pool
 *   name (not a fresh fetch_pool call) -- exactly matching
 *   _downloadSelectedSearches's own `search.isPool` branch.
 * - anything else -- a plain, live, fully-paginated tag search under
 *   `spec_site` (not per-spec -- one site applies to every plain-tag spec
 *   in this call; `--site` on the command line, e621 if omitted).
 *
 * Every live/cached fetch above pages until an empty page comes back, no
 * cap -- same exhaustive "download the entire thing" behavior
 * PostGridScreen._selectEntireSearch/SearchesScreen
 * ._downloadSelectedSearches already use, not a capped preview. A post
 * already active (queued/downloading) in the queue, or resolved by more
 * than one spec in this same call, is only ever added once -- same dedup
 * reasoning as DownloadQueueService._enqueueAll's own activeIds set. A
 * spec that fails outright (a bad pool/search id, a network error) is
 * reported and skipped -- it never aborts the other specs or the drain
 * that follows. */
int bunny_cli_cmd_download(bunny_cli_context_t *ctx, const char *download_folder, int jobs, bunny_db_site_t spec_site, const char **specs, size_t spec_count);

/* Queues a favorite-add for `post_id` (stars is Inkbunny's 1-3 tier, or -1
 * for e621's plain favorite/any Inkbunny default) and immediately drains
 * the action queue (bunny_core_process_queue locally, or POST /queue/process
 * over REST) -- a CLI invocation is one-shot, so there's no reason to leave
 * this for later the way the app's own background timer does. Reports
 * success/failure clearly; an Inkbunny post with no Inkbunny account
 * configured, or any post that doesn't exist, fails here with the real
 * site/queue error. */
int bunny_cli_cmd_favorite_add(bunny_cli_context_t *ctx, int64_t post_id, int stars);

/* Same shape as bunny_cli_cmd_favorite_add, for removing a favorite. */
int bunny_cli_cmd_favorite_remove(bunny_cli_context_t *ctx, int64_t post_id);

/* Queues a vote (score must be -1, 0, or 1) and drains the action queue --
 * same immediate-drain reasoning as bunny_cli_cmd_favorite_add. Inkbunny
 * has no vote API at all; queuing one against an Inkbunny post is accepted
 * but always fails once processed, same as bunny_core_queue_vote's own doc
 * comment describes. */
int bunny_cli_cmd_vote(bunny_cli_context_t *ctx, int64_t post_id, int score);

/* Syncs saved searches. Standalone: `search_id == 0` runs
 * bunny_core_sync_due_searches (every search whose interval has elapsed),
 * otherwise forces exactly that one search via bunny_core_sync_search
 * regardless of due-ness -- runs synchronously here and then prints the
 * resulting bunny_core_sync_stats_t as a colored human-readable summary
 * (not JSON -- for a human, not a pipe, matching --stats). Networked: the
 * server's own sync is an async job (POST /sync or POST
 * /searches/{id}/sync, which only enqueue it onto the server's own task
 * queue and return immediately -- the server runs it in the background on
 * its own, the actual progress/results are only ever visible via GET
 * /sync/status or the app's own UI, not this command), so this just
 * triggers it and reports whether the server actually accepted the
 * request, rather than waiting for or printing stats it was never asked
 * to go fetch. */
int bunny_cli_cmd_sync(bunny_cli_context_t *ctx, int64_t search_id);

/* Dumps a site's tag blacklist as a plain JSON array of strings to stdout. */
int bunny_cli_cmd_blacklist_list(bunny_cli_context_t *ctx, bunny_db_site_t site);

/* Adds/removes one blacklist rule for `site`. `tag` is validated under that
 * site's own tag-query grammar before being stored -- an invalid rule fails
 * with a clear error rather than being stored unusable. */
int bunny_cli_cmd_blacklist_add(bunny_cli_context_t *ctx, bunny_db_site_t site, const char *tag);
int bunny_cli_cmd_blacklist_remove(bunny_cli_context_t *ctx, bunny_db_site_t site, const char *tag);

/* Dumps the whole download queue (ctx->core, both modes -- every row, any
 * status) as a JSON array to stdout -- debugging/scripting, not meant for
 * a human to read directly. In networked mode with no local queue db
 * available (ctx->core is NULL), fails with a clear error instead of
 * guessing. */
int bunny_cli_cmd_queue_list(bunny_cli_context_t *ctx);

#ifdef __cplusplus
}
#endif

#endif /* BUNNY_CLI_COMMANDS_H */
