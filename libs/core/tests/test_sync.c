#include "unity.h"

#include <stdbool.h>
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

/* Copied out immediately (rather than keeping the request's own header
 * pointers) since the e621 client -- and the buffer its User-Agent header
 * value points into -- is destroyed before the test gets a chance to
 * inspect the captured value. */
static char g_captured_user_agent[256];
static bool g_captured_user_agent_found;

static char g_captured_url[512];

static bunny_http_result_t capturing_fake_send(void *user_data, const bunny_http_request_t *request, bunny_http_response_t *out_response)
{
    for (size_t i = 0; i < request->header_count; i++) {
        if (strcmp(request->headers[i].name, "User-Agent") == 0) {
            snprintf(g_captured_user_agent, sizeof(g_captured_user_agent), "%s", request->headers[i].value);
            g_captured_user_agent_found = true;
        }
    }
    snprintf(g_captured_url, sizeof(g_captured_url), "%s", request->url);
    return fake_send(user_data, request, out_response);
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

/* Mirrors BUNNY_CORE_SYNC_E621_PAGE_LIMIT in sync.c -- not part of the public
 * API, so this needs to be kept in sync by hand if that constant ever
 * changes. */
#define TEST_E621_FULL_PAGE_SIZE 320

/* Builds a minimal e621 posts-search response with `count` posts (ids
 * starting at `first_id`), so a "full page triggers another request" test
 * doesn't need a literal 320-post fixture file checked into the repo. */
static char *build_e621_posts_page_json(int count, int first_id)
{
    size_t capacity = 1024 + (size_t)count * 700;
    char *buf = malloc(capacity);
    if (!buf) {
        return NULL;
    }
    size_t len = (size_t)snprintf(buf, capacity, "{\"posts\":[");
    for (int i = 0; i < count; i++) {
        int id = first_id + i;
        len += (size_t)snprintf(buf + len, capacity - len,
                                "%s{\"id\":%d,\"created_at\":\"2024-01-01T00:00:00.000-05:00\","
                                "\"file\":{\"width\":100,\"height\":100,\"ext\":\"png\",\"size\":1000,\"md5\":\"aaa\",\"url\":\"https://static1.e621.net/data/%d.png\"},"
                                "\"preview\":{\"width\":50,\"height\":50,\"url\":\"https://static1.e621.net/data/preview/%d.png\"},"
                                "\"sample\":{\"has\":false},\"score\":{\"up\":1,\"down\":0,\"total\":1},"
                                "\"tags\":{\"general\":[\"one\"],\"species\":[],\"character\":[],\"copyright\":[],\"artist\":[\"someartist\"],\"invalid\":[],\"lore\":[],\"meta\":[]},"
                                "\"rating\":\"s\",\"fav_count\":1,\"sources\":[],\"description\":\"a test post\",\"comment_count\":0,\"is_favorited\":false,\"pools\":[]}",
                                i == 0 ? "" : ",", id, id, id);
    }
    len += (size_t)snprintf(buf + len, capacity - len, "]}");
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
    TEST_ASSERT_EQUAL(1, posts.items[0].score_up);
    TEST_ASSERT_EQUAL(0, posts.items[0].score_down);
    bunny_db_post_list_free(&posts);

    free(fixture);
}

void test_sync_e621_search_upserts_post_tag_categories(void)
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

    bunny_db_post_list_t posts;
    result = bunny_core_search_list_posts(g_core, search_id, false, &posts);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(1, (int)posts.count);
    int64_t post_id = posts.items[0].id;
    bunny_db_post_list_free(&posts);

    bunny_db_post_tag_list_t tags;
    result = bunny_core_post_get_tags_by_category(g_core, post_id, &tags);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(2, (int)tags.count);
    for (size_t i = 0; i < tags.count; i++) {
        if (strcmp(tags.items[i].name, "one") == 0) {
            TEST_ASSERT_EQUAL_STRING("general", tags.items[i].category);
        } else if (strcmp(tags.items[i].name, "someartist") == 0) {
            TEST_ASSERT_EQUAL_STRING("artist", tags.items[i].category);
        } else {
            TEST_FAIL_MESSAGE("unexpected tag name");
        }
    }
    bunny_db_post_tag_list_free(&tags);

    free(fixture);
}

void test_sync_e621_search_upserts_post_sources(void)
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

    bunny_db_post_list_t posts;
    result = bunny_core_search_list_posts(g_core, search_id, false, &posts);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(1, (int)posts.count);
    int64_t post_id = posts.items[0].id;
    bunny_db_post_list_free(&posts);

    bunny_db_string_list_t sources;
    result = bunny_core_post_get_sources(g_core, post_id, &sources);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(1, (int)sources.count);
    TEST_ASSERT_EQUAL_STRING("https://example.com/original", sources.items[0]);
    bunny_db_string_list_free(&sources);

    free(fixture);
}

