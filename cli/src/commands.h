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

#ifdef __cplusplus
}
#endif

#endif /* BUNNY_CLI_COMMANDS_H */
