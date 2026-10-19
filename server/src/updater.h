#ifndef BUNNY_SERVER_UPDATER_H
#define BUNNY_SERVER_UPDATER_H

#include <bunny_common/http.h>

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* BUNNY_BUILD_NUMBER is injected by CMake (see the top-level CMakeLists.txt
 * option's own comment) -- 0 for a local/dev build, the real release.yml run
 * number for anything actually shipped. Guard it so this header still
 * compiles (e.g. for IDE tooling) outside the normal CMake build. */
#ifndef BUNNY_BUILD_NUMBER
#define BUNNY_BUILD_NUMBER 0
#endif

typedef struct
{
    bool update_available;
    int latest_build_number;
    char *tag_name;        /* owned; e.g. "build-42" */
    char *download_url;    /* owned; NULL if update_available is false, or
                             * the release has no asset matching
                             * asset_name_suffix */
    char *sha256_sums_url; /* owned; the release's "SHA256SUMS.txt" asset's
                             * download URL, NULL if the release has none
                             * (e.g. a release built before this existed) */
    char *release_notes;   /* owned; may be NULL (empty release body) */
} bunny_updater_check_result_t;

void bunny_updater_check_result_free(bunny_updater_check_result_t *result);

/* Parses a GitHub Releases API "get the latest release" response body
 * (https://docs.github.com/en/rest/releases/releases#get-the-latest-release)
 * and fills out_result, comparing the release's "build-<N>" tag against
 * current_build_number. asset_name_suffix selects which of the release's
 * assets to report the download URL for (e.g. "linux-x64.tar.gz" matches
 * "bunny-server-linux-x64.tar.gz") -- out_result->download_url is left NULL
 * if no asset matches, even when update_available is true. Pure/offline --
 * no network, safe to unit test directly with fixture JSON. */
bool bunny_updater_parse_latest_release(const char *json, size_t json_len, int current_build_number, const char *asset_name_suffix, bunny_updater_check_result_t *out_result);

/* Does the actual GET against GitHub's API (repo_owner/repo_name, e.g.
 * "Nyjako"/"little-bunny") and delegates to
 * bunny_updater_parse_latest_release. user_agent is required -- GitHub's API
 * rejects requests with no User-Agent header. */
bunny_http_result_t bunny_updater_check(const bunny_http_transport_t *transport, const char *repo_owner, const char *repo_name, const char *user_agent, const char *asset_name_suffix, int current_build_number, bunny_updater_check_result_t *out_result);

/* Downloads url's body verbatim to dest_path (overwritten if it already
 * exists, parent directory must already exist). Binary-safe (uses
 * body_len, not strlen) -- works for the .tar.gz asset itself, not just
 * JSON. */
bunny_http_result_t bunny_updater_download_file(const bunny_http_transport_t *transport, const char *url, const char *user_agent, const char *dest_path);

/* Downloads url's body as a NUL-terminated string (owned, caller frees) --
 * for small text assets like SHA256SUMS.txt, never the multi-megabyte
 * archive itself (see bunny_updater_download_file for that). NULL on any
 * failure (network error or non-200 status). */
char *bunny_updater_download_text(const bunny_http_transport_t *transport, const char *url, const char *user_agent);

/* Hashes the file at path with SHA-256, writing the lowercase hex digest
 * (64 chars + NUL) into out_hex. */
bool bunny_updater_sha256_hex(const char *path, char out_hex[65]);

/* Finds filename's expected digest in sums_text (the contents of a
 * `sha256sum`-format file: lines of "<hex>  <filename>", optionally with a
 * "*" before the filename for binary mode) and writes it (lowercase,
 * 64 chars + NUL) into out_hex. False if filename isn't listed. */
bool bunny_updater_find_sha256(const char *sums_text, const char *filename, char out_hex[65]);

/* Extracts a .tar.gz archive into dest_dir (created if missing) by shelling
 * out to the system `tar` binary via fork/exec (never through a shell --
 * no injection surface, even though every argument here is internally
 * constructed, never user input). Linux-only; this whole module is never
 * compiled into the Windows server build (see server/CMakeLists.txt) since
 * there's no self-update story for a Windows service yet. */
bool bunny_updater_extract_tar_gz(const char *tar_gz_path, const char *dest_dir);

/* The scheduler's own entry point (server/src/scheduler.c) -- checks
 * data_dir/.last_update_check's mtime, no-ops if checked recently
 * (BUNNY_UPDATE_CHECK_INTERVAL_SEC), otherwise runs the full check-download-
 * extract-verify-stage sequence into data_dir/update-staging/ and, on
 * success, writes data_dir/update-ready (the marker
 * deploy/bunny-server-update-apply.sh looks for) before returning. Never
 * restarts the process itself -- the caller (scheduler_loop) decides when a
 * clean exit(0) is safe (not mid-sync), matching how systemd's
 * Restart=always is the actual restart mechanism, not this function. */
void bunny_updater_scheduler_tick(const bunny_http_transport_t *transport, const char *data_dir, const char *user_agent, bool *out_restart_requested);

#ifdef __cplusplus
}
#endif

#endif /* BUNNY_SERVER_UPDATER_H */
