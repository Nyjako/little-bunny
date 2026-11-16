#include "commands.h"

#include "destination.h"
#include "log.h"

#include <bunny_common/json.h>
#include <bunny_common/thread.h>
#include <cJSON.h>

#include "json_helpers.h"

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <unistd.h>
#endif

static void sleep_ms(unsigned int ms)
{
#ifdef _WIN32
    Sleep(ms);
#else
    usleep(ms * 1000);
#endif
}

/* A command with no networked implementation (--download, --sync,
 * --queue-list, --stats) reaches this instead of guessing -- see each
 * public function's own doc comment in commands.h for why that particular
 * command doesn't fit the REST surface the same way. */
static int report_not_supported_over_network(const char *command_name)
{
    bunny_cli_log(BUNNY_CLI_LOG_ERROR, "%s isn't supported in networked mode yet, see cli/README.md", command_name);
    return 1;
}

/* Prints an already-parsed response body (the server's post/pool/blacklist
 * JSON shapes are deliberately identical to bunny_cli's own, json_helpers.h's
 * own doc comment) exactly the way the standalone path prints its own
 * cJSON object -- re-printed via cJSON_Print rather than echoing the raw
 * response body text, so formatting stays consistent either way. */
static void print_json(const cJSON *json)
{
    char *printed = cJSON_Print(json);
    printf("%s\n", printed);
    free(printed);
}

static int cmd_search_standalone(bunny_core_t *core, bunny_db_site_t site, const char *query, int page)
{
    bunny_db_post_list_t list;
    bunny_core_result_t result = bunny_core_preview_search(core, site, query, page, NULL, &list);
    if (result != BUNNY_CORE_OK) {
        bunny_cli_log(BUNNY_CLI_LOG_ERROR, "search failed: %s", bunny_core_result_to_string(result));
        return 1;
    }

    cJSON *json = bunny_cli_post_list_to_json(&list);
    print_json(json);

    cJSON_Delete(json);
    bunny_db_post_list_free(&list);
    return 0;
}

static int cmd_search_networked(bunny_cli_rest_client_t *rest, bunny_db_site_t site, const char *query, int page)
{
    char *encoded_query = bunny_cli_rest_url_encode(query);
    char path[1200];
    snprintf(path, sizeof(path), "/search/preview?site=%s&query=%s&page=%d", bunny_db_site_to_string(site), encoded_query ? encoded_query : "", page);
    free(encoded_query);

    cJSON *response = NULL;
    bunny_cli_rest_result_t result = bunny_cli_rest_request(rest, BUNNY_HTTP_POST, path, NULL, &response);
    if (result != BUNNY_CLI_REST_OK) {
        bunny_cli_log(BUNNY_CLI_LOG_ERROR, "search failed: %s", bunny_cli_rest_result_to_string(result));
        cJSON_Delete(response);
        return 1;
    }

    print_json(response);
    cJSON_Delete(response);
    return 0;
}

int bunny_cli_cmd_search(bunny_cli_context_t *ctx, bunny_db_site_t site, const char *query, int page)
{
    if (ctx->mode == BUNNY_CLI_MODE_NETWORKED) {
        return cmd_search_networked(ctx->rest, site, query, page);
    }
    return cmd_search_standalone(ctx->core, site, query, page);
}

static int cmd_pool_standalone(bunny_core_t *core, int64_t pool_id)
{
    bunny_core_pool_info_t info;
    bunny_core_result_t result = bunny_core_fetch_pool(core, pool_id, &info);
    if (result != BUNNY_CORE_OK) {
        bunny_cli_log(BUNNY_CLI_LOG_ERROR, "pool fetch failed: %s", bunny_core_result_to_string(result));
        return 1;
    }

    cJSON *json = bunny_cli_pool_info_to_json(&info);
    print_json(json);

    cJSON_Delete(json);
    bunny_core_pool_info_free(&info);
    return 0;
}

