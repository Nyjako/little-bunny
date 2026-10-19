#include "updater.h"

#include <cJSON.h>
#include <goblin/appdirs.h>
#include <goblin/cstr.h>
#include <goblin/fileio.h>
#include <openssl/evp.h>

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>

#ifndef _WIN32
#include <sys/wait.h>
#include <unistd.h>
#endif

#include "log.h"

#define BUNNY_UPDATE_CHECK_INTERVAL_SEC (24 * 60 * 60)
#define BUNNY_RELEASE_TAG_PREFIX "build-"
#define BUNNY_SHA256_SUMS_ASSET_NAME "SHA256SUMS.txt"

void bunny_updater_check_result_free(bunny_updater_check_result_t *result)
{
    if (!result) {
        return;
    }
    free(result->tag_name);
    free(result->download_url);
    free(result->sha256_sums_url);
    free(result->release_notes);
    memset(result, 0, sizeof(*result));
}

bool bunny_updater_parse_latest_release(const char *json, size_t json_len, int current_build_number, const char *asset_name_suffix, bunny_updater_check_result_t *out_result)
{
    if (!json || !out_result) {
        return false;
    }
    memset(out_result, 0, sizeof(*out_result));

    cJSON *root = cJSON_ParseWithLength(json, json_len);
    if (!root) {
        return false;
    }

    cJSON *tag_item = cJSON_GetObjectItemCaseSensitive(root, "tag_name");
    if (!cJSON_IsString(tag_item) || !tag_item->valuestring) {
        cJSON_Delete(root);
        return false;
    }

    const char *tag = tag_item->valuestring;
    const char *prefix = BUNNY_RELEASE_TAG_PREFIX;
    if (strncmp(tag, prefix, strlen(prefix)) != 0) {
        /* Not one of this project's own release tags (e.g. a hand-made tag
         * on the repo) -- nothing sensible to compare, treat as no update. */
        cJSON_Delete(root);
        return true;
    }

    int latest_build_number = atoi(tag + strlen(prefix));
    out_result->tag_name = goblin_copy_cstr(tag);
    out_result->latest_build_number = latest_build_number;
    /* current_build_number is 0 for a local/dev build (CMakeLists.txt
     * defaults BUNNY_BUILD_NUMBER to "0") -- never treated as outdated
     * relative to any real release, same sentinel convention as the
     * Flutter app's own appBuildNumber (app_version.dart). */
    out_result->update_available = current_build_number > 0 && latest_build_number > current_build_number;

    cJSON *body_item = cJSON_GetObjectItemCaseSensitive(root, "body");
    if (cJSON_IsString(body_item) && body_item->valuestring && body_item->valuestring[0] != '\0') {
        out_result->release_notes = goblin_copy_cstr(body_item->valuestring);
    }

    if (out_result->update_available && asset_name_suffix) {
        cJSON *assets = cJSON_GetObjectItemCaseSensitive(root, "assets");
        int asset_count = cJSON_GetArraySize(assets);
        size_t suffix_len = strlen(asset_name_suffix);
        for (int i = 0; i < asset_count; i++) {
            cJSON *asset = cJSON_GetArrayItem(assets, i);
            cJSON *name_item = cJSON_GetObjectItemCaseSensitive(asset, "name");
            if (!cJSON_IsString(name_item) || !name_item->valuestring) {
                continue;
            }
            cJSON *url_item = cJSON_GetObjectItemCaseSensitive(asset, "browser_download_url");
            if (!cJSON_IsString(url_item) || !url_item->valuestring) {
                continue;
            }
            size_t name_len = strlen(name_item->valuestring);
            if (name_len >= suffix_len && strcmp(name_item->valuestring + (name_len - suffix_len), asset_name_suffix) == 0) {
                out_result->download_url = goblin_copy_cstr(url_item->valuestring);
            } else if (strcmp(name_item->valuestring, BUNNY_SHA256_SUMS_ASSET_NAME) == 0) {
                out_result->sha256_sums_url = goblin_copy_cstr(url_item->valuestring);
            }
        }
    }

    cJSON_Delete(root);
    return true;
}

