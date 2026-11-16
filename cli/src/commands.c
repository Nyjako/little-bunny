#include "commands.h"

#include "destination.h"
#include "log.h"

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

int bunny_cli_cmd_search(bunny_core_t *core, bunny_db_site_t site, const char *query, int page)
{
    bunny_db_post_list_t list;
    bunny_core_result_t result = bunny_core_preview_search(core, site, query, page, NULL, &list);
    if (result != BUNNY_CORE_OK) {
        bunny_cli_log(BUNNY_CLI_LOG_ERROR, "search failed: %s", bunny_core_result_to_string(result));
        return 1;
    }

    cJSON *json = bunny_cli_post_list_to_json(&list);
    char *printed = cJSON_Print(json);
    printf("%s\n", printed);

    free(printed);
    cJSON_Delete(json);
    bunny_db_post_list_free(&list);
    return 0;
}

int bunny_cli_cmd_pool(bunny_core_t *core, int64_t pool_id)
{
    bunny_core_pool_info_t info;
    bunny_core_result_t result = bunny_core_fetch_pool(core, pool_id, &info);
    if (result != BUNNY_CORE_OK) {
        bunny_cli_log(BUNNY_CLI_LOG_ERROR, "pool fetch failed: %s", bunny_core_result_to_string(result));
        return 1;
    }

    cJSON *json = bunny_cli_pool_info_to_json(&info);
    char *printed = cJSON_Print(json);
    printf("%s\n", printed);

    free(printed);
    cJSON_Delete(json);
    bunny_core_pool_info_free(&info);
    return 0;
}

int bunny_cli_cmd_stats(bunny_core_t *core)
{
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
    bunny_core_t *core;
    bunny_mutex_t claim_mutex; /* guards both claiming a row and the two counters below */
    int succeeded;
    int failed;
} download_shared_state_t;

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
    bunny_db_post_t post;
    memset(&post, 0, sizeof(post));
    bool have_post = bunny_core_post_get_by_id(state->core, item->post_id, &post) == BUNNY_CORE_OK;

    bunny_db_download_queue_status_t new_status = BUNNY_DB_DOWNLOAD_QUEUE_FAILED;
    char error_message[256] = "";

    if (!have_post) {
        snprintf(error_message, sizeof(error_message), "post %lld not found locally", (long long)item->post_id);
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
        bunny_db_post_free(&post);
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

int bunny_cli_cmd_download(bunny_core_t *core, const char *download_folder, int jobs)
{
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
    state.core = core;
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

int bunny_cli_cmd_favorite_add(bunny_core_t *core, int64_t post_id, int stars)
{
    char description[128];
    snprintf(description, sizeof(description), "favorited post %lld", (long long)post_id);
    return drain_and_report(core, bunny_core_queue_favorite_add(core, post_id, stars), description);
}

int bunny_cli_cmd_favorite_remove(bunny_core_t *core, int64_t post_id)
{
    char description[128];
    snprintf(description, sizeof(description), "unfavorited post %lld", (long long)post_id);
    return drain_and_report(core, bunny_core_queue_favorite_remove(core, post_id), description);
}

int bunny_cli_cmd_vote(bunny_core_t *core, int64_t post_id, int score)
{
    if (score < -1 || score > 1) {
        bunny_cli_log(BUNNY_CLI_LOG_ERROR, "vote score must be -1, 0, or 1 (got %d)", score);
        return 1;
    }

    char description[128];
    snprintf(description, sizeof(description), "voted %+d on post %lld", score, (long long)post_id);
    return drain_and_report(core, bunny_core_queue_vote(core, post_id, score, false), description);
}