static int cmd_pool_networked(bunny_cli_rest_client_t *rest, int64_t pool_id)
{
    char path[64];
    snprintf(path, sizeof(path), "/pools/%lld", (long long)pool_id);

    cJSON *response = NULL;
    bunny_cli_rest_result_t result = bunny_cli_rest_request(rest, BUNNY_HTTP_GET, path, NULL, &response);
    if (result != BUNNY_CLI_REST_OK) {
        bunny_cli_log(BUNNY_CLI_LOG_ERROR, "pool fetch failed: %s", bunny_cli_rest_result_to_string(result));
        cJSON_Delete(response);
        return 1;
    }

    print_json(response);
    cJSON_Delete(response);
    return 0;
}

int bunny_cli_cmd_pool(bunny_cli_context_t *ctx, int64_t pool_id)
{
    if (ctx->mode == BUNNY_CLI_MODE_NETWORKED) {
        return cmd_pool_networked(ctx->rest, pool_id);
    }
    return cmd_pool_standalone(ctx->core, pool_id);
}

int bunny_cli_cmd_stats(bunny_cli_context_t *ctx)
{
    if (ctx->mode == BUNNY_CLI_MODE_NETWORKED) {
        return report_not_supported_over_network("--stats");
    }
    bunny_core_t *core = ctx->core;
    bunny_db_tag_stat_list_t table_stats;
    bunny_core_result_t result = bunny_core_table_stats(core, &table_stats);
    if (result != BUNNY_CORE_OK) {
        bunny_cli_log(BUNNY_CLI_LOG_ERROR, "failed to query table row counts: %s", bunny_core_result_to_string(result));
        return 1;
    }

    for (size_t i = 0; i < table_stats.count; i++) {
        bunny_cli_log(BUNNY_CLI_LOG_INFO, "%-24s %d", table_stats.items[i].name, table_stats.items[i].count);
    }
    bunny_db_tag_stat_list_free(&table_stats);

    bool integrity_ok = false;
    result = bunny_core_integrity_check(core, &integrity_ok);
    if (result != BUNNY_CORE_OK) {
        bunny_cli_log(BUNNY_CLI_LOG_ERROR, "integrity check itself failed: %s", bunny_core_result_to_string(result));
        return 1;
    }

    bunny_cli_log(integrity_ok ? BUNNY_CLI_LOG_SUCCESS : BUNNY_CLI_LOG_ERROR, "database integrity: %s", integrity_ok ? "OK" : "FAILED");
    return integrity_ok ? 0 : 1;
}

/* ---- --download ------------------------------------------------------- */

/* One claimed download_queue row's data, copied out of the row bunny_core
 * returned before that row's own list is freed -- pool_name is duplicated
 * (not borrowed) for the same reason. */
typedef struct
{
    int64_t queue_id;
    int64_t post_id;
    int64_t pool_id;
    char *pool_name; /* owned, may be NULL */
    int pool_page;
} claimed_item_t;

typedef struct
{
    bunny_core_t *core;            /* the local download-queue db, both modes -- see bunny_cli_context_t's own doc comment */
    bunny_cli_rest_client_t *rest; /* non-NULL in networked mode only, used to resolve each post's own metadata */
    bunny_mutex_t claim_mutex;     /* guards both claiming a row and the two counters below */
    int succeeded;
    int failed;
} download_shared_state_t;

/* A post's metadata, however it was resolved (bunny_core_post_get_by_id
 * locally, or GET /posts/{id} over REST) -- just the handful of fields
 * process_claimed_item actually needs, so it doesn't have to care which
 * path produced them. All strings owned; free with resolved_post_free. */
typedef struct
{
    char *artist;
    char *file_ext;
    char *file_url;
    char *file_md5;
    int64_t external_id;
    bunny_db_site_t site;
} resolved_post_t;

static void resolved_post_free(resolved_post_t *post)
{
    free(post->artist);
    free(post->file_ext);
    free(post->file_url);
    free(post->file_md5);
    memset(post, 0, sizeof(*post));
}

static bool resolve_post_standalone(bunny_core_t *core, int64_t post_id, resolved_post_t *out)
{
    bunny_db_post_t post;
    if (bunny_core_post_get_by_id(core, post_id, &post) != BUNNY_CORE_OK) {
        return false;
    }
    memset(out, 0, sizeof(*out));
    out->artist = post.artist ? strdup(post.artist) : NULL;
    out->file_ext = post.file_ext ? strdup(post.file_ext) : NULL;
    out->file_url = post.file_url ? strdup(post.file_url) : NULL;
    out->file_md5 = post.file_md5 ? strdup(post.file_md5) : NULL;
    out->external_id = post.external_id;
    out->site = post.site;
    bunny_db_post_free(&post);
    return true;
}

