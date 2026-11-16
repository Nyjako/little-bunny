#include "unity.h"

#include "commands.h"

#include <bunny_core/core.h>
#include <test_http_server.h>

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* Covers commands.c's own claim/process loop -- the piece destination.c's
 * tests don't touch at all -- against a *real* bunny_core_t and a real
 * local HTTP server (bunny_test_http_server, the same fixture
 * bunny_core_test_download already uses), not a fake. Post rows are
 * created via bunny_core_fetch_and_cache_post against an injected fake
 * e621_transport (same pattern test_sync.c already uses), with each
 * post's own file.url pointed at the local test server instead of a real
 * e621 CDN URL -- the actual download_start/_poll/_release calls commands.c
 * makes are then genuine local HTTP fetches, exercising the real
 * destination.c-resolved path end to end. */

typedef struct
{
    const char *bodies[8];
    size_t body_count;
    size_t next_index;
} fake_transport_state_t;

static fake_transport_state_t g_e621_state;
static bunny_http_transport_t g_e621_transport;
static bunny_core_t *g_core;
static char g_dest_dir[256];

static bunny_http_result_t fake_send(void *user_data, const bunny_http_request_t *request, bunny_http_response_t *out_response)
{
    (void)request;
    fake_transport_state_t *state = (fake_transport_state_t *)user_data;
    const char *body = state->next_index < state->body_count ? state->bodies[state->next_index] : "";
    state->next_index++;
    out_response->status = 200;
    out_response->body = strdup(body);
    out_response->body_len = strlen(body);
    return BUNNY_HTTP_OK;
}

/* A minimal but valid e621 single-post JSON response -- file.md5 is
 * deliberately empty ("no checksum to contradict", same convention
 * bunny_core_download_start's own doc comment describes), so the download
 * always resolves to VERIFIED regardless of what bytes the local test
 * server actually serves. */
static char *make_post_json(int64_t external_id, const char *file_url)
{
    char *buf = malloc(1024);
    snprintf(buf, 1024,
             "{\"post\":{\"id\":%lld,\"created_at\":\"2024-01-01T00:00:00.000-05:00\","
             "\"file\":{\"width\":1,\"height\":1,\"ext\":\"png\",\"size\":1,\"md5\":\"\",\"url\":\"%s\"},"
             "\"preview\":{\"width\":1,\"height\":1,\"url\":\"%s\"},\"sample\":{\"has\":false},"
             "\"score\":{\"up\":0,\"down\":0,\"total\":0},"
             "\"tags\":{\"general\":[],\"species\":[],\"character\":[],\"copyright\":[],\"artist\":[\"someartist\"],\"invalid\":[],\"lore\":[],\"meta\":[]},"
             "\"rating\":\"s\",\"fav_count\":0,\"sources\":[],\"description\":\"\",\"comment_count\":0,\"is_favorited\":false,\"pools\":[],"
             "\"relationships\":{\"has_children\":false,\"has_active_children\":false,\"children\":[]}}}",
             (long long)external_id, file_url, file_url);
    return buf;
}

void setUp(void)
{
    memset(&g_e621_state, 0, sizeof(g_e621_state));
    g_e621_transport.send = fake_send;
    g_e621_transport.user_data = &g_e621_state;

    bunny_core_config_t config;
    memset(&config, 0, sizeof(config));
    config.db_path = ":memory:";
    config.user_agent = "bunny-cli-tests/1.0 (unit tests)";
    config.e621_transport = &g_e621_transport;
    config.min_request_interval_sec = 0.001;

    bunny_core_result_t result = bunny_core_open(&config, &g_core);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);

    snprintf(g_dest_dir, sizeof(g_dest_dir), "/tmp/bunny_cli_test_download_%d", rand());
}

static void remove_dest_dir(void)
{
    char cmd[300];
    snprintf(cmd, sizeof(cmd), "rm -rf '%s'", g_dest_dir);
    system(cmd); /* test cleanup only -- g_dest_dir is always this file's own fixed-prefix temp path */
}

void tearDown(void)
{
    bunny_core_close(g_core);
    g_core = NULL;
    remove_dest_dir();
}

static int64_t fetch_fake_post(int64_t external_id, const char *file_url)
{
    char *body = make_post_json(external_id, file_url);
    g_e621_state.bodies[g_e621_state.body_count++] = body;

    int64_t post_id = 0;
    bunny_core_result_t result = bunny_core_fetch_and_cache_post(g_core, BUNNY_DB_SITE_E621, external_id, &post_id);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_TRUE(post_id > 0);
    return post_id;
}