void test_sync_e621_search_upserts_post_relationships_and_pools(void)
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

    bunny_db_post_list_t posts;
    result = bunny_core_search_list_posts(g_core, search_id, false, &posts);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(1, (int)posts.count);
    int64_t post_id = posts.items[0].id;
    bunny_db_post_list_free(&posts);

    bunny_db_post_relationships_t relationships;
    result = bunny_core_post_get_relationships(g_core, post_id, &relationships);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_TRUE(relationships.has_parent);
    TEST_ASSERT_EQUAL(999, relationships.parent_external_id);
    TEST_ASSERT_TRUE(relationships.has_active_children);
    TEST_ASSERT_EQUAL(2, relationships.children.count);
    bunny_db_post_relationships_free(&relationships);

    bunny_db_int64_list_t pool_ids;
    result = bunny_core_post_get_pool_ids(g_core, post_id, &pool_ids);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(2, pool_ids.count);
    bunny_db_int64_list_free(&pool_ids);

    free(fixture);
}

void test_fetch_and_cache_post_upserts_live_e621_post(void)
{
    char *fixture1 = read_fixture("e621_post_single.json");
    char *fixture2 = read_fixture("e621_post_single.json");
    TEST_ASSERT_NOT_NULL(fixture1);
    TEST_ASSERT_NOT_NULL(fixture2);
    g_e621_state.bodies[0] = fixture1;
    g_e621_state.bodies[1] = fixture2;
    g_e621_state.body_count = 2;

    int64_t post_id = 0;
    bunny_core_result_t result = bunny_core_fetch_and_cache_post(g_core, BUNNY_DB_SITE_E621, 42, &post_id);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_TRUE(post_id > 0);

    bunny_db_post_tag_list_t tags;
    result = bunny_core_post_get_tags_by_category(g_core, post_id, &tags);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(2, (int)tags.count);
    bunny_db_post_tag_list_free(&tags);

    /* Fetching again (e.g. a second chip tap) must upsert in place, not
     * duplicate the post. */
    int64_t second_id = 0;
    result = bunny_core_fetch_and_cache_post(g_core, BUNNY_DB_SITE_E621, 42, &second_id);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(post_id, second_id);

    free(fixture1);
    free(fixture2);
}

void test_fetch_and_cache_post_upserts_live_inkbunny_submission(void)
{
    /* The e621 counterpart above was this function's only test coverage
     * until now -- this is the first test to exercise the Inkbunny branch.
     * Also notable: unlike a search sync, a full inkbunny_get_submission
     * response *does* include a "files" array (see architecture.md's note on
     * this gap), so this is the one sync path that can actually populate
     * file_url/file_md5/width/height/sample_url for an Inkbunny post -- all
     * of which stay NULL/0 from a search sync alone. */
    char *login_fixture = read_fixture("inkbunny_login_success.json");
    char *submission_fixture = read_fixture("inkbunny_submission_full.json");
    TEST_ASSERT_NOT_NULL(login_fixture);
    TEST_ASSERT_NOT_NULL(submission_fixture);
    g_inkbunny_state.bodies[0] = login_fixture;
    g_inkbunny_state.bodies[1] = submission_fixture;
    g_inkbunny_state.body_count = 2;

    int64_t post_id = 0;
    bunny_core_result_t result = bunny_core_fetch_and_cache_post(g_core, BUNNY_DB_SITE_INKBUNNY, 3955918, &post_id);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_TRUE(post_id > 0);
    /* Upsert-in-place idempotency is already covered by the e621 case above
     * (both go through the same bunny_db_post_upsert) -- a second call here
     * would need its own guest-login fixture, since bunny_core_build_
     * inkbunny_client logs in fresh every call, unlike e621's anonymous GETs. */

    free(login_fixture);
    free(submission_fixture);
}