/* The local queue db (ctx->core) never stores post data in networked mode
 * -- only the queue rows -- so this is a real network call per item,
 * fetching the exact same JSON shape bunny_cli_cmd_search/_pool already
 * forward as-is (json_helpers.h's own doc comment). */
static bool resolve_post_networked(bunny_cli_rest_client_t *rest, int64_t post_id, resolved_post_t *out)
{
    char path[64];
    snprintf(path, sizeof(path), "/posts/%lld", (long long)post_id);

    cJSON *json = NULL;
    bunny_cli_rest_result_t result = bunny_cli_rest_request(rest, BUNNY_HTTP_GET, path, NULL, &json);
    if (result != BUNNY_CLI_REST_OK || !json) {
        cJSON_Delete(json);
        return false;
    }

    memset(out, 0, sizeof(*out));
    const char *artist = bunny_json_get_string_or(json, "artist", NULL);
    const char *file_ext = bunny_json_get_string_or(json, "file_ext", NULL);
    const char *file_url = bunny_json_get_string_or(json, "file_url", NULL);
    const char *file_md5 = bunny_json_get_string_or(json, "file_md5", NULL);
    const char *site_text = bunny_json_get_string_or(json, "site", "");
    out->artist = artist ? strdup(artist) : NULL;
    out->file_ext = file_ext ? strdup(file_ext) : NULL;
    out->file_url = file_url ? strdup(file_url) : NULL;
    out->file_md5 = file_md5 ? strdup(file_md5) : NULL;
    bunny_json_get_int64(json, "external_id", &out->external_id);
    out->site = strcmp(site_text, "inkbunny") == 0 ? BUNNY_DB_SITE_INKBUNNY : BUNNY_DB_SITE_E621;

    cJSON_Delete(json);
    return true;
}

/* Finds the next BUNNY_DB_DOWNLOAD_QUEUE_QUEUED row, marks it DOWNLOADING,
 * and copies its data into *out -- the whole find+mark step happens under
 * one lock so two worker threads can never claim the same row. Returns
 * false once nothing is left to claim (every worker's own loop exit). */
static bool claim_next_item(download_shared_state_t *state, claimed_item_t *out)
{
    bunny_mutex_lock(&state->claim_mutex);

    bunny_db_download_queue_list_t list;
    bunny_core_result_t result = bunny_core_download_queue_list(state->core, &list);
    if (result != BUNNY_CORE_OK) {
        bunny_mutex_unlock(&state->claim_mutex);
        return false;
    }

    bool found = false;
    for (size_t i = 0; i < list.count; i++) {
        if (list.items[i].status == BUNNY_DB_DOWNLOAD_QUEUE_QUEUED) {
            out->queue_id = list.items[i].id;
            out->post_id = list.items[i].post_id;
            out->pool_id = list.items[i].pool_id;
            out->pool_name = list.items[i].pool_name ? strdup(list.items[i].pool_name) : NULL;
            out->pool_page = list.items[i].pool_page;
            found = true;
            break;
        }
    }
    bunny_db_download_queue_list_free(&list);

    if (found) {
        bunny_core_download_queue_set_status(state->core, out->queue_id, BUNNY_DB_DOWNLOAD_QUEUE_DOWNLOADING, NULL);
    }

    bunny_mutex_unlock(&state->claim_mutex);
    return found;
}

/* Inkbunny's CDN rejects a bare request with no User-Agent/Referer with a
 * 403 (e621's has no such requirement) -- same headers/values as
 * imageHeadersFor (app/lib/util/image_headers.dart) on the Dart side. */
static size_t extra_headers_for_site(bunny_db_site_t site, bunny_http_header_t *out_headers)
{
    if (site != BUNNY_DB_SITE_INKBUNNY) {
        return 0;
    }
    out_headers[0].name = "User-Agent";
    out_headers[0].value = "LittleBunny/1.0 (+https://github.com/Nyjako/little-bunny)";
    out_headers[1].name = "Referer";
    out_headers[1].value = "https://inkbunny.net/";
    return 2;
}

