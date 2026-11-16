#ifndef BUNNY_CLI_COMMANDS_H
#define BUNNY_CLI_COMMANDS_H

#include "handshake.h" /* bunny_cli_mode_t -- reused as-is rather than a second mode enum */
#include "rest_client.h"

#include <bunny_core/core.h>
#include <bunny_db/types.h>

#ifdef __cplusplus
extern "C" {
#endif

/* What every bunny_cli_cmd_* below actually operates against -- resolved
 * once in main.c right after the handshake (a real bunny_core_t* for
 * BUNNY_CLI_MODE_STANDALONE, a bunny_cli_rest_client_t* for
 * BUNNY_CLI_MODE_NETWORKED) and passed down instead of each command
 * re-deciding which mode it's in from scratch. `mode` is never
 * BUNNY_CLI_MODE_NONE here -- main.c already exits before building a
 * context in that case. Only the field matching `mode` is non-NULL. */
typedef struct
{
    bunny_cli_mode_t mode;
    bunny_core_t *core;            /* BUNNY_CLI_MODE_STANDALONE only */
    bunny_cli_rest_client_t *rest; /* BUNNY_CLI_MODE_NETWORKED only */
} bunny_cli_context_t;

/* Every bunny_cli_cmd_* function returns a process exit code (0 success,
 * non-zero failure) and does its own logging via log.h -- main.c just
 * dispatches to one of these and returns what it returns. None of them
 * touch the handshake directly; main.c resolves `ctx`/the download folder
 * once up front and passes them in. A command with no networked
 * implementation yet (--download, --sync, --queue-list, --stats -- see
 * cli/README.md's "Current limitation" section for why each one doesn't
 * fit the REST surface the same way) reports a clear error in
 * BUNNY_CLI_MODE_NETWORKED rather than guessing. */

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

/* Drains the whole download queue using up to `jobs` concurrent worker
 * threads (clamped to [1, 8], matching bunny_core's own fixed download-slot
 * table) -- each claims the next still-queued row, resolves its real
 * destination (destination.h, mirroring the app's own scheme exactly),
 * downloads it via bunny_core_download_start/_poll/_release, and updates
 * the row's status. `download_folder` is the app's own configured
 * destination (from the handshake payload) -- NULL fails immediately with
 * a clear error rather than guessing a location. Standalone only -- the
 * download queue is purely client-side (docs/architecture.md's "Downloads
 * are client-side" section); a networked version needs its own local
 * queue database (the exact thing HttpBunnyRepository's own
 * _downloadQueueNative does on the Dart side), which the handshake doesn't
 * hand over yet. */
int bunny_cli_cmd_download(bunny_cli_context_t *ctx, const char *download_folder, int jobs);

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

/* Syncs saved searches: `search_id == 0` runs bunny_core_sync_due_searches
 * (every search whose interval has elapsed), otherwise forces exactly that
 * one search via bunny_core_sync_search regardless of due-ness. Prints the
 * resulting bunny_core_sync_stats_t as a colored human-readable summary
 * (not JSON -- for a human, not a pipe, matching --stats). Standalone only
 * -- the server's own POST /sync is an async job (enqueued onto its task
 * queue, progress read back via GET /sync/status), a different shape from
 * this command's synchronous "run it now, print the stats" contract; see
 * cli/README.md. */
int bunny_cli_cmd_sync(bunny_cli_context_t *ctx, int64_t search_id);

/* Dumps a site's tag blacklist as a plain JSON array of strings to stdout. */
int bunny_cli_cmd_blacklist_list(bunny_cli_context_t *ctx, bunny_db_site_t site);

/* Adds/removes one blacklist rule for `site`. `tag` is validated under that
 * site's own tag-query grammar before being stored -- an invalid rule fails
 * with a clear error rather than being stored unusable. */
int bunny_cli_cmd_blacklist_add(bunny_cli_context_t *ctx, bunny_db_site_t site, const char *tag);
int bunny_cli_cmd_blacklist_remove(bunny_cli_context_t *ctx, bunny_db_site_t site, const char *tag);

/* Dumps the whole download queue (every row, any status) as a JSON array to
 * stdout -- debugging/scripting, not meant for a human to read directly.
 * Standalone only -- same "purely client-side, no REST endpoint for it"
 * reasoning as bunny_cli_cmd_download. */
int bunny_cli_cmd_queue_list(bunny_cli_context_t *ctx);

#ifdef __cplusplus
}
#endif

#endif /* BUNNY_CLI_COMMANDS_H */
