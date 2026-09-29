#include "unity.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bunny_core/core.h"

typedef struct
{
    const char *bodies[4];
    size_t body_count;
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
    const char *body = state->next_index < state->body_count ? state->bodies[state->next_index] : "";
    state->next_index++;
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
    /* 0 means "use each library's built-in ~0.5s default", which would slow
     * every test down noticeably -- use a negligible delay instead. */
    config.min_request_interval_sec = 0.001;

    bunny_core_result_t result = bunny_core_open(&config, &g_core);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
}

void tearDown(void)
{
    bunny_core_close(g_core);
    g_core = NULL;
}

void test_sync_e621_search_upserts_post(void)
{
    char *fixture = read_fixture("e621_posts_search.json");
    TEST_ASSERT_NOT_NULL(fixture);
    g_e621_state.bodies[0] = fixture;
    g_e621_state.body_count = 1;

    int64_t search_id = 0;
    bunny_core_result_t result = bunny_core_search_create(g_core, BUNNY_DB_SITE_E621, "wolves", "wolf", 24, &search_id);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);

    bunny_core_sync_stats_t stats;
    result = bunny_core_sync_due_searches(g_core, &stats);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(1, stats.searches_checked);
    TEST_ASSERT_EQUAL(1, stats.searches_synced);
    TEST_ASSERT_EQUAL(1, stats.posts_upserted);

    bunny_db_post_list_t posts;
    result = bunny_core_search_list_posts(g_core, search_id, false, &posts);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(1, (int)posts.count);
    TEST_ASSERT_EQUAL(1, posts.items[0].external_id);
    TEST_ASSERT_EQUAL_STRING("someartist", posts.items[0].artist);
    TEST_ASSERT_EQUAL_STRING("s", posts.items[0].rating);
    TEST_ASSERT_EQUAL_STRING("aaa", posts.items[0].file_md5);
    TEST_ASSERT_EQUAL(1, posts.items[0].score);
    bunny_db_post_list_free(&posts);

    free(fixture);
}

void test_tag_autocomplete_finds_tags_from_synced_posts(void)
{
    char *fixture = read_fixture("e621_posts_search.json");
    TEST_ASSERT_NOT_NULL(fixture);
    g_e621_state.bodies[0] = fixture;
    g_e621_state.body_count = 1;

    int64_t search_id = 0;
    bunny_core_search_create(g_core, BUNNY_DB_SITE_E621, "wolves", "wolf", 24, &search_id);
    bunny_core_sync_due_searches(g_core, NULL);

    bunny_db_tag_stat_list_t tags;
    bunny_core_result_t result = bunny_core_tag_autocomplete(g_core, BUNNY_DB_SITE_E621, "on", 10, &tags);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(1, (int)tags.count);
    TEST_ASSERT_EQUAL_STRING("one", tags.items[0].name);
    bunny_db_tag_stat_list_free(&tags);

    free(fixture);
}

void test_tag_autocomplete_returns_empty_list_for_no_match(void)
{
    bunny_db_tag_stat_list_t tags;
    bunny_core_result_t result = bunny_core_tag_autocomplete(g_core, BUNNY_DB_SITE_E621, "nonexistent", 10, &tags);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(0, (int)tags.count);
    bunny_db_tag_stat_list_free(&tags);
}

void test_mark_seen_flips_is_seen_on_a_synced_post(void)
{
    char *fixture = read_fixture("e621_posts_search.json");
    TEST_ASSERT_NOT_NULL(fixture);
    g_e621_state.bodies[0] = fixture;
    g_e621_state.body_count = 1;

    int64_t search_id = 0;
    bunny_core_search_create(g_core, BUNNY_DB_SITE_E621, "wolves", "wolf", 24, &search_id);
    bunny_core_sync_due_searches(g_core, NULL);

    bunny_db_post_list_t posts;
    bunny_core_search_list_posts(g_core, search_id, false, &posts);
    TEST_ASSERT_EQUAL(1, (int)posts.count);
    TEST_ASSERT_FALSE(posts.items[0].is_seen);
    int64_t post_id = posts.items[0].id;
    bunny_db_post_list_free(&posts);

    bunny_core_result_t result = bunny_core_post_mark_seen(g_core, post_id);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);

    bunny_core_search_list_posts(g_core, search_id, false, &posts);
    TEST_ASSERT_TRUE(posts.items[0].is_seen);
    bunny_db_post_list_free(&posts);

    free(fixture);
}

void test_mark_seen_rejects_a_nonexistent_post(void)
{
    /* seen_posts.post_id REFERENCES posts(id) -- a nonexistent post_id is a
     * foreign-key violation, which bunny_core_map_db_result treats as bad
     * caller input (BUNNY_CORE_ERR_INVALID_ARG), not BUNNY_CORE_ERR_NOT_FOUND
     * (see libs/core/src/internal.h). */
    bunny_core_result_t result = bunny_core_post_mark_seen(g_core, 999);
    TEST_ASSERT_EQUAL(BUNNY_CORE_ERR_INVALID_ARG, result);
}