/* Downloads one already-claimed row, then reports its outcome back to the
 * queue and the shared counters. Frees item->pool_name before returning --
 * callers must treat *item as consumed afterward. */
static void process_claimed_item(download_shared_state_t *state, const char *download_folder, claimed_item_t *item)
{
    resolved_post_t post;
    bool have_post = state->rest ? resolve_post_networked(state->rest, item->post_id, &post) : resolve_post_standalone(state->core, item->post_id, &post);

    bunny_db_download_queue_status_t new_status = BUNNY_DB_DOWNLOAD_QUEUE_FAILED;
    char error_message[256] = "";

    if (!have_post) {
        snprintf(error_message, sizeof(error_message), "post %lld could not be resolved", (long long)item->post_id);
    } else if (!post.file_url) {
        snprintf(error_message, sizeof(error_message), "post %lld has no file to download", (long long)item->post_id);
    } else {
        char folder[BUNNY_CLI_DESTINATION_MAX];
        char filename[BUNNY_CLI_DESTINATION_MAX];
        bunny_cli_destination_for(post.artist, post.file_ext, post.external_id, item->pool_id, item->pool_name, item->pool_page, folder, filename);

        char dest_dir[BUNNY_CLI_DESTINATION_MAX * 2];
        snprintf(dest_dir, sizeof(dest_dir), "%s/%s", download_folder, folder);

        bunny_http_header_t headers[2];
        size_t header_count = extra_headers_for_site(post.site, headers);

        int64_t handle = 0;
        bunny_core_result_t start_result = bunny_core_download_start(post.file_url, header_count ? headers : NULL, header_count, dest_dir, filename, post.file_md5, &handle);
        if (start_result != BUNNY_CORE_OK) {
            snprintf(error_message, sizeof(error_message), "failed to start: %s", bunny_core_result_to_string(start_result));
        } else {
            bool done = false;
            bunny_core_download_outcome_t outcome = BUNNY_CORE_DOWNLOAD_FAILED;
            while (!done) {
                int64_t received = 0;
                int64_t total = 0;
                bunny_core_download_poll(handle, &received, &total, &done, &outcome, error_message, sizeof(error_message));
                if (!done) {
                    sleep_ms(150);
                }
            }
            bunny_core_download_release(handle);

            switch (outcome) {
                case BUNNY_CORE_DOWNLOAD_VERIFIED:
                    new_status = BUNNY_DB_DOWNLOAD_QUEUE_SUCCEEDED;
                    break;
                case BUNNY_CORE_DOWNLOAD_CHECKSUM_MISMATCH:
                    new_status = BUNNY_DB_DOWNLOAD_QUEUE_CHECKSUM_MISMATCH;
                    break;
                case BUNNY_CORE_DOWNLOAD_FAILED:
                    new_status = BUNNY_DB_DOWNLOAD_QUEUE_FAILED;
                    break;
            }
        }
    }

    bunny_mutex_lock(&state->claim_mutex);
    bunny_core_download_queue_set_status(state->core, item->queue_id, new_status, error_message[0] ? error_message : NULL);
    if (new_status == BUNNY_DB_DOWNLOAD_QUEUE_SUCCEEDED) {
        state->succeeded++;
        bunny_cli_log(BUNNY_CLI_LOG_SUCCESS, "post %lld downloaded", (long long)item->post_id);
    } else {
        state->failed++;
        bunny_cli_log(BUNNY_CLI_LOG_ERROR, "post %lld: %s", (long long)item->post_id, error_message[0] ? error_message : bunny_db_download_queue_status_to_string(new_status));
    }
    bunny_mutex_unlock(&state->claim_mutex);

    if (have_post) {
        resolved_post_free(&post);
    }
    free(item->pool_name);
}

typedef struct
{
    download_shared_state_t *state;
    const char *download_folder;
} worker_arg_t;