bunny_http_result_t bunny_updater_check(const bunny_http_transport_t *transport, const char *repo_owner, const char *repo_name, const char *user_agent, const char *asset_name_suffix, int current_build_number, bunny_updater_check_result_t *out_result)
{
    if (!transport || !repo_owner || !repo_name || !user_agent || !out_result) {
        return BUNNY_HTTP_ERR_INVALID_ARG;
    }

    char url[512];
    snprintf(url, sizeof(url), "https://api.github.com/repos/%s/%s/releases/latest", repo_owner, repo_name);

    /* GitHub's API rejects requests with no User-Agent, and strongly
     * recommends (if not outright requiring, depending on endpoint) the
     * versioned Accept header below. */
    bunny_http_header_t headers[] = {
        {"User-Agent", user_agent},
        {"Accept", "application/vnd.github+json"},
    };
    bunny_http_request_t request = {
        .method = BUNNY_HTTP_GET,
        .url = url,
        .headers = headers,
        .header_count = sizeof(headers) / sizeof(headers[0]),
        .body = NULL,
        .body_len = 0,
    };

    bunny_http_response_t response;
    bunny_http_result_t result = bunny_http_send(transport, &request, &response);
    if (result != BUNNY_HTTP_OK) {
        return result;
    }
    if (response.status != 200 || !bunny_updater_parse_latest_release(response.body, response.body_len, current_build_number, asset_name_suffix, out_result)) {
        bunny_http_response_free(&response);
        return BUNNY_HTTP_ERR_NETWORK;
    }
    bunny_http_response_free(&response);
    return BUNNY_HTTP_OK;
}

bunny_http_result_t bunny_updater_download_file(const bunny_http_transport_t *transport, const char *url, const char *user_agent, const char *dest_path)
{
    if (!transport || !url || !user_agent || !dest_path) {
        return BUNNY_HTTP_ERR_INVALID_ARG;
    }

    bunny_http_header_t headers[] = {{"User-Agent", user_agent}};
    bunny_http_request_t request = {
        .method = BUNNY_HTTP_GET,
        .url = url,
        .headers = headers,
        .header_count = 1,
        .body = NULL,
        .body_len = 0,
    };

    bunny_http_response_t response;
    bunny_http_result_t result = bunny_http_send(transport, &request, &response);
    if (result != BUNNY_HTTP_OK) {
        return result;
    }
    if (response.status != 200) {
        bunny_http_response_free(&response);
        return BUNNY_HTTP_ERR_NETWORK;
    }

    FILE *f = fopen(dest_path, "wb");
    if (!f) {
        bunny_http_response_free(&response);
        return BUNNY_HTTP_ERR_NETWORK;
    }
    /* Captured before bunny_http_response_free, which zeroes response.body_len
     * as part of its own cleanup -- comparing against it after freeing would
     * always see 0, making this falsely report failure on every successful
     * download. */
    size_t expected_len = response.body_len;
    size_t written = fwrite(response.body, 1, expected_len, f);
    fclose(f);
    bunny_http_response_free(&response);
    return written == expected_len ? BUNNY_HTTP_OK : BUNNY_HTTP_ERR_NETWORK;
}

char *bunny_updater_download_text(const bunny_http_transport_t *transport, const char *url, const char *user_agent)
{
    if (!transport || !url || !user_agent) {
        return NULL;
    }

    bunny_http_header_t headers[] = {{"User-Agent", user_agent}};
    bunny_http_request_t request = {
        .method = BUNNY_HTTP_GET,
        .url = url,
        .headers = headers,
        .header_count = 1,
        .body = NULL,
        .body_len = 0,
    };

    bunny_http_response_t response;
    if (bunny_http_send(transport, &request, &response) != BUNNY_HTTP_OK) {
        return NULL;
    }
    if (response.status != 200) {
        bunny_http_response_free(&response);
        return NULL;
    }

    char *text = malloc(response.body_len + 1);
    if (!text) {
        bunny_http_response_free(&response);
        return NULL;
    }
    memcpy(text, response.body, response.body_len);
    text[response.body_len] = '\0';
    bunny_http_response_free(&response);
    return text;
}

bool bunny_updater_sha256_hex(const char *path, char out_hex[65])
{
    if (!path || !out_hex) {
        return false;
    }

    FILE *f = fopen(path, "rb");
    if (!f) {
        return false;
    }

    EVP_MD_CTX *ctx = EVP_MD_CTX_new();
    bool ok = ctx && EVP_DigestInit_ex(ctx, EVP_sha256(), NULL) == 1;

    unsigned char buf[65536];
    size_t n;
    while (ok && (n = fread(buf, 1, sizeof(buf), f)) > 0) {
        ok = EVP_DigestUpdate(ctx, buf, n) == 1;
    }
    ok = ok && !ferror(f);

    unsigned char digest[EVP_MAX_MD_SIZE];
    unsigned int digest_len = 0;
    ok = ok && EVP_DigestFinal_ex(ctx, digest, &digest_len) == 1 && digest_len == 32;

    if (ctx) {
        EVP_MD_CTX_free(ctx);
    }
    fclose(f);

    if (!ok) {
        return false;
    }
    for (unsigned int i = 0; i < digest_len; i++) {
        snprintf(out_hex + i * 2, 3, "%02x", digest[i]);
    }
    return true;
}