void test_list_comments_returns_live_e621_comments(void)
{
    char *post_fixture = read_fixture("e621_post_single.json");
    char *comments_fixture = read_fixture("e621_comments_list.json");
    TEST_ASSERT_NOT_NULL(post_fixture);
    TEST_ASSERT_NOT_NULL(comments_fixture);
    g_e621_state.bodies[0] = post_fixture;
    g_e621_state.bodies[1] = comments_fixture;
    g_e621_state.body_count = 2;

    int64_t post_id = 0;
    bunny_core_result_t result = bunny_core_fetch_and_cache_post(g_core, BUNNY_DB_SITE_E621, 42, &post_id);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);

    bunny_core_comment_list_t comments;
    result = bunny_core_list_comments(g_core, post_id, &comments);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(2, (int)comments.count);
    TEST_ASSERT_EQUAL_STRING("someone", comments.items[0].creator_name);
    TEST_ASSERT_EQUAL_STRING("Nice pic!", comments.items[0].body);
    TEST_ASSERT_EQUAL_STRING("another", comments.items[1].creator_name);
    bunny_core_comment_list_free(&comments);

    free(post_fixture);
    free(comments_fixture);
}

void test_list_comments_rejects_inkbunny_posts(void)
{
    char *login_fixture = read_fixture("inkbunny_login_success.json");
    char *submission_fixture = read_fixture("inkbunny_submission_full.json");
    TEST_ASSERT_NOT_NULL(login_fixture);
    TEST_ASSERT_NOT_NULL(submission_fixture);
    g_inkbunny_state.bodies[0] = login_fixture;
    g_inkbunny_state.bodies[1] = submission_fixture;
    g_inkbunny_state.body_count = 2;

    int64_t post_id = 0;
    bunny_core_result_t result = bunny_core_fetch_and_cache_post(g_core, BUNNY_DB_SITE_INKBUNNY, 3955918, &post_id);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);

    /* No further fixture bodies queued -- rejecting a non-e621 post must
     * happen before any HTTP call is made. */
    bunny_core_comment_list_t comments;
    result = bunny_core_list_comments(g_core, post_id, &comments);
    TEST_ASSERT_EQUAL(BUNNY_CORE_ERR_SITE, result);

    free(login_fixture);
    free(submission_fixture);
}

void test_fetch_pool_returns_live_pool_info(void)
{
    char *fixture = read_fixture("e621_pool_single.json");
    TEST_ASSERT_NOT_NULL(fixture);
    g_e621_state.bodies[0] = fixture;
    g_e621_state.body_count = 1;

    bunny_core_pool_info_t info;
    bunny_core_result_t result = bunny_core_fetch_pool(g_core, 5, &info);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(5, info.id);
    TEST_ASSERT_EQUAL_STRING("a_test_pool", info.name);
    TEST_ASSERT_EQUAL(3, info.post_count);
    bunny_core_pool_info_free(&info);

    free(fixture);
}

void test_preview_search_upserts_posts_without_creating_a_search(void)
{
    char *fixture = read_fixture("e621_posts_search.json");
    TEST_ASSERT_NOT_NULL(fixture);
    g_e621_state.bodies[0] = fixture;
    g_e621_state.body_count = 1;

    bunny_db_post_list_t posts;
    bunny_core_result_t result = bunny_core_preview_search(g_core, BUNNY_DB_SITE_E621, "wolf", 1, &posts);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(1, (int)posts.count);
    TEST_ASSERT_EQUAL(1, posts.items[0].external_id);
    TEST_ASSERT_EQUAL_STRING("someartist", posts.items[0].artist);
    bunny_db_post_list_free(&posts);

    /* The whole point of a preview search -- unlike bunny_core_search_create
     * + sync, it must never create a searches row. */
    bunny_db_search_list_t searches;
    result = bunny_core_search_list(g_core, &searches);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(0, (int)searches.count);
    bunny_db_search_list_free(&searches);

    free(fixture);
}

void test_preview_search_requests_the_given_e621_page(void)
{
    g_e621_transport.send = capturing_fake_send;

    char *fixture = read_fixture("e621_posts_search.json");
    TEST_ASSERT_NOT_NULL(fixture);
    g_e621_state.bodies[0] = fixture;
    g_e621_state.body_count = 1;

    bunny_db_post_list_t posts;
    bunny_core_result_t result = bunny_core_preview_search(g_core, BUNNY_DB_SITE_E621, "wolf", 3, &posts);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    bunny_db_post_list_free(&posts);
    free(fixture);

    TEST_ASSERT_NOT_NULL(strstr(g_captured_url, "page=3"));
}

void test_preview_search_requests_the_given_inkbunny_page(void)
{
    g_inkbunny_transport.send = capturing_fake_send;

    char *login_fixture = read_fixture("inkbunny_login_success.json");
    char *search_fixture = read_fixture("inkbunny_search_response.json");
    TEST_ASSERT_NOT_NULL(login_fixture);
    TEST_ASSERT_NOT_NULL(search_fixture);
    g_inkbunny_state.bodies[0] = login_fixture;
    g_inkbunny_state.bodies[1] = search_fixture;
    g_inkbunny_state.body_count = 2;

    bunny_db_post_list_t posts;
    bunny_core_result_t result = bunny_core_preview_search(g_core, BUNNY_DB_SITE_INKBUNNY, "tribute", 2, &posts);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    bunny_db_post_list_free(&posts);
    free(login_fixture);
    free(search_fixture);

    TEST_ASSERT_NOT_NULL(strstr(g_captured_url, "page=2"));
}