static void *worker_thread_fn(void *arg_ptr)
{
    worker_arg_t *arg = arg_ptr;
    claimed_item_t item;
    while (claim_next_item(arg->state, &item)) {
        process_claimed_item(arg->state, arg->download_folder, &item);
    }
    return NULL;
}

#define BUNNY_CLI_MAX_DOWNLOAD_JOBS 8 /* matches bunny_core's own fixed download-slot table */

int bunny_cli_cmd_download(bunny_cli_context_t *ctx, const char *download_folder, int jobs)
{
    if (!ctx->core) {
        bunny_cli_log(BUNNY_CLI_LOG_ERROR, "no local download-queue database available (the app didn't report one -- an older app build?)");
        return 1;
    }
    if (!download_folder) {
        bunny_cli_log(BUNNY_CLI_LOG_ERROR, "no download destination folder configured in the app yet");
        return 1;
    }
    if (jobs < 1) {
        jobs = 1;
    }
    if (jobs > BUNNY_CLI_MAX_DOWNLOAD_JOBS) {
        jobs = BUNNY_CLI_MAX_DOWNLOAD_JOBS;
    }

    download_shared_state_t state;
    state.core = ctx->core;
    state.rest = ctx->mode == BUNNY_CLI_MODE_NETWORKED ? ctx->rest : NULL;
    state.succeeded = 0;
    state.failed = 0;
    bunny_mutex_init(&state.claim_mutex);

    worker_arg_t arg;
    arg.state = &state;
    arg.download_folder = download_folder;

    bunny_cli_log(BUNNY_CLI_LOG_INFO, "draining the download queue with %d worker(s)...", jobs);

    bunny_thread_t threads[BUNNY_CLI_MAX_DOWNLOAD_JOBS];
    int thread_count = 0;
    for (int i = 0; i < jobs; i++) {
        if (bunny_thread_create(&threads[thread_count], worker_thread_fn, &arg) == 0) {
            thread_count++;
        }
    }
    for (int i = 0; i < thread_count; i++) {
        bunny_thread_join(threads[i]);
    }

    bunny_mutex_destroy(&state.claim_mutex);

    bunny_cli_log(state.failed == 0 ? BUNNY_CLI_LOG_SUCCESS : BUNNY_CLI_LOG_WARN, "done: %d succeeded, %d failed", state.succeeded, state.failed);
    return state.failed == 0 ? 0 : 1;
}

/* ---- --favorite / --unfavorite / --vote -------------------------------- */

/* Drains the action queue right after enqueuing one action, and reports
 * the result -- shared by every bunny_cli_cmd_favorite_add/_remove/_vote
 * below, which differ only in which bunny_core_queue_* call they make
 * first and what to say on success. */
static int drain_and_report(bunny_core_t *core, bunny_core_result_t enqueue_result, const char *action_description)
{
    if (enqueue_result != BUNNY_CORE_OK) {
        bunny_cli_log(BUNNY_CLI_LOG_ERROR, "failed to queue %s: %s", action_description, bunny_core_result_to_string(enqueue_result));
        return 1;
    }

    bunny_core_queue_stats_t stats;
    memset(&stats, 0, sizeof(stats));
    bunny_core_result_t process_result = bunny_core_process_queue(core, &stats);
    if (process_result != BUNNY_CORE_OK) {
        bunny_cli_log(BUNNY_CLI_LOG_ERROR, "failed to drain the action queue: %s", bunny_core_result_to_string(process_result));
        return 1;
    }

    if (stats.actions_failed > 0) {
        bunny_cli_log(BUNNY_CLI_LOG_ERROR, "%s failed (see the app/server's own log for the site's error)", action_description);
        return 1;
    }

    bunny_cli_log(BUNNY_CLI_LOG_SUCCESS, "%s", action_description);
    return 0;
}

/* Networked counterpart to drain_and_report above: enqueues one action via
 * `method`/`path`/`body` (POST/DELETE /posts/{id}/favorite, POST
 * /posts/{id}/vote -- each a 202 "queued" response, server/src/routes_queue.c),
 * then drains the server's own action queue via POST /queue/process and
 * reports its actions_failed count, same immediate-feedback contract as the
 * standalone path. */
