#ifndef BUNNY_CLI_COMMANDS_H
#define BUNNY_CLI_COMMANDS_H

#include <bunny_core/core.h>
#include <bunny_db/types.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Every bunny_cli_cmd_* function returns a process exit code (0 success,
 * non-zero failure) and does its own logging via log.h -- main.c just
 * dispatches to one of these and returns what it returns. None of them
 * touch the handshake directly; main.c resolves `core`/the download folder
 * once up front and passes them in. */

/* Live e621/Inkbunny query + cache (bunny_core_preview_search), dumping the
 * resulting posts as a JSON array to stdout. */
int bunny_cli_cmd_search(bunny_core_t *core, bunny_db_site_t site, const char *query, int page);

/* A pool's own metadata (e621 only) as a JSON object to stdout. */
int bunny_cli_cmd_pool(bunny_core_t *core, int64_t pool_id);

/* Row counts per database table, colored human-readable summary to stdout
 * (not JSON -- this one's for a human, not a pipe). Same shape as
 * `bunny_server --db-stats`. */
int bunny_cli_cmd_stats(bunny_core_t *core);

/* Drains the whole download queue using up to `jobs` concurrent worker
 * threads (clamped to [1, 8], matching bunny_core's own fixed download-slot
 * table) -- each claims the next still-queued row, resolves its real
 * destination (destination.h, mirroring the app's own scheme exactly),
 * downloads it via bunny_core_download_start/_poll/_release, and updates
 * the row's status. `download_folder` is the app's own configured
 * destination (from the handshake payload) -- NULL fails immediately with
 * a clear error rather than guessing a location. */
int bunny_cli_cmd_download(bunny_core_t *core, const char *download_folder, int jobs);

/* Queues a favorite-add for `post_id` (stars is Inkbunny's 1-3 tier, or -1
 * for e621's plain favorite/any Inkbunny default) and immediately drains
 * the action queue (bunny_core_process_queue) -- a CLI invocation is
 * one-shot, so there's no reason to leave this for later the way the app's
 * own background timer does. Reports success/failure clearly; an Inkbunny
 * post with no Inkbunny account configured, or any post that doesn't
 * exist, fails here with the real site/queue error. */
int bunny_cli_cmd_favorite_add(bunny_core_t *core, int64_t post_id, int stars);

/* Same shape as bunny_cli_cmd_favorite_add, for removing a favorite. */
int bunny_cli_cmd_favorite_remove(bunny_core_t *core, int64_t post_id);

/* Queues a vote (score must be -1, 0, or 1) and drains the action queue --
 * same immediate-drain reasoning as bunny_cli_cmd_favorite_add. Inkbunny
 * has no vote API at all; queuing one against an Inkbunny post is accepted
 * but always fails once processed, same as bunny_core_queue_vote's own doc
 * comment describes. */
int bunny_cli_cmd_vote(bunny_core_t *core, int64_t post_id, int score);

#ifdef __cplusplus
}
#endif

#endif /* BUNNY_CLI_COMMANDS_H */