void test_preview_search_rejects_a_page_below_one(void)
{
    bunny_db_post_list_t posts;
    bunny_core_result_t result = bunny_core_preview_search(g_core, BUNNY_DB_SITE_E621, "wolf", 0, &posts);
    TEST_ASSERT_EQUAL(BUNNY_CORE_ERR_INVALID_ARG, result);
}

void test_e621_requests_use_the_bare_user_agent_without_an_account(void)
{
    g_captured_user_agent_found = false;
    g_e621_transport.send = capturing_fake_send;

    char *fixture = read_fixture("e621_posts_search.json");
    TEST_ASSERT_NOT_NULL(fixture);
    g_e621_state.bodies[0] = fixture;
    g_e621_state.body_count = 1;

    bunny_db_post_list_t posts;
    bunny_core_result_t result = bunny_core_preview_search(g_core, BUNNY_DB_SITE_E621, "wolf", 1, &posts);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    bunny_db_post_list_free(&posts);
    free(fixture);

    TEST_ASSERT_TRUE(g_captured_user_agent_found);
    TEST_ASSERT_EQUAL_STRING("bunny-tests/1.0 (unit tests)", g_captured_user_agent);
}

void test_e621_requests_include_the_configured_username_in_the_user_agent(void)
{
    bunny_core_account_set(g_core, BUNNY_DB_SITE_E621, "someuser", "someapikey");
    g_captured_user_agent_found = false;
    g_e621_transport.send = capturing_fake_send;

    char *fixture = read_fixture("e621_posts_search.json");
    TEST_ASSERT_NOT_NULL(fixture);
    g_e621_state.bodies[0] = fixture;
    g_e621_state.body_count = 1;

    bunny_db_post_list_t posts;
    bunny_core_result_t result = bunny_core_preview_search(g_core, BUNNY_DB_SITE_E621, "wolf", 1, &posts);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    bunny_db_post_list_free(&posts);
    free(fixture);

    TEST_ASSERT_TRUE(g_captured_user_agent_found);
    TEST_ASSERT_EQUAL_STRING("bunny-tests/1.0 (unit tests) (by someuser on e621)", g_captured_user_agent);
}

void test_sync_e621_search_upserts_post_sample_url(void)
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

    bunny_db_post_list_t posts;
    result = bunny_core_search_list_posts(g_core, search_id, false, &posts);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(1, (int)posts.count);
    TEST_ASSERT_EQUAL_STRING("https://static1.e621.net/data/sample/1.png", posts.items[0].sample_url);
    bunny_db_post_list_free(&posts);

    free(fixture);
}

void test_sync_e621_search_fetches_a_second_page_when_the_first_is_full(void)
{
    char *page1 = build_e621_posts_page_json(TEST_E621_FULL_PAGE_SIZE, 1);
    char *page2 = build_e621_posts_page_json(5, TEST_E621_FULL_PAGE_SIZE + 1);
    TEST_ASSERT_NOT_NULL(page1);
    TEST_ASSERT_NOT_NULL(page2);
    g_e621_state.bodies[0] = page1;
    g_e621_state.bodies[1] = page2;
    g_e621_state.body_count = 2;

    int64_t search_id = 0;
    bunny_core_search_create(g_core, BUNNY_DB_SITE_E621, "wolves", "wolf", 24, &search_id);

    bunny_core_sync_stats_t stats;
    bunny_core_result_t result = bunny_core_sync_due_searches(g_core, &stats);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(1, stats.searches_synced);
    TEST_ASSERT_EQUAL(TEST_E621_FULL_PAGE_SIZE + 5, stats.posts_upserted);
    /* Exactly 2 requests -- a short second page must stop the loop rather
     * than probing for a third. */
    TEST_ASSERT_EQUAL(2, (int)g_e621_state.next_index);

    free(page1);
    free(page2);
}