void test_multiple_workers_each_claim_a_distinct_item_and_all_succeed(void)
{
    bunny_test_http_server_t *server = bunny_test_http_server_start("200 OK", "hello world", strlen("hello world"), 4);
    TEST_ASSERT_NOT_NULL(server);
    char *url = bunny_test_http_server_url(server);

    int64_t queue_ids[4];
    for (int i = 0; i < 4; i++) {
        int64_t post_id = fetch_fake_post(100 + i, url);
        bunny_core_result_t result = bunny_core_download_queue_add(g_core, post_id, 0, NULL, 0, &queue_ids[i]);
        TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    }

    int exit_code = bunny_cli_cmd_download(g_core, g_dest_dir, 3);
    TEST_ASSERT_EQUAL(0, exit_code);

    bunny_test_http_server_join(server); /* confirms exactly 4 real HTTP fetches happened, not more/fewer */
    free(url);

    bunny_db_download_queue_list_t list;
    bunny_core_download_queue_list(g_core, &list);
    TEST_ASSERT_EQUAL(4, (int)list.count);
    for (size_t i = 0; i < list.count; i++) {
        TEST_ASSERT_EQUAL(BUNNY_DB_DOWNLOAD_QUEUE_SUCCEEDED, list.items[i].status);
    }
    bunny_db_download_queue_list_free(&list);

    for (int i = 0; i < 4; i++) {
        char path[512];
        snprintf(path, sizeof(path), "%s/someartist/%d.png", g_dest_dir, 100 + i);
        TEST_ASSERT_EQUAL(0, access(path, F_OK));
    }
}

void test_posts_missing_locally_fail_gracefully_with_no_hang_and_no_duplicate_claims(void)
{
    int64_t queue_ids[3];
    for (int i = 0; i < 3; i++) {
        /* post_id 9001+i was never fetched/cached -- bunny_core_post_get_by_id
         * will fail to resolve it, the exact case this is checking never
         * hangs or double-claims. */
        bunny_core_result_t result = bunny_core_download_queue_add(g_core, 9001 + i, 0, NULL, 0, &queue_ids[i]);
        TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    }

    int exit_code = bunny_cli_cmd_download(g_core, g_dest_dir, 4); /* more workers than items, on purpose */
    TEST_ASSERT_EQUAL(1, exit_code);

    bunny_db_download_queue_list_t list;
    bunny_core_download_queue_list(g_core, &list);
    TEST_ASSERT_EQUAL(3, (int)list.count);
    for (size_t i = 0; i < list.count; i++) {
        TEST_ASSERT_EQUAL(BUNNY_DB_DOWNLOAD_QUEUE_FAILED, list.items[i].status);
        TEST_ASSERT_NOT_NULL(list.items[i].failure_reason);
    }
    bunny_db_download_queue_list_free(&list);
}

void test_an_empty_queue_succeeds_immediately_with_nothing_to_do(void)
{
    int exit_code = bunny_cli_cmd_download(g_core, g_dest_dir, 3);
    TEST_ASSERT_EQUAL(0, exit_code);
}

void test_a_null_download_folder_fails_immediately_without_touching_the_queue(void)
{
    int64_t queue_id = 0;
    bunny_core_download_queue_add(g_core, 1, 0, NULL, 0, &queue_id);

    int exit_code = bunny_cli_cmd_download(g_core, NULL, 3);
    TEST_ASSERT_EQUAL(1, exit_code);

    bunny_db_download_queue_list_t list;
    bunny_core_download_queue_list(g_core, &list);
    TEST_ASSERT_EQUAL(BUNNY_DB_DOWNLOAD_QUEUE_QUEUED, list.items[0].status); /* untouched */
    bunny_db_download_queue_list_free(&list);
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_multiple_workers_each_claim_a_distinct_item_and_all_succeed);
    RUN_TEST(test_posts_missing_locally_fail_gracefully_with_no_hang_and_no_duplicate_claims);
    RUN_TEST(test_an_empty_queue_succeeds_immediately_with_nothing_to_do);
    RUN_TEST(test_a_null_download_folder_fails_immediately_without_touching_the_queue);
    return UNITY_END();
}