void test_sync_inkbunny_search_upserts_post(void)
{
    char *login_fixture = read_fixture("inkbunny_login_success.json");
    char *search_fixture = read_fixture("inkbunny_search_response.json");
    TEST_ASSERT_NOT_NULL(login_fixture);
    TEST_ASSERT_NOT_NULL(search_fixture);
    g_inkbunny_state.bodies[0] = login_fixture;
    g_inkbunny_state.bodies[1] = search_fixture;
    g_inkbunny_state.body_count = 2;

    int64_t search_id = 0;
    bunny_core_result_t result = bunny_core_search_create(g_core, BUNNY_DB_SITE_INKBUNNY, "tribute", "tribute", 24, &search_id);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);

    bunny_core_sync_stats_t stats;
    result = bunny_core_sync_due_searches(g_core, &stats);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(1, stats.searches_synced);
    TEST_ASSERT_EQUAL(1, stats.posts_upserted);

    bunny_db_post_list_t posts;
    result = bunny_core_search_list_posts(g_core, search_id, false, &posts);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(1, (int)posts.count);
    TEST_ASSERT_EQUAL(3955918, posts.items[0].external_id);
    TEST_ASSERT_EQUAL_STRING("OvineSatanOMG", posts.items[0].artist);
    TEST_ASSERT_EQUAL_STRING("Thank you, Digimon Beatbreak", posts.items[0].title);
    bunny_db_post_list_free(&posts);

    free(login_fixture);
    free(search_fixture);
}

void test_sync_skips_search_not_due_yet(void)
{
    char *fixture = read_fixture("e621_posts_search.json");
    TEST_ASSERT_NOT_NULL(fixture);
    g_e621_state.bodies[0] = fixture;
    g_e621_state.body_count = 1;

    int64_t search_id = 0;
    bunny_core_search_create(g_core, BUNNY_DB_SITE_E621, "wolves", "wolf", 24, &search_id);

    bunny_core_sync_stats_t stats;
    bunny_core_sync_due_searches(g_core, &stats);
    TEST_ASSERT_EQUAL(1, stats.searches_synced);

    /* Second call immediately after: the search was just touched, so with a
     * 24h interval it isn't due again -- must not re-fetch. */
    bunny_core_result_t result = bunny_core_sync_due_searches(g_core, &stats);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(1, stats.searches_checked);
    TEST_ASSERT_EQUAL(0, stats.searches_synced);
    TEST_ASSERT_EQUAL(0, stats.posts_upserted);

    free(fixture);
}

void test_verify_e621_accepts_valid_credentials(void)
{
    char *fixture = read_fixture("e621_posts_search.json");
    TEST_ASSERT_NOT_NULL(fixture);
    g_e621_state.bodies[0] = fixture;
    g_e621_state.body_count = 1;

    bunny_core_result_t result = bunny_core_account_verify(g_core, BUNNY_DB_SITE_E621, "someuser", "someapikey");
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);

    free(fixture);
}

void test_verify_e621_rejects_when_site_call_fails(void)
{
    /* No fixture queued -- fake_send returns an empty 200 body, which fails
     * to parse as e621's expected JSON shape, exercising the same
     * any-site-failure-maps-to-ERR_SITE path a real 401 would. */
    bunny_core_result_t result = bunny_core_account_verify(g_core, BUNNY_DB_SITE_E621, "someuser", "badkey");
    TEST_ASSERT_EQUAL(BUNNY_CORE_ERR_SITE, result);
}

void test_verify_inkbunny_accepts_valid_credentials(void)
{
    char *fixture = read_fixture("inkbunny_login_success.json");
    TEST_ASSERT_NOT_NULL(fixture);
    g_inkbunny_state.bodies[0] = fixture;
    g_inkbunny_state.body_count = 1;

    bunny_core_result_t result = bunny_core_account_verify(g_core, BUNNY_DB_SITE_INKBUNNY, "someuser", "somepassword");
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);

    free(fixture);
}

void test_verify_inkbunny_rejects_invalid_credentials(void)
{
    /* Inkbunny reports auth failure as an error_code/error_message body
     * under HTTP 200 (see docs/architecture.md's Inkbunny API constraints),
     * not a non-2xx status -- this is the real shape a bad login returns. */
    char *fixture = read_fixture("inkbunny_login_failure.json");
    TEST_ASSERT_NOT_NULL(fixture);
    g_inkbunny_state.bodies[0] = fixture;
    g_inkbunny_state.body_count = 1;

    bunny_core_result_t result = bunny_core_account_verify(g_core, BUNNY_DB_SITE_INKBUNNY, "someuser", "badpassword");
    TEST_ASSERT_EQUAL(BUNNY_CORE_ERR_SITE, result);

    free(fixture);
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_sync_e621_search_upserts_post);
    RUN_TEST(test_tag_autocomplete_finds_tags_from_synced_posts);
    RUN_TEST(test_tag_autocomplete_returns_empty_list_for_no_match);
    RUN_TEST(test_mark_seen_flips_is_seen_on_a_synced_post);
    RUN_TEST(test_mark_seen_rejects_a_nonexistent_post);
    RUN_TEST(test_sync_inkbunny_search_upserts_post);
    RUN_TEST(test_sync_skips_search_not_due_yet);
    RUN_TEST(test_verify_e621_accepts_valid_credentials);
    RUN_TEST(test_verify_e621_rejects_when_site_call_fails);
    RUN_TEST(test_verify_inkbunny_accepts_valid_credentials);
    RUN_TEST(test_verify_inkbunny_rejects_invalid_credentials);
    return UNITY_END();
}