void test_sync_e621_search_stops_after_a_single_short_page(void)
{
    char *fixture = read_fixture("e621_posts_search.json");
    TEST_ASSERT_NOT_NULL(fixture);
    g_e621_state.bodies[0] = fixture;
    g_e621_state.body_count = 1;

    int64_t search_id = 0;
    bunny_core_search_create(g_core, BUNNY_DB_SITE_E621, "wolves", "wolf", 24, &search_id);

    bunny_core_sync_stats_t stats;
    bunny_core_result_t result = bunny_core_sync_due_searches(g_core, &stats);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(1, stats.searches_synced);
    TEST_ASSERT_EQUAL(1, (int)g_e621_state.next_index);

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
    /* With no total-results/total-pages signal in inkbunny_submission_list_t,
     * the pagination loop (M8.5.1) always probes one page past the last
     * non-empty one to confirm there's nothing more. */
    char *empty_fixture = read_fixture("inkbunny_search_response_empty.json");
    TEST_ASSERT_NOT_NULL(login_fixture);
    TEST_ASSERT_NOT_NULL(search_fixture);
    TEST_ASSERT_NOT_NULL(empty_fixture);
    g_inkbunny_state.bodies[0] = login_fixture;
    g_inkbunny_state.bodies[1] = search_fixture;
    g_inkbunny_state.bodies[2] = empty_fixture;
    g_inkbunny_state.body_count = 3;

    int64_t search_id = 0;
    bunny_core_result_t result = bunny_core_search_create(g_core, BUNNY_DB_SITE_INKBUNNY, "tribute", "tribute", 24, &search_id);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);

    bunny_core_sync_stats_t stats;
    result = bunny_core_sync_due_searches(g_core, &stats);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(1, stats.searches_synced);
    TEST_ASSERT_EQUAL(1, stats.posts_upserted);
    /* login + page 1 (1 result) + page 2 (empty, stops the loop) -- never a
     * page 3. */
    TEST_ASSERT_EQUAL(3, (int)g_inkbunny_state.next_index);

    bunny_db_post_list_t posts;
    result = bunny_core_search_list_posts(g_core, search_id, false, &posts);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(1, (int)posts.count);
    TEST_ASSERT_EQUAL(3955918, posts.items[0].external_id);
    TEST_ASSERT_EQUAL_STRING("OvineSatanOMG", posts.items[0].artist);
    TEST_ASSERT_EQUAL_STRING("Thank you, Digimon Beatbreak", posts.items[0].title);
    /* Inkbunny's search endpoint doesn't return a "files" array at all (see
     * architecture.md's note on description/keywords having the same gap) --
     * sample_url (like file_url/file_md5/width/height) is only ever
     * populated via a full inkbunny_get_submission fetch, not a search sync. */
    TEST_ASSERT_NULL(posts.items[0].sample_url);
    int64_t post_id = posts.items[0].id;
    bunny_db_post_list_free(&posts);

    /* Inkbunny keywords have no category concept at all -- unlike e621 tags
     * (see test_sync_e621_search_upserts_post_tag_categories above), the
     * category comes back NULL, not some default/fallback string. */
    bunny_db_post_tag_list_t tags;
    result = bunny_core_post_get_tags_by_category(g_core, post_id, &tags);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(1, (int)tags.count);
    TEST_ASSERT_EQUAL_STRING("tribute", tags.items[0].name);
    TEST_ASSERT_NULL(tags.items[0].category);
    bunny_db_post_tag_list_free(&tags);

    free(login_fixture);
    free(search_fixture);
    free(empty_fixture);
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
    RUN_TEST(test_sync_e621_search_upserts_post_tag_categories);
    RUN_TEST(test_sync_e621_search_upserts_post_sources);
    RUN_TEST(test_sync_e621_search_upserts_post_sample_url);
    RUN_TEST(test_sync_e621_search_upserts_post_relationships_and_pools);
    RUN_TEST(test_fetch_and_cache_post_upserts_live_e621_post);
    RUN_TEST(test_fetch_and_cache_post_upserts_live_inkbunny_submission);
    RUN_TEST(test_list_comments_returns_live_e621_comments);
    RUN_TEST(test_list_comments_rejects_inkbunny_posts);
    RUN_TEST(test_fetch_pool_returns_live_pool_info);
    RUN_TEST(test_preview_search_upserts_posts_without_creating_a_search);
    RUN_TEST(test_preview_search_requests_the_given_e621_page);
    RUN_TEST(test_preview_search_requests_the_given_inkbunny_page);
    RUN_TEST(test_preview_search_rejects_a_page_below_one);
    RUN_TEST(test_e621_requests_use_the_bare_user_agent_without_an_account);
    RUN_TEST(test_e621_requests_include_the_configured_username_in_the_user_agent);
    RUN_TEST(test_sync_e621_search_fetches_a_second_page_when_the_first_is_full);
    RUN_TEST(test_sync_e621_search_stops_after_a_single_short_page);
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