bool bunny_updater_find_sha256(const char *sums_text, const char *filename, char out_hex[65])
{
    if (!sums_text || !filename || !out_hex) {
        return false;
    }

    size_t filename_len = strlen(filename);
    const char *line = sums_text;
    while (*line) {
        const char *line_end = strchr(line, '\n');
        size_t line_len = line_end ? (size_t)(line_end - line) : strlen(line);

        /* Standard `sha256sum` output: a 64-char lowercase hex digest, then
         * whitespace, then the filename (optionally prefixed with '*' for
         * binary mode). */
        if (line_len > 64 && isspace((unsigned char)line[64])) {
            const char *name_start = line + 64;
            while (*name_start == ' ' || *name_start == '*') {
                name_start++;
            }
            size_t name_len = (size_t)(line_len - (name_start - line));
            if (name_len == filename_len && strncmp(name_start, filename, filename_len) == 0) {
                memcpy(out_hex, line, 64);
                out_hex[64] = '\0';
                return true;
            }
        }

        if (!line_end) {
            break;
        }
        line = line_end + 1;
    }
    return false;
}

#ifdef _WIN32
bool bunny_updater_extract_tar_gz(const char *tar_gz_path, const char *dest_dir)
{
    (void)tar_gz_path;
    (void)dest_dir;
    return false; /* No self-update story for the Windows server yet. */
}
#else
bool bunny_updater_extract_tar_gz(const char *tar_gz_path, const char *dest_dir)
{
    if (!tar_gz_path || !dest_dir || !goblin_mkdir(dest_dir)) {
        return false;
    }

    pid_t pid = fork();
    if (pid < 0) {
        return false;
    }
    if (pid == 0) {
        /* Child: exec, never returns on success. execlp (not system()) --
         * no shell involved, so there's no injection surface even though
         * every argument here is internally constructed, never user input. */
        execlp("tar", "tar", "-xzf", tar_gz_path, "-C", dest_dir, (char *)NULL);
        _exit(127); /* execlp failed (tar not on PATH, etc.) */
    }

    int status = 0;
    if (waitpid(pid, &status, 0) != pid) {
        return false;
    }
    return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}
#endif

/* data_dir/.last_update_check's mtime is the self-throttle, same pattern as
 * scheduler.c's own backup_due_and_prune. A plain empty marker file (not a
 * database row) -- this is operational bookkeeping, not user data. */
static bool check_due(const char *marker_path)
{
    struct stat st;
    if (stat(marker_path, &st) != 0) {
        return true; /* never checked before */
    }
    return (time(NULL) - st.st_mtime) >= BUNNY_UPDATE_CHECK_INTERVAL_SEC;
}

static void touch_marker(const char *path)
{
    FILE *f = fopen(path, "w");
    if (f) {
        fclose(f);
    }
}

