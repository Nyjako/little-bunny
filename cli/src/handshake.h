#ifndef BUNNY_CLI_HANDSHAKE_H
#define BUNNY_CLI_HANDSHAKE_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* bunny_cli never reads the app's database/connection info from a flag or a
 * file -- it asks the real app for it, briefly, over a pipe only the two of
 * them share (see the top-level plan's "App handshake design" section for
 * the full protocol and the reasoning behind it). This module is the C side
 * of that protocol: spawning the app with "--cli-handshake", writing the
 * one line it expects on stdin, and reading the one JSON line it writes
 * back before it exits. */

typedef enum
{
    BUNNY_CLI_HANDSHAKE_OK,             /* out is populated */
    BUNNY_CLI_HANDSHAKE_LOCKED,         /* the app's own app-lock rejected the supplied secret */
    BUNNY_CLI_HANDSHAKE_APP_NOT_FOUND,  /* app_exe_path doesn't exist / isn't executable */
    BUNNY_CLI_HANDSHAKE_SPAWN_FAILED,   /* pipe()/fork()/exec() or CreateProcess() itself failed */
    BUNNY_CLI_HANDSHAKE_PROTOCOL_ERROR, /* the app exited without ever writing one valid JSON line */
} bunny_cli_handshake_result_t;

typedef enum
{
    BUNNY_CLI_MODE_NONE, /* no repository configured yet in the app */
    BUNNY_CLI_MODE_STANDALONE,
    BUNNY_CLI_MODE_NETWORKED,
} bunny_cli_mode_t;

/* Only the fields matching `mode` are non-NULL (download_destination_folder
 * is the one exception -- see its own comment below); every string here is
 * owned by this struct -- free with bunny_cli_handshake_payload_free. */
typedef struct
{
    bunny_cli_mode_t mode;
    char *db_path;          /* BUNNY_CLI_MODE_STANDALONE only */
    char *user_agent;       /* BUNNY_CLI_MODE_STANDALONE only */
    char *server_base_url;  /* BUNNY_CLI_MODE_NETWORKED only */
    char *bearer_token;     /* BUNNY_CLI_MODE_NETWORKED only */
    char *cert_fingerprint; /* BUNNY_CLI_MODE_NETWORKED only */
    /* BUNNY_CLI_MODE_NETWORKED only -- the app's own small local db used
     * purely for download-queue bookkeeping in networked mode (the server
     * never proxies binary downloads or stores this queue itself, see
     * docs/architecture.md's "Downloads are client-side" section), the
     * exact same db HttpBunnyRepository's own _ensureDownloadQueueNative
     * opens on the Dart side. `--download`/`--queue-list` need this to
     * continue/inspect the queue without the app running; every other
     * networked command only needs the REST client. May be NULL even in
     * networked mode (an app build from before this field existed) --
     * callers must check, not assume it's always set. */
    char *download_queue_db_path;
    char *download_queue_user_agent;
    /* Present for both BUNNY_CLI_MODE_STANDALONE and BUNNY_CLI_MODE_NETWORKED
     * (never for BUNNY_CLI_MODE_NONE) -- the app's DownloadSettingsStore
     * setting, a separate concern from the repository config above, but one
     * `--download` needs just as much to write files to the exact folder
     * the app itself would (see cli/src/destination.c). May still be NULL
     * even then, in the rare case the app's own OS-Downloads-directory
     * fallback also failed -- callers must check for that, not assume it's
     * always set alongside a real mode. */
    char *download_destination_folder;
    /* Present for both modes (never BUNNY_CLI_MODE_NONE), default false if
     * the app build doesn't report them -- the app's own global
     * DownloadSettingsStore toggles ("auto favorite/upvote on download"),
     * a separate concern from a saved search's own per-search auto-
     * favorite/upvote (BunnySearch.autoFavorite/autoUpvote, M10.1/M14.2,
     * applied at sync time, not download time -- unrelated to these).
     * bunny_cli_cmd_download applies these to every post it downloads,
     * same as DownloadQueueService's own worker does for the app itself. */
    bool auto_favorite_on_download;
    bool auto_upvote_on_download;
} bunny_cli_handshake_payload_t;

/* Safe to call on a zero-initialized or already-freed payload. Zeroes
 * *payload afterward. */
void bunny_cli_handshake_payload_free(bunny_cli_handshake_payload_t *payload);

/* Spawns `app_exe_path` with the single argument "--cli-handshake" (piped
 * stdin/stdout; the child's stderr is inherited, so a crash there is still
 * visible to this process's own stderr). Writes `supplied_secret` (NULL
 * treated the same as "", i.e. "no secret supplied") followed by a newline
 * to the child's stdin, closes that pipe, reads exactly one line back from
 * its stdout, and waits for the child to actually exit (never leaves a
 * zombie/orphan behind) before returning. Pure plumbing -- never reads from
 * the real terminal or retries anything itself; that's main.c's job. */
bunny_cli_handshake_result_t bunny_cli_handshake_run(const char *app_exe_path, const char *supplied_secret, bunny_cli_handshake_payload_t *out);

/* Resolves the path this CLI expects the app's own executable to sit at --
 * right next to this process's own binary ("little_bunny"/"little_bunny.exe").
 * Returns a newly allocated string the caller must free(), or NULL if this
 * process's own executable path couldn't even be resolved (a different
 * failure from the app simply not existing there -- bunny_cli_handshake_run
 * reports that case as BUNNY_CLI_HANDSHAKE_APP_NOT_FOUND instead). */
char *bunny_cli_find_app_executable(void);

/* Human-readable string for every bunny_cli_handshake_result_t value --
 * never NULL, same convention as bunny_core_result_to_string. */
const char *bunny_cli_handshake_result_to_string(bunny_cli_handshake_result_t result);

#ifdef __cplusplus
}
#endif

#endif /* BUNNY_CLI_HANDSHAKE_H */
