#include "unity.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bunny_core/core.h"

typedef struct
{
    long statuses[4];
    const char *bodies[4];
    size_t count;
    size_t next_index;
} fake_transport_state_t;

static fake_transport_state_t g_e621_state;
static fake_transport_state_t g_inkbunny_state;
static bunny_http_transport_t g_e621_transport;
static bunny_http_transport_t g_inkbunny_transport;
static bunny_core_t *g_core;

static bunny_http_result_t fake_send(void *user_data, const bunny_http_request_t *request, bunny_http_response_t *out_response)
{
    (void)request;
    fake_transport_state_t *state = (fake_transport_state_t *)user_data;
    size_t idx = state->next_index;
    /* 0 means "unset" (the struct is zero-initialized) -- default to 200 so
     * tests only need to set a status explicitly when testing a failure. */
    long status = idx < state->count && state->statuses[idx] != 0 ? state->statuses[idx] : 200;
    const char *body = idx < state->count && state->bodies[idx] ? state->bodies[idx] : "";
    state->next_index++;

    out_response->status = status;
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
    memset(&g_inkbunny_state, 0, sizeof(g_inkbunny_state));
    g_e621_transport.send = fake_send;
    g_e621_transport.user_data = &g_e621_state;
    g_inkbunny_transport.send = fake_send;
    g_inkbunny_transport.user_data = &g_inkbunny_state;

    bunny_core_config_t config;
    memset(&config, 0, sizeof(config));
    config.db_path = ":memory:";
    config.user_agent = "bunny-tests/1.0 (unit tests)";
    config.e621_transport = &g_e621_transport;
    config.inkbunny_transport = &g_inkbunny_transport;
    config.min_request_interval_sec = 0.001;

    bunny_core_result_t result = bunny_core_open(&config, &g_core);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);

    /* e621_favorite_add/vote/non-anonymous comment_create all require client
     * credentials -- without this, every e621 action below fails E621_ERR_AUTH
     * before it even reaches the fake transport's status code. */
    bunny_core_account_set(g_core, BUNNY_DB_SITE_E621, "tester", "test-api-key");
}

void tearDown(void)
{
    bunny_core_close(g_core);
    g_core = NULL;
}

/* Seeds one e621 post (external_id 1) via a real sync pass, consuming the
 * fake transport's queued response(s) that were set before calling this. */
static int64_t seed_e621_post(int64_t *out_search_id)
{
    int64_t search_id = 0;
    bunny_core_search_create(g_core, BUNNY_DB_SITE_E621, "wolves", "wolf", 24, &search_id);

    bunny_core_sync_stats_t sync_stats;
    bunny_core_result_t result = bunny_core_sync_due_searches(g_core, &sync_stats);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(1, sync_stats.posts_upserted);

    bunny_db_post_list_t posts;
    bunny_core_search_list_posts(g_core, search_id, false, &posts);
    TEST_ASSERT_EQUAL(1, (int)posts.count);
    int64_t post_id = posts.items[0].id;
    bunny_db_post_list_free(&posts);

    if (out_search_id) {
        *out_search_id = search_id;
    }
    return post_id;
}

static int64_t seed_inkbunny_post(void)
{
    char *login_fixture = read_fixture("inkbunny_login_success.json");
    char *search_fixture = read_fixture("inkbunny_search_response.json");
    TEST_ASSERT_NOT_NULL(login_fixture);
    TEST_ASSERT_NOT_NULL(search_fixture);
    g_inkbunny_state.bodies[0] = login_fixture;
    g_inkbunny_state.bodies[1] = search_fixture;
    g_inkbunny_state.count = 2;

    int64_t search_id = 0;
    bunny_core_search_create(g_core, BUNNY_DB_SITE_INKBUNNY, "tribute", "tribute", 24, &search_id);

    bunny_core_sync_stats_t sync_stats;
    bunny_core_sync_due_searches(g_core, &sync_stats);
    TEST_ASSERT_EQUAL(1, sync_stats.posts_upserted);

    bunny_db_post_list_t posts;
    bunny_core_search_list_posts(g_core, search_id, false, &posts);
    TEST_ASSERT_EQUAL(1, (int)posts.count);
    int64_t post_id = posts.items[0].id;
    bunny_db_post_list_free(&posts);

    /* Reset the e621/inkbunny fake state so the seeding calls don't leak
     * into the action being tested below. */
    memset(&g_inkbunny_state, 0, sizeof(g_inkbunny_state));
    g_inkbunny_transport.user_data = &g_inkbunny_state;
    free(login_fixture);
    free(search_fixture);

    return post_id;
}