void bunny_updater_scheduler_tick(const bunny_http_transport_t *transport, const char *data_dir, const char *user_agent, bool *out_restart_requested)
{
    *out_restart_requested = false;
    if (!data_dir) {
        return;
    }

    char *marker_path = goblin_appdir_join(data_dir, ".last_update_check");
    if (!marker_path) {
        return;
    }
    if (!check_due(marker_path)) {
        free(marker_path);
        return;
    }
    touch_marker(marker_path);
    free(marker_path);

    bunny_updater_check_result_t check;
    bunny_http_result_t result = bunny_updater_check(transport, "Nyjako", "little-bunny", user_agent, "linux-x64.tar.gz", BUNNY_BUILD_NUMBER, &check);
    if (result != BUNNY_HTTP_OK) {
        server_log("ERROR", "updater: failed to check for a new release");
        return;
    }
    if (!check.update_available) {
        bunny_updater_check_result_free(&check);
        return;
    }
    if (!check.download_url) {
        server_log("ERROR", "updater: release %s has no linux-x64.tar.gz asset", check.tag_name);
        bunny_updater_check_result_free(&check);
        return;
    }
    server_log("INFO", "updater: %s available (currently running build %d), downloading", check.tag_name, BUNNY_BUILD_NUMBER);

    char *staging_dir = goblin_appdir_join(data_dir, "update-staging");
    if (!staging_dir || !goblin_mkdir(staging_dir)) {
        server_log("ERROR", "updater: couldn't create staging directory");
        bunny_updater_check_result_free(&check);
        free(staging_dir);
        return;
    }

    char *archive_path = goblin_appdir_join(staging_dir, "bunny-server-linux-x64.tar.gz");
    if (!archive_path || bunny_updater_download_file(transport, check.download_url, user_agent, archive_path) != BUNNY_HTTP_OK) {
        server_log("ERROR", "updater: download of %s failed", check.tag_name);
        bunny_updater_check_result_free(&check);
        free(archive_path);
        free(staging_dir);
        return;
    }

    /* Mandatory, not best-effort -- a corrupted/truncated download (the
     * realistic risk here, not tampering: this is already plain HTTPS from
     * GitHub) must never get extracted and staged as if it were good. */
    bool checksum_ok = false;
    if (!check.sha256_sums_url) {
        server_log("ERROR", "updater: release %s has no SHA256SUMS.txt asset", check.tag_name);
    } else {
        char *sums_text = bunny_updater_download_text(transport, check.sha256_sums_url, user_agent);
        char expected_hex[65];
        char actual_hex[65];
        if (!sums_text) {
            server_log("ERROR", "updater: failed to download SHA256SUMS.txt for %s", check.tag_name);
        } else if (!bunny_updater_find_sha256(sums_text, "bunny-server-linux-x64.tar.gz", expected_hex)) {
            server_log("ERROR", "updater: SHA256SUMS.txt for %s has no entry for bunny-server-linux-x64.tar.gz", check.tag_name);
        } else if (!bunny_updater_sha256_hex(archive_path, actual_hex)) {
            server_log("ERROR", "updater: failed to hash the downloaded archive for %s", check.tag_name);
        } else if (strcmp(expected_hex, actual_hex) != 0) {
            server_log("ERROR", "updater: checksum mismatch for %s (expected %s, got %s)", check.tag_name, expected_hex, actual_hex);
        } else {
            checksum_ok = true;
        }
        free(sums_text);
    }
    if (!checksum_ok) {
        remove(archive_path);
        bunny_updater_check_result_free(&check);
        free(archive_path);
        free(staging_dir);
        return;
    }

    char *extracted_dir = goblin_appdir_join(staging_dir, "extracted");
    bool extracted = extracted_dir && bunny_updater_extract_tar_gz(archive_path, extracted_dir);
    remove(archive_path);
    free(archive_path);
    if (!extracted) {
        server_log("ERROR", "updater: failed to extract the downloaded %s archive", check.tag_name);
        bunny_updater_check_result_free(&check);
        free(extracted_dir);
        free(staging_dir);
        return;
    }

    char *extracted_binary = goblin_appdir_join(extracted_dir, "bunny_server");
    struct stat st;
#ifdef _WIN32
    bool binary_present = extracted_binary && stat(extracted_binary, &st) == 0;
#else
    bool binary_present = extracted_binary && stat(extracted_binary, &st) == 0 && (st.st_mode & S_IXUSR);
#endif
    free(extracted_binary);
    free(extracted_dir);
    if (!binary_present) {
        server_log("ERROR", "updater: extracted archive for %s has no executable bunny_server", check.tag_name);
        bunny_updater_check_result_free(&check);
        free(staging_dir);
        return;
    }

    /* The marker deploy/bunny-server-update-apply.sh's ExecStartPre=+ step
     * looks for -- its mere existence (contents unused) means "a verified
     * binary is staged and ready to install", checked on the NEXT service
     * start. This process never installs it (and never restarts itself) --
     * that's the root-run helper's job, specifically so this sandboxed,
     * unprivileged process never needs write access to /usr/local/bin. */
    char *ready_marker = goblin_appdir_join(data_dir, "update-ready");
    if (ready_marker) {
        touch_marker(ready_marker);
        free(ready_marker);
    }
    free(staging_dir);

    server_log("INFO", "updater: %s staged and verified -- will install on next restart", check.tag_name);
    bunny_updater_check_result_free(&check);
    *out_restart_requested = true;
}
