#include "unity.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bunny_core/core.h"

typedef struct
{
    const char *body;
} fake_transport_state_t;

static fake_transport_state_t g_e621_state;
static bunny_http_transport_t g_e621_transport;
static bunny_core_t *g_core;

static bunny_http_result_t fake_send(void *user_data, const bunny_http_request_t *request, bunny_http_response_t *out_response)
{
    (void)request;
    fake_transport_state_t *state = (fake_transport_state_t *)user_data;
    const char *body = state->body ? state->body : "";
    out_response->status = 200;
    out_response->body = strdup(body);
    out_response->body_len = strlen(body);
    return BUNNY_HTTP_OK;
}

static char *read_fixture(const char *filename)
{
    char path[512];
    snprintf(path, sizeof(path), "%s/%s", FIXTURES_DIR, filename);

    FILE *f = fopen(path, "rb");
    if (!f) {
        return NULL;
    }
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);

    char *buf = malloc((size_t)size + 1);
    if (!buf) {
        fclose(f);
        return NULL;
    }
    if (fread(buf, 1, (size_t)size, f) != (size_t)size) {
        fclose(f);
        free(buf);
        return NULL;
    }
    buf[size] = '\0';
    fclose(f);
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
    config.user_agent = "bunny-tests/1.0 (unit tests)";
    config.e621_transport = &g_e621_transport;
    config.min_request_interval_sec = 0.001;

    bunny_core_result_t result = bunny_core_open(&config, &g_core);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
}

void tearDown(void)
{
    bunny_core_close(g_core);
    g_core = NULL;
}

/* Seeds one e621 post (external_id 1) via a real sync pass, so a
 * downloads row has a valid posts(id) to reference. */
static int64_t seed_e621_post(void)
{
    char *fixture = read_fixture("e621_posts_search.json");
    TEST_ASSERT_NOT_NULL(fixture);
    g_e621_state.body = fixture;

    int64_t search_id = 0;
    bunny_core_search_create(g_core, BUNNY_DB_SITE_E621, "wolves", "wolf", 24, NULL, &search_id);

    bunny_core_sync_stats_t sync_stats;
    bunny_core_result_t result = bunny_core_sync_due_searches(g_core, &sync_stats);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(1, sync_stats.posts_upserted);

    bunny_db_post_list_t posts;
    bunny_core_search_list_posts(g_core, search_id, false, 1, &posts);
    TEST_ASSERT_EQUAL(1, (int)posts.count);
    int64_t post_id = posts.items[0].id;
    bunny_db_post_list_free(&posts);

    free(fixture);
    return post_id;
}

void test_record_download_and_list_for_post(void)
{
    int64_t post_id = seed_e621_post();

    int64_t download_id = 0;
    bunny_core_result_t result = bunny_core_record_download(g_core, post_id, "/downloads/wolf/1.jpg", "abc123", true, &download_id);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_TRUE(download_id > 0);

    bunny_db_download_list_t list;
    result = bunny_core_list_downloads_for_post(g_core, post_id, &list);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(1, (int)list.count);
    TEST_ASSERT_EQUAL_STRING("/downloads/wolf/1.jpg", list.items[0].file_path);
    TEST_ASSERT_EQUAL_STRING("abc123", list.items[0].checksum_md5);
    TEST_ASSERT_TRUE(list.items[0].checksum_verified);
    bunny_db_download_list_free(&list);
}

void test_list_downloads_for_post_with_none_is_empty(void)
{
    int64_t post_id = seed_e621_post();

    bunny_db_download_list_t list;
    bunny_core_result_t result = bunny_core_list_downloads_for_post(g_core, post_id, &list);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(0, (int)list.count);
    bunny_db_download_list_free(&list);
}

void test_record_download_for_nonexistent_post_is_invalid_arg(void)
{
    bunny_core_result_t result = bunny_core_record_download(g_core, 999999, "/downloads/x.jpg", NULL, false, NULL);
    TEST_ASSERT_EQUAL(BUNNY_CORE_ERR_INVALID_ARG, result);
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_record_download_and_list_for_post);
    RUN_TEST(test_list_downloads_for_post_with_none_is_empty);
    RUN_TEST(test_record_download_for_nonexistent_post_is_invalid_arg);
    return UNITY_END();
}