void test_queue_e621_favorite_add_succeeds_and_updates_mirror(void)
{
    char *fixture = read_fixture("e621_posts_search.json");
    g_e621_state.bodies[0] = fixture;
    g_e621_state.statuses[0] = 200;
    g_e621_state.count = 1;
    int64_t search_id = 0;
    int64_t post_id = seed_e621_post(&search_id);
    free(fixture);

    memset(&g_e621_state, 0, sizeof(g_e621_state));
    g_e621_state.statuses[0] = 200; /* favorites.json POST response -- status only, no body needed */
    g_e621_state.count = 1;

    bunny_core_result_t result = bunny_core_queue_favorite_add(g_core, post_id, -1);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);

    bunny_core_queue_stats_t stats;
    result = bunny_core_process_queue(g_core, &stats);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(1, stats.actions_processed);
    TEST_ASSERT_EQUAL(1, stats.actions_succeeded);
    TEST_ASSERT_EQUAL(0, stats.actions_failed);

    bunny_db_post_list_t posts;
    bunny_core_search_list_posts(g_core, search_id, false, &posts);
    TEST_ASSERT_EQUAL(1, (int)posts.count);
    TEST_ASSERT_TRUE(posts.items[0].is_favorited);
    bunny_db_post_list_free(&posts);
}

void test_queue_e621_vote_succeeds(void)
{
    char *fixture = read_fixture("e621_posts_search.json");
    g_e621_state.bodies[0] = fixture;
    g_e621_state.count = 1;
    int64_t post_id = seed_e621_post(NULL);
    free(fixture);

    memset(&g_e621_state, 0, sizeof(g_e621_state));
    g_e621_state.statuses[0] = 200;
    g_e621_state.count = 1;

    bunny_core_result_t result = bunny_core_queue_vote(g_core, post_id, 1, false);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);

    bunny_core_queue_stats_t stats;
    result = bunny_core_process_queue(g_core, &stats);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(1, stats.actions_succeeded);
}

void test_queue_e621_comment_succeeds(void)
{
    char *fixture = read_fixture("e621_posts_search.json");
    g_e621_state.bodies[0] = fixture;
    g_e621_state.count = 1;
    int64_t post_id = seed_e621_post(NULL);
    free(fixture);

    memset(&g_e621_state, 0, sizeof(g_e621_state));
    g_e621_state.statuses[0] = 200;
    g_e621_state.bodies[0] = "{\"id\":1,\"post_id\":1,\"creator_name\":\"tester\",\"body\":\"nice\",\"created_at\":\"2026-01-01T00:00:00Z\"}";
    g_e621_state.count = 1;

    bunny_core_result_t result = bunny_core_queue_comment(g_core, post_id, "nice post!", false);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);

    bunny_core_queue_stats_t stats;
    result = bunny_core_process_queue(g_core, &stats);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(1, stats.actions_succeeded);
}

void test_queue_e621_action_failure_marks_failed_not_retried(void)
{
    char *fixture = read_fixture("e621_posts_search.json");
    g_e621_state.bodies[0] = fixture;
    g_e621_state.count = 1;
    int64_t post_id = seed_e621_post(NULL);
    free(fixture);

    memset(&g_e621_state, 0, sizeof(g_e621_state));
    g_e621_state.statuses[0] = 500; /* server error -> E621_ERR_SERVER */
    g_e621_state.count = 1;

    bunny_core_queue_favorite_add(g_core, post_id, -1);

    bunny_core_queue_stats_t stats;
    bunny_core_result_t result = bunny_core_process_queue(g_core, &stats);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(1, stats.actions_processed);
    TEST_ASSERT_EQUAL(0, stats.actions_succeeded);
    TEST_ASSERT_EQUAL(1, stats.actions_failed);

    /* A failed action isn't pending anymore -- a second pass must not
     * re-attempt it (no retry scheduling in M4). */
    bunny_core_result_t second_result = bunny_core_process_queue(g_core, &stats);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, second_result);
    TEST_ASSERT_EQUAL(0, stats.actions_processed);
}

void test_queue_inkbunny_vote_always_invalid(void)
{
    int64_t post_id = seed_inkbunny_post();

    bunny_core_queue_vote(g_core, post_id, 1, false);

    bunny_core_queue_stats_t stats;
    bunny_core_result_t result = bunny_core_process_queue(g_core, &stats);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(1, stats.actions_processed);
    TEST_ASSERT_EQUAL(0, stats.actions_succeeded);
    TEST_ASSERT_EQUAL(1, stats.actions_failed);
}

void test_queue_inkbunny_favorite_without_account_fails(void)
{
    int64_t post_id = seed_inkbunny_post();

    /* No Inkbunny account was ever configured on this core -- favoriting
     * requires a real login (no guest mode), so this must fail without
     * making any further network call. */
    bunny_core_queue_favorite_add(g_core, post_id, 1);

    bunny_core_queue_stats_t stats;
    bunny_core_result_t result = bunny_core_process_queue(g_core, &stats);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(1, stats.actions_processed);
    TEST_ASSERT_EQUAL(0, stats.actions_succeeded);
    TEST_ASSERT_EQUAL(1, stats.actions_failed);
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_queue_e621_favorite_add_succeeds_and_updates_mirror);
    RUN_TEST(test_queue_e621_vote_succeeds);
    RUN_TEST(test_queue_e621_comment_succeeds);
    RUN_TEST(test_queue_e621_action_failure_marks_failed_not_retried);
    RUN_TEST(test_queue_inkbunny_vote_always_invalid);
    RUN_TEST(test_queue_inkbunny_favorite_without_account_fails);
    return UNITY_END();
}