static int drain_and_report_networked(bunny_cli_rest_client_t *rest, bunny_http_method_t method, const char *path, const cJSON *body, const char *action_description)
{
    bunny_cli_rest_result_t enqueue_result = bunny_cli_rest_request(rest, method, path, body, NULL);
    if (enqueue_result != BUNNY_CLI_REST_OK) {
        bunny_cli_log(BUNNY_CLI_LOG_ERROR, "failed to queue %s: %s", action_description, bunny_cli_rest_result_to_string(enqueue_result));
        return 1;
    }

    cJSON *stats_json = NULL;
    bunny_cli_rest_result_t process_result = bunny_cli_rest_request(rest, BUNNY_HTTP_POST, "/queue/process", NULL, &stats_json);
    if (process_result != BUNNY_CLI_REST_OK) {
        bunny_cli_log(BUNNY_CLI_LOG_ERROR, "failed to drain the action queue: %s", bunny_cli_rest_result_to_string(process_result));
        cJSON_Delete(stats_json);
        return 1;
    }

    int actions_failed = bunny_json_get_int_or(stats_json, "actions_failed", 0);
    cJSON_Delete(stats_json);

    if (actions_failed > 0) {
        bunny_cli_log(BUNNY_CLI_LOG_ERROR, "%s failed (see the server's own log for the site's error)", action_description);
        return 1;
    }

    bunny_cli_log(BUNNY_CLI_LOG_SUCCESS, "%s", action_description);
    return 0;
}

int bunny_cli_cmd_favorite_add(bunny_cli_context_t *ctx, int64_t post_id, int stars)
{
    char description[128];
    snprintf(description, sizeof(description), "favorited post %lld", (long long)post_id);

    if (ctx->mode == BUNNY_CLI_MODE_NETWORKED) {
        char path[64];
        snprintf(path, sizeof(path), "/posts/%lld/favorite", (long long)post_id);
        cJSON *body = cJSON_CreateObject();
        cJSON_AddNumberToObject(body, "stars", stars);
        int exit_code = drain_and_report_networked(ctx->rest, BUNNY_HTTP_POST, path, body, description);
        cJSON_Delete(body);
        return exit_code;
    }
    return drain_and_report(ctx->core, bunny_core_queue_favorite_add(ctx->core, post_id, stars), description);
}

int bunny_cli_cmd_favorite_remove(bunny_cli_context_t *ctx, int64_t post_id)
{
    char description[128];
    snprintf(description, sizeof(description), "unfavorited post %lld", (long long)post_id);

    if (ctx->mode == BUNNY_CLI_MODE_NETWORKED) {
        char path[64];
        snprintf(path, sizeof(path), "/posts/%lld/favorite", (long long)post_id);
        return drain_and_report_networked(ctx->rest, BUNNY_HTTP_DELETE, path, NULL, description);
    }
    return drain_and_report(ctx->core, bunny_core_queue_favorite_remove(ctx->core, post_id), description);
}

int bunny_cli_cmd_vote(bunny_cli_context_t *ctx, int64_t post_id, int score)
{
    if (score < -1 || score > 1) {
        bunny_cli_log(BUNNY_CLI_LOG_ERROR, "vote score must be -1, 0, or 1 (got %d)", score);
        return 1;
    }

    char description[128];
    snprintf(description, sizeof(description), "voted %+d on post %lld", score, (long long)post_id);

    if (ctx->mode == BUNNY_CLI_MODE_NETWORKED) {
        char path[64];
        snprintf(path, sizeof(path), "/posts/%lld/vote", (long long)post_id);
        cJSON *body = cJSON_CreateObject();
        cJSON_AddNumberToObject(body, "score", score);
        cJSON_AddBoolToObject(body, "no_unvote", false);
        int exit_code = drain_and_report_networked(ctx->rest, BUNNY_HTTP_POST, path, body, description);
        cJSON_Delete(body);
        return exit_code;
    }
    return drain_and_report(ctx->core, bunny_core_queue_vote(ctx->core, post_id, score, false), description);
}

/* ---- --sync --------------------------------------------------------------- */

static void log_sync_stats(const bunny_core_sync_stats_t *stats)
{
    bunny_cli_log(BUNNY_CLI_LOG_INFO, "searches checked: %d, synced: %d", stats->searches_checked, stats->searches_synced);
    bunny_cli_log(BUNNY_CLI_LOG_INFO, "posts upserted: %d (%d new)", stats->posts_upserted, stats->new_posts_found);
    if (stats->seconds_until_next_due >= 0) {
        bunny_cli_log(BUNNY_CLI_LOG_INFO, "next search due in %.0f seconds", stats->seconds_until_next_due);
    }
}

/* Networked: the server's own sync is async (POST /sync or POST
 * /searches/{id}/sync just enqueue it onto the server's task queue and
 * return -- the server runs it in the background on its own, see
 * commands.h's own doc comment) -- this just triggers it and reports
 * whether the server actually accepted the request, never stats it was
 * never asked to go fetch (that's GET /sync/status's job, not this
 * command's). */
static int cmd_sync_networked(bunny_cli_rest_client_t *rest, int64_t search_id)
{
    char path[64];
    if (search_id == 0) {
        strcpy(path, "/sync");
    } else {
        snprintf(path, sizeof(path), "/searches/%lld/sync", (long long)search_id);
    }

    cJSON *response = NULL;
    bunny_cli_rest_result_t result = bunny_cli_rest_request(rest, BUNNY_HTTP_POST, path, NULL, &response);
    bool enqueued = bunny_json_get_bool_or(response, "enqueued", false);
    cJSON_Delete(response);

    if (result != BUNNY_CLI_REST_OK || !enqueued) {
        bunny_cli_log(BUNNY_CLI_LOG_ERROR, "sync request was not accepted: %s", result != BUNNY_CLI_REST_OK ? bunny_cli_rest_result_to_string(result) : "the server is already busy syncing");
        return 1;
    }

    bunny_cli_log(BUNNY_CLI_LOG_SUCCESS, "sync requested -- the server will run it in the background");
    return 0;
}

int bunny_cli_cmd_sync(bunny_cli_context_t *ctx, int64_t search_id)
{
    if (ctx->mode == BUNNY_CLI_MODE_NETWORKED) {
        return cmd_sync_networked(ctx->rest, search_id);
    }

    bunny_core_sync_stats_t stats;
    memset(&stats, 0, sizeof(stats));

    bunny_core_result_t result = search_id == 0 ? bunny_core_sync_due_searches(ctx->core, &stats) : bunny_core_sync_search(ctx->core, search_id, &stats);
    if (result != BUNNY_CORE_OK) {
        bunny_cli_log(BUNNY_CLI_LOG_ERROR, "sync failed: %s", bunny_core_result_to_string(result));
        return 1;
    }

    log_sync_stats(&stats);
    bunny_cli_log(BUNNY_CLI_LOG_SUCCESS, "sync complete");
    return 0;
}

/* ---- --blacklist-* ---------------------------------------------------------- */

static int cmd_blacklist_list_networked(bunny_cli_rest_client_t *rest, bunny_db_site_t site)
{
    char path[64];
    snprintf(path, sizeof(path), "/blacklist?site=%s", bunny_db_site_to_string(site));

    cJSON *response = NULL;
    bunny_cli_rest_result_t result = bunny_cli_rest_request(rest, BUNNY_HTTP_GET, path, NULL, &response);
    if (result != BUNNY_CLI_REST_OK) {
        bunny_cli_log(BUNNY_CLI_LOG_ERROR, "failed to list the blacklist: %s", bunny_cli_rest_result_to_string(result));
        cJSON_Delete(response);
        return 1;
    }

    print_json(response);
    cJSON_Delete(response);
    return 0;
}

int bunny_cli_cmd_blacklist_list(bunny_cli_context_t *ctx, bunny_db_site_t site)
{
    if (ctx->mode == BUNNY_CLI_MODE_NETWORKED) {
        return cmd_blacklist_list_networked(ctx->rest, site);
    }

    bunny_db_string_list_t list;
    bunny_core_result_t result = bunny_core_blacklist_list(ctx->core, site, &list);
    if (result != BUNNY_CORE_OK) {
        bunny_cli_log(BUNNY_CLI_LOG_ERROR, "failed to list the blacklist: %s", bunny_core_result_to_string(result));
        return 1;
    }

    cJSON *json = bunny_cli_string_list_to_json(&list);
    print_json(json);

    cJSON_Delete(json);
    bunny_db_string_list_free(&list);
    return 0;
}

int bunny_cli_cmd_blacklist_add(bunny_cli_context_t *ctx, bunny_db_site_t site, const char *tag)
{
    if (ctx->mode == BUNNY_CLI_MODE_NETWORKED) {
        cJSON *body = cJSON_CreateObject();
        cJSON_AddStringToObject(body, "site", bunny_db_site_to_string(site));
        cJSON_AddStringToObject(body, "tag", tag);
        bunny_cli_rest_result_t result = bunny_cli_rest_request(ctx->rest, BUNNY_HTTP_POST, "/blacklist", body, NULL);
        cJSON_Delete(body);
        if (result != BUNNY_CLI_REST_OK) {
            bunny_cli_log(BUNNY_CLI_LOG_ERROR, "failed to add blacklist rule \"%s\": %s", tag, bunny_cli_rest_result_to_string(result));
            return 1;
        }
        bunny_cli_log(BUNNY_CLI_LOG_SUCCESS, "added blacklist rule \"%s\"", tag);
        return 0;
    }

    bunny_core_result_t result = bunny_core_blacklist_add(ctx->core, site, tag);
    if (result != BUNNY_CORE_OK) {
        bunny_cli_log(BUNNY_CLI_LOG_ERROR, "failed to add blacklist rule \"%s\": %s", tag, bunny_core_result_to_string(result));
        return 1;
    }
    bunny_cli_log(BUNNY_CLI_LOG_SUCCESS, "added blacklist rule \"%s\"", tag);
    return 0;
}

int bunny_cli_cmd_blacklist_remove(bunny_cli_context_t *ctx, bunny_db_site_t site, const char *tag)
{
    if (ctx->mode == BUNNY_CLI_MODE_NETWORKED) {
        char *encoded_tag = bunny_cli_rest_url_encode(tag);
        char path[512];
        snprintf(path, sizeof(path), "/blacklist?site=%s&tag=%s", bunny_db_site_to_string(site), encoded_tag ? encoded_tag : "");
        free(encoded_tag);

        bunny_cli_rest_result_t result = bunny_cli_rest_request(ctx->rest, BUNNY_HTTP_DELETE, path, NULL, NULL);
        if (result != BUNNY_CLI_REST_OK) {
            bunny_cli_log(BUNNY_CLI_LOG_ERROR, "failed to remove blacklist rule \"%s\": %s", tag, bunny_cli_rest_result_to_string(result));
            return 1;
        }
        bunny_cli_log(BUNNY_CLI_LOG_SUCCESS, "removed blacklist rule \"%s\"", tag);
        return 0;
    }

    bunny_core_result_t result = bunny_core_blacklist_remove(ctx->core, site, tag);
    if (result != BUNNY_CORE_OK) {
        bunny_cli_log(BUNNY_CLI_LOG_ERROR, "failed to remove blacklist rule \"%s\": %s", tag, bunny_core_result_to_string(result));
        return 1;
    }
    bunny_cli_log(BUNNY_CLI_LOG_SUCCESS, "removed blacklist rule \"%s\"", tag);
    return 0;
}

/* ---- --queue-list ------------------------------------------------------------ */

int bunny_cli_cmd_queue_list(bunny_cli_context_t *ctx)
{
    if (!ctx->core) {
        bunny_cli_log(BUNNY_CLI_LOG_ERROR, "no local download-queue database available (the app didn't report one -- an older app build?)");
        return 1;
    }

    bunny_db_download_queue_list_t list;
    bunny_core_result_t result = bunny_core_download_queue_list(ctx->core, &list);
    if (result != BUNNY_CORE_OK) {
        bunny_cli_log(BUNNY_CLI_LOG_ERROR, "failed to list the download queue: %s", bunny_core_result_to_string(result));
        return 1;
    }

    cJSON *json = bunny_cli_download_queue_list_to_json(&list);
    print_json(json);

    cJSON_Delete(json);
    bunny_db_download_queue_list_free(&list);
    return 0;
}
