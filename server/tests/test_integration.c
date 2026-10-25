#include "unity.h"

#include <bunny_common/http.h>
#include <curl/curl.h>

#include <dirent.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include "app.h"

#define TEST_PORT 18543

static const char *E621_FIXTURE = "{\"posts\":[{\"id\":1,\"created_at\":\"2024-01-01T00:00:00.000-05:00\","
                                  "\"file\":{\"width\":100,\"height\":100,\"ext\":\"png\",\"size\":1000,\"md5\":\"aaa\",\"url\":\"https://static1.e621.net/data/1.png\"},"
                                  "\"preview\":{\"width\":50,\"height\":50,\"url\":\"https://static1.e621.net/data/preview/1.png\"},"
                                  "\"sample\":{\"has\":true,\"url\":\"https://static1.e621.net/data/sample/1.png\"},\"score\":{\"up\":1,\"down\":0,\"total\":1},"
                                  "\"tags\":{\"general\":[\"one\"],\"species\":[],\"character\":[],\"copyright\":[],\"artist\":[\"someartist\"],\"invalid\":[],\"lore\":[],\"meta\":[]},"
                                  "\"rating\":\"s\",\"fav_count\":1,\"sources\":[\"https://example.com/original\"],\"description\":\"a test post\",\"comment_count\":0,\"is_favorited\":false,\"pools\":[]}]}";

static const char *E621_SINGLE_POST_FIXTURE = "{\"post\":{\"id\":42,\"created_at\":\"2024-01-01T00:00:00.000-05:00\","
                                              "\"file\":{\"width\":100,\"height\":100,\"ext\":\"png\",\"size\":1000,\"md5\":\"bbb\",\"url\":\"https://static1.e621.net/data/42.png\"},"
                                              "\"preview\":{\"width\":50,\"height\":50,\"url\":\"https://static1.e621.net/data/preview/42.png\"},"
                                              "\"sample\":{\"has\":false},\"score\":{\"up\":2,\"down\":0,\"total\":2},"
                                              "\"tags\":{\"general\":[\"two\"],\"species\":[],\"character\":[],\"copyright\":[],\"artist\":[\"anotherartist\"],\"invalid\":[],\"lore\":[],\"meta\":[]},"
                                              "\"rating\":\"s\",\"fav_count\":2,\"sources\":[],\"description\":\"a fetched post\",\"comment_count\":0,\"is_favorited\":false,\"pools\":[]}}";

static const char *E621_POOL_FIXTURE = "{\"id\":5,\"name\":\"a_test_pool\",\"description\":\"a test pool\",\"created_at\":\"2024-01-01T00:00:00.000-05:00\","
                                       "\"updated_at\":\"2024-01-02T00:00:00.000-05:00\",\"creator_id\":1,\"creator_name\":\"someone\",\"is_active\":true,"
                                       "\"category\":\"series\",\"post_ids\":[1,2,3]}";

static const char *E621_COMMENTS_LIST_FIXTURE = "[{\"id\":1,\"post_id\":42,\"creator_name\":\"someone\",\"body\":\"Nice pic!\",\"created_at\":\"2024-01-02T00:00:00.000-05:00\"}]";

/* One entry already locally blacklisted ("young"), one brand new
 * ("brand_new"), and one multi-tag "AND" line the local blacklist can't
 * represent yet ("rating:e young") -- exercises all three outcomes of
 * bunny_core_sync_e621_blacklist in a single fetch. */
static const char *E621_USER_PROFILE_FIXTURE = "{\"id\":1,\"name\":\"tester\",\"blacklisted_tags\":\"young\\nbrand_new\\nrating:e young\"}";

static bunny_http_result_t fake_e621_send(void *user_data, const bunny_http_request_t *request, bunny_http_response_t *out_response)
{
    (void)user_data;
    const char *body = E621_FIXTURE;
    if (strstr(request->url, "/posts/42.json")) {
        body = E621_SINGLE_POST_FIXTURE;
    } else if (strstr(request->url, "/pools/5.json")) {
        body = E621_POOL_FIXTURE;
    } else if (strstr(request->url, "/users/tester.json")) {
        body = E621_USER_PROFILE_FIXTURE;
    } else if (strstr(request->url, "/comments.json") && request->method == BUNNY_HTTP_GET) {
        body = E621_COMMENTS_LIST_FIXTURE;
    }
    out_response->status = 200;
    out_response->body = strdup(body);
    out_response->body_len = strlen(body);
    return BUNNY_HTTP_OK;
}

static const char *INKBUNNY_LOGIN_FIXTURE = "{\"sid\":\"x\",\"user_id\":\"628881\",\"ratingsmask\":\"101\"}";

static const char *INKBUNNY_MY_FAVORITES_FIXTURE = "{\"sid\":\"x\",\"results_count_all\":1,\"results_count_thispage\":1,\"pages_count\":1,\"page\":1,"
                                                   "\"user_location\":\"\",\"search_params\":[],\"submissions\":["
                                                   "{\"submission_id\":\"99\",\"hidden\":\"f\",\"username\":\"someone\",\"user_id\":\"628881\","
                                                   "\"create_datetime\":\"2026-01-01 00:00:00+00\",\"thumbnail_url_large_noncustom\":\"https://example.invalid/99.jpg\","
                                                   "\"title\":\"my favorite thing\",\"deleted\":\"f\",\"public\":\"t\",\"rating_id\":\"0\",\"rating_name\":\"General\","
                                                   "\"submission_type_id\":\"1\",\"friends_only\":\"f\",\"guest_block\":\"f\",\"scraps\":\"f\",\"favorite\":\"t\",\"keywords\":[]}"
                                                   "]}";

static bunny_http_result_t fake_inkbunny_send(void *user_data, const bunny_http_request_t *request, bunny_http_response_t *out_response)
{
    (void)user_data;
    const char *body = strstr(request->url, "api_login.php") ? INKBUNNY_LOGIN_FIXTURE : INKBUNNY_MY_FAVORITES_FIXTURE;
    out_response->status = 200;
    out_response->body = strdup(body);
    out_response->body_len = strlen(body);
    return BUNNY_HTTP_OK;
}

/* Sleeps ~1s before returning the normal fixture -- the "slow sync" this
 * test's concurrency check needs. Only ever installed by
 * test_concurrent_request_is_not_blocked_by_a_slow_sync below; every other
 * test's setUp() resets g_e621_transport.send back to fake_e621_send. */
static bunny_http_result_t slow_fake_e621_send(void *user_data, const bunny_http_request_t *request, bunny_http_response_t *out_response)
{
    usleep(1000000);
    return fake_e621_send(user_data, request, out_response);
}

static bunny_http_transport_t g_e621_transport;
static bunny_http_transport_t g_inkbunny_transport;
static server_app_t *g_app;
static char g_data_dir[] = "/tmp/bunny_server_test_integration_XXXXXX";

typedef struct
{
    char *data;
    size_t size;
} response_buffer_t;

static size_t write_callback(void *ptr, size_t size, size_t nmemb, void *userdata)
{
    response_buffer_t *buf = (response_buffer_t *)userdata;
    size_t total = size * nmemb;
    char *new_data = realloc(buf->data, buf->size + total + 1);
    if (!new_data) {
        return 0;
    }
    buf->data = new_data;
    memcpy(buf->data + buf->size, ptr, total);
    buf->size += total;
    buf->data[buf->size] = '\0';
    return total;
}

static long do_request(const char *method, const char *path, const char *body, response_buffer_t *out_response, bool with_auth, const char *auth_token_override)
{
    CURL *curl = curl_easy_init();
    char url[256];
    snprintf(url, sizeof(url), "https://127.0.0.1:%d%s", TEST_PORT, path);

    curl_easy_setopt(curl, CURLOPT_URL, url);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 0L);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 0L);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_callback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, out_response);
    curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, method);
    if (body) {
        curl_easy_setopt(curl, CURLOPT_POSTFIELDS, body);
    }

    struct curl_slist *headers = NULL;
    if (with_auth) {
        char auth_header[128];
        const char *token = auth_token_override ? auth_token_override : server_app_auth_token(g_app);
        snprintf(auth_header, sizeof(auth_header), "Authorization: Bearer %s", token);
        headers = curl_slist_append(headers, auth_header);
    }
    if (body) {
        headers = curl_slist_append(headers, "Content-Type: application/json");
    }
    if (headers) {
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    }

    CURLcode res = curl_easy_perform(curl);
    long status = 0;
    if (res == CURLE_OK) {
        curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &status);
    }

    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
    return status;
}

/* POST /searches/{id}/sync, POST /sync, and POST /sync/all all just enqueue
 * onto the background sync worker and return 202 immediately (see
 * task_queue.h) -- the work itself finishes asynchronously, often within
 * microseconds against these tests' instant fake transports, but with no
 * guaranteed ordering relative to when this function's response arrives.
 * (POST /queue/process stays synchronous -- see handle_queue_process's own
 * comment in routes_queue.c for why -- so it doesn't need this.) Tests that
 * need to observe the result poll for it here instead of relying on a
 * synchronous response body. 2s timeout is generous for a fake, in-memory-db
 * transport with no real network latency. */
static bool poll_until_response_contains(const char *method, const char *path, const char *needle)
{
    for (int attempt = 0; attempt < 100; attempt++) {
        response_buffer_t response = {0};
        long status = do_request(method, path, NULL, &response, true, NULL);
        bool found = status == 200 && response.data && strstr(response.data, needle) != NULL;
        free(response.data);
        if (found) {
            return true;
        }
        usleep(20000); /* 20ms */
    }
    return false;
}

void setUp(void)
{
    g_e621_transport.send = fake_e621_send;
    g_e621_transport.user_data = NULL;
    g_inkbunny_transport.send = fake_inkbunny_send;
    g_inkbunny_transport.user_data = NULL;

    strcpy(g_data_dir, "/tmp/bunny_server_test_integration_XXXXXX");
    TEST_ASSERT_NOT_NULL(mkdtemp(g_data_dir));

    bunny_core_config_t core_config;
    memset(&core_config, 0, sizeof(core_config));
    core_config.db_path = ":memory:";
    core_config.user_agent = "bunny-tests/1.0 (integration)";
    core_config.e621_transport = &g_e621_transport;
    core_config.inkbunny_transport = &g_inkbunny_transport;
    core_config.min_request_interval_sec = 0.001;

    /* poll_interval_sec <= 0 disables the scheduler -- these tests drive
     * /sync and /queue/process explicitly and don't want a background pass
     * racing (and consuming) the fake transport's canned responses. */
    g_app = server_app_start(&core_config, g_data_dir, TEST_PORT, 0);
    TEST_ASSERT_NOT_NULL(g_app);
    usleep(100000); /* give civetweb a moment to bind before the first request */
}

void tearDown(void)
{
    /* Stop the scheduler (and therefore any in-flight backup_due_and_prune,
     * M14.5) before touching the filesystem below -- otherwise a
     * still-running poll tick could recreate backups/<file> between this
     * cleanup's unlink and rmdir. */
    server_app_stop(g_app);
    g_app = NULL;

    char path[512];
    snprintf(path, sizeof(path), "%s/auth_token", g_data_dir);
    unlink(path);
    snprintf(path, sizeof(path), "%s/server.pem", g_data_dir);
    unlink(path);

    /* Any test run with a short poll interval (e.g. test_scheduler_*) may
     * have had the scheduler write into backups/ as a side effect, even if
     * that specific test isn't about backups. */
    char backups_dir[600];
    snprintf(backups_dir, sizeof(backups_dir), "%s/backups", g_data_dir);
    DIR *dir = opendir(backups_dir);
    if (dir) {
        struct dirent *entry;
        while ((entry = readdir(dir)) != NULL) {
            if (entry->d_name[0] == '.') {
                continue;
            }
            snprintf(path, sizeof(path), "%s/%s", backups_dir, entry->d_name);
            unlink(path);
        }
        closedir(dir);
        rmdir(backups_dir);
    }

    rmdir(g_data_dir);
}

void test_health_check_no_auth_needed(void)
{
    response_buffer_t response = {0};
    long status = do_request("GET", "/health", NULL, &response, false, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"status\":\"ok\""));
    free(response.data);
}

void test_request_without_token_is_rejected(void)
{
    response_buffer_t response = {0};
    long status = do_request("GET", "/searches", NULL, &response, false, NULL);
    TEST_ASSERT_EQUAL(401, status);
    free(response.data);
}

void test_request_with_wrong_token_is_rejected(void)
{
    response_buffer_t response = {0};
    long status = do_request("GET", "/searches", NULL, &response, true, "wrong-token");
    TEST_ASSERT_EQUAL(401, status);
    free(response.data);
}

void test_verify_account(void)
{
    response_buffer_t response = {0};

    /* fake_e621_send always returns E621_FIXTURE regardless of credentials,
     * so this only proves the route reaches bunny_core_account_verify and
     * maps a real E621_OK through to 200 -- the actual accept/reject logic
     * is covered against both success and failure fixtures in
     * libs/core/tests/test_sync.c. */
    long status = do_request("POST", "/accounts/verify", "{\"site\":\"e621\",\"username\":\"tester\",\"secret\":\"testkey\"}", &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"ok\":true"));
    free(response.data);
    memset(&response, 0, sizeof(response));

    /* Verifying doesn't persist anything. */
    status = do_request("GET", "/accounts/e621", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(404, status);
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("POST", "/accounts/verify", "{\"site\":\"e621\",\"username\":\"tester\"}", &response, true, NULL);
    TEST_ASSERT_EQUAL(400, status);
    free(response.data);
}

void test_full_account_search_sync_favorite_flow(void)
{
    response_buffer_t response = {0};

    long status = do_request("POST", "/accounts", "{\"site\":\"e621\",\"username\":\"tester\",\"secret\":\"testkey\"}", &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("GET", "/accounts/e621", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"id\":1"));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"username\":\"tester\""));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"created_at\":"));
    TEST_ASSERT_NULL(strstr(response.data, "testkey")); /* secret must never be echoed back */
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("POST", "/searches", "{\"site\":\"e621\",\"label\":\"wolves\",\"query\":\"wolf\",\"interval_hours\":24}", &response, true, NULL);
    TEST_ASSERT_EQUAL(201, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"id\":1"));
    free(response.data);
    memset(&response, 0, sizeof(response));

    /* Fake e621 transport (set up in setUp) means this hits no real network.
     * /sync just enqueues onto the background sync worker and returns
     * immediately (202) -- see poll_until_response_contains's doc comment. */
    status = do_request("POST", "/sync", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(202, status);
    free(response.data);
    memset(&response, 0, sizeof(response));

    TEST_ASSERT_TRUE(poll_until_response_contains("GET", "/searches/1/posts", "\"external_id\":1"));

    status = do_request("GET", "/searches/1/posts", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"external_id\":1"));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"is_seen\":false"));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"sample_url\":\"https://static1.e621.net/data/sample/1.png\""));
    free(response.data);
    memset(&response, 0, sizeof(response));

    /* "somea", not the shorter "one" -- M39 throttles autocomplete to
     * prefixes of 5+ characters. */
    status = do_request("GET", "/tags/autocomplete?site=e621&prefix=somea", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"name\":\"someartist\""));
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("GET", "/posts/1/tags", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"name\":\"one\""));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"category\":\"general\""));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"name\":\"someartist\""));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"category\":\"artist\""));
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("GET", "/posts/1/sources", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_EQUAL_STRING("[\"https://example.com/original\"]", response.data);
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("GET", "/posts/1/relationships", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"has_parent\":false"));
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("GET", "/posts/1/pools", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_EQUAL_STRING("[]", response.data);
    free(response.data);
    memset(&response, 0, sizeof(response));

    /* Fetches post external_id 42 live (never synced via any search) and
     * caches it -- the fake transport routes this to E621_SINGLE_POST_FIXTURE. */
    status = do_request("POST", "/posts/fetch?site=e621&external_id=42", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"id\":2")); /* second row in this fresh :memory: db */
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("GET", "/pools/5", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"name\":\"a_test_pool\""));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"post_count\":3"));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"description\":\"a test pool\""));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"referenced_pool_ids\":[]"));
    free(response.data);
    memset(&response, 0, sizeof(response));

    /* The fetched post (external_id 42) is local id 2 (the search sync's
     * post took id 1) -- GET /posts/{id} reads it back by that local id. */
    status = do_request("GET", "/posts/2", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"external_id\":42"));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"artist\":\"anotherartist\""));
    free(response.data);
    memset(&response, 0, sizeof(response));

    /* Live comment list for local post id 2 (external_id 42) -- fetched
     * fresh from the site on every call, nothing persisted. */
    status = do_request("GET", "/posts/2/comments", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"creator_name\":\"someone\""));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"body\":\"Nice pic!\""));
    free(response.data);
    memset(&response, 0, sizeof(response));

    /* A stateless preview search -- the fake transport routes this to the
     * same E621_FIXTURE as the earlier search sync (external_id 1), so this
     * upserts in place (still local id 1) rather than creating a new row. No
     * new searches row is created either. */
    status = do_request("POST", "/search/preview?site=e621&query=wolf", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"id\":1"));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"artist\":\"someartist\""));
    free(response.data);
    memset(&response, 0, sizeof(response));

    /* An explicit page param (M9.6.2's infinite scroll) is accepted the same
     * way -- the fake transport doesn't vary its fixture by page, so this
     * only confirms the server parses/forwards the param without erroring. */
    status = do_request("POST", "/search/preview?site=e621&query=wolf&page=2", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("GET", "/searches", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"id\":1")); /* still just the one "wolves" search */
    TEST_ASSERT_NULL(strstr(response.data, "\"id\":2"));
    free(response.data);
    memset(&response, 0, sizeof(response));

    /* The synced post's local id is 1 (first row in a fresh :memory: db). */
    status = do_request("POST", "/posts/1/seen", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("GET", "/searches/1/posts", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"is_seen\":true"));
    free(response.data);
    memset(&response, 0, sizeof(response));

    /* The synced post's local id is 1 (first row in a fresh :memory: db). */
    status = do_request("POST", "/posts/1/favorite", "{}", &response, true, NULL);
    TEST_ASSERT_EQUAL(202, status);
    free(response.data);
    memset(&response, 0, sizeof(response));

    /* M9.7.1: an upvote queued right alongside the favorite above, so a
     * single /queue/process drains both in one pass. */
    status = do_request("POST", "/posts/1/vote", "{\"score\":1}", &response, true, NULL);
    TEST_ASSERT_EQUAL(202, status);
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("POST", "/queue/process", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    /* No e621 account credentials matter here -- favorite_add/vote just need
     * status 200, which the fake transport always returns. Unlike /sync and
     * /searches/{id}/sync, this stays synchronous (see handle_queue_process's
     * own comment in routes_queue.c for why) -- the real stats are available
     * immediately. */
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"actions_succeeded\":2"));
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("GET", "/searches/1/posts", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"user_vote\":1"));
    free(response.data);
    memset(&response, 0, sizeof(response));

    /* M10.2/M40: post 1 (tags "one"/"someartist") was favorited a few
     * requests ago, so both tags now show up in the unified report's
     * top_favorited_tags, site-prefixed since the report merges e621 and
     * Inkbunny into one ranking. top_used_tags is a superset of
     * top_favorited_tags (a non-favorited post still counting there is
     * covered at the C level) -- same two tags show up in both here since
     * this fixture's only post is favorited either way. */
    status = do_request("GET", "/stats_report", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"computed_at\""));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"top_favorited_tags\":[{\"name\":\"e621: one\""));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"name\":\"e621: someartist\""));
    /* top_used_tags also picks up tags from posts synced by earlier steps in
     * this same end-to-end flow -- just checking presence, not position. */
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"top_used_tags\""));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"name\":\"e621: one\""));
    free(response.data);
    memset(&response, 0, sizeof(response));

    /* A manual refresh (M40) recomputes rather than erroring/no-op-ing. */
    status = do_request("POST", "/stats_report", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"name\":\"e621: one\""));
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("GET", "/posts/1/downloads", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_EQUAL_STRING("[]", response.data);
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("POST", "/posts/1/downloads", "{\"file_path\":\"/downloads/wolf/1.png\",\"checksum_md5\":\"aaa\",\"verified\":true}", &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"id\":1"));
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("GET", "/posts/1/downloads", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"file_path\":\"/downloads/wolf/1.png\""));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"checksum_md5\":\"aaa\""));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"checksum_verified\":true"));
    free(response.data);
}

/* The underlying "a forced single-search sync ignores the due check, unlike
 * the batch /sync endpoint" invariant (M13.2) is proven directly against
 * bunny_core_sync_search in libs/core/tests/test_sync.c
 * (test_sync_search_forces_a_non_due_search_to_sync) -- the task_queue job
 * this route enqueues always calls bunny_core_sync_search, never the
 * due-checking bunny_core_sync_due_searches, so that guarantee holds by
 * construction here too. This test instead covers what's specific to the
 * route: a known search id is accepted and actually gets synced
 * (asynchronously -- see poll_until_response_contains), a repeat call is
 * also accepted, and an unknown id still gets an immediate 404 (checked
 * synchronously before enqueueing, since the worker has no way to report
 * NOT_FOUND after an 202 response has already gone out). */
void test_sync_single_search_forces_even_when_not_due(void)
{
    response_buffer_t response = {0};

    long status = do_request("POST", "/searches", "{\"site\":\"e621\",\"label\":\"wolves\",\"query\":\"wolf\",\"interval_hours\":24}", &response, true, NULL);
    TEST_ASSERT_EQUAL(201, status);
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("POST", "/searches/1/sync", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(202, status);
    free(response.data);
    memset(&response, 0, sizeof(response));

    TEST_ASSERT_TRUE(poll_until_response_contains("GET", "/searches/1/posts", "\"external_id\":1"));

    /* Repeat call -- must still be accepted, not rejected just because the
     * search was already synced moments ago. */
    status = do_request("POST", "/searches/1/sync", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(202, status);
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("POST", "/searches/999/sync", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(404, status);
    free(response.data);
}

void test_blacklist_add_list_remove(void)
{
    response_buffer_t response = {0};

    long status = do_request("GET", "/blacklist?site=e621", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_EQUAL_STRING("[]", response.data);
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("POST", "/blacklist", "{\"site\":\"e621\",\"tag\":\"young\"}", &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"ok\":true"));
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("GET", "/blacklist?site=e621", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"young\""));
    free(response.data);
    memset(&response, 0, sizeof(response));

    /* A different site's list must stay empty. */
    status = do_request("GET", "/blacklist?site=inkbunny", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_EQUAL_STRING("[]", response.data);
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("DELETE", "/blacklist?site=e621&tag=young", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("GET", "/blacklist?site=e621", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_EQUAL_STRING("[]", response.data);
    free(response.data);
}

void test_blacklist_e621_sync_imports_new_tags_and_skips_multi_tag_lines(void)
{
    response_buffer_t response = {0};

    long status = do_request("POST", "/accounts", "{\"site\":\"e621\",\"username\":\"tester\",\"secret\":\"testkey\"}", &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("POST", "/blacklist", "{\"site\":\"e621\",\"tag\":\"young\"}", &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("POST", "/blacklist/e621/sync", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"added\":1"));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"already_present\":1"));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"skipped_multi_tag\":1"));
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("GET", "/blacklist?site=e621", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"young\""));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"brand_new\""));
    TEST_ASSERT_NULL(strstr(response.data, "rating:e young"));
    free(response.data);
}

void test_search_pin_and_unpin(void)
{
    response_buffer_t response = {0};

    long status = do_request("POST", "/searches", "{\"site\":\"e621\",\"label\":\"wolves\",\"query\":\"wolf\",\"interval_hours\":24}", &response, true, NULL);
    TEST_ASSERT_EQUAL(201, status);
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("GET", "/searches", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"pinned\":false"));
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("POST", "/searches/1/pin", "{\"pinned\":true}", &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"ok\":true"));
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("GET", "/searches", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"pinned\":true"));
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("POST", "/searches/1/pin", "{\"pinned\":false}", &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("GET", "/searches", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"pinned\":false"));
    free(response.data);
}

void test_group_crud_and_assign_search(void)
{
    response_buffer_t response = {0};

    long status = do_request("POST", "/groups", "{\"name\":\"Wolves\",\"pinned\":true}", &response, true, NULL);
    TEST_ASSERT_EQUAL(201, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"id\":1"));
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("GET", "/groups", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"name\":\"Wolves\""));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"pinned\":true"));
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("PUT", "/groups/1", "{\"name\":\"Canines\",\"pinned\":false}", &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"ok\":true"));
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("GET", "/groups", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"name\":\"Canines\""));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"pinned\":false"));
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("POST", "/searches", "{\"site\":\"e621\",\"label\":\"wolves\",\"query\":\"wolf\",\"interval_hours\":24}", &response, true, NULL);
    TEST_ASSERT_EQUAL(201, status);
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("GET", "/searches", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"group_id\":0"));
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("POST", "/searches/1/group", "{\"group_id\":1}", &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"ok\":true"));
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("GET", "/searches", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"group_id\":1"));
    free(response.data);
    memset(&response, 0, sizeof(response));

    /* Deleting a group ungroups its member searches instead of deleting
     * them (confirmed design decision -- see bunny_db_group_delete). */
    status = do_request("DELETE", "/groups/1", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"ok\":true"));
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("GET", "/groups", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_EQUAL_STRING("[]", response.data);
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("GET", "/searches", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"group_id\":0"));
    free(response.data);
}

void test_search_touch_viewed(void)
{
    response_buffer_t response = {0};

    long status = do_request("POST", "/searches", "{\"site\":\"e621\",\"label\":\"wolves\",\"query\":\"wolf\",\"interval_hours\":24}", &response, true, NULL);
    TEST_ASSERT_EQUAL(201, status);
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("GET", "/searches", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"last_viewed_at\":null"));
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("POST", "/searches/1/viewed", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"ok\":true"));
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("GET", "/searches", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NULL(strstr(response.data, "\"last_viewed_at\":null"));
    free(response.data);
}

void test_search_auto_favorite_create_and_update(void)
{
    response_buffer_t response = {0};

    long status = do_request("POST", "/searches", "{\"site\":\"e621\",\"label\":\"wolves\",\"query\":\"wolf\",\"interval_hours\":24,\"auto_favorite\":true,\"auto_favorite_stars\":2,\"auto_upvote\":true}", &response, true, NULL);
    TEST_ASSERT_EQUAL(201, status);
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("GET", "/searches", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"auto_favorite\":true"));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"auto_favorite_stars\":2"));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"auto_upvote\":true"));
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("PUT", "/searches/1", "{\"label\":\"renamed\",\"query\":\"fox\",\"interval_hours\":12,\"auto_favorite\":false,\"auto_favorite_stars\":1,\"auto_upvote\":false}", &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("GET", "/searches", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"label\":\"renamed\""));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"query\":\"fox\""));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"auto_favorite\":false"));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"auto_upvote\":false"));
    free(response.data);
}

void test_my_inkbunny_favorites_searches_and_caches_with_favorite_marked(void)
{
    response_buffer_t response = {0};

    long status = do_request("POST", "/favorites/inkbunny/mine?page=1", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"external_id\":99"));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"title\":\"my favorite thing\""));
    /* M10.3: the fixture's "favorite":"t" must be mirrored into the local
     * favorites table, not just displayed. */
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"is_favorited\":true"));
    free(response.data);
}

void test_scheduler_syncs_search_automatically(void)
{
    /* setUp started the app with the scheduler disabled (poll_interval=0);
     * restart with a short interval to exercise the actual background
     * thread, instead of relying on an explicit /sync call. */
    server_app_stop(g_app);

    bunny_core_config_t core_config;
    memset(&core_config, 0, sizeof(core_config));
    core_config.db_path = ":memory:";
    core_config.user_agent = "bunny-tests/1.0 (integration)";
    core_config.e621_transport = &g_e621_transport;
    core_config.min_request_interval_sec = 0.001;

    g_app = server_app_start(&core_config, g_data_dir, TEST_PORT, 1);
    TEST_ASSERT_NOT_NULL(g_app);
    usleep(100000);

    response_buffer_t response = {0};
    long status = do_request("POST", "/searches", "{\"site\":\"e621\",\"label\":\"wolves\",\"query\":\"wolf\",\"interval_hours\":24}", &response, true, NULL);
    TEST_ASSERT_EQUAL(201, status);
    free(response.data);
    memset(&response, 0, sizeof(response));

    /* Give the 1s-poll scheduler thread time to fire at least once, with no
     * explicit /sync call from this test. */
    sleep(3);

    status = do_request("GET", "/searches/1/posts", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"external_id\":1"));
    free(response.data);
}

void test_scheduler_backs_up_database_automatically(void)
{
    /* Same restart-with-a-short-poll-interval shape as the sync test above
     * -- exercises the actual scheduler thread's backup check (M14.5)
     * instead of calling anything backup-related directly, since there's
     * no HTTP route for it (server-only background job). */
    server_app_stop(g_app);

    bunny_core_config_t core_config;
    memset(&core_config, 0, sizeof(core_config));
    core_config.db_path = ":memory:";
    core_config.user_agent = "bunny-tests/1.0 (integration)";
    core_config.e621_transport = &g_e621_transport;
    core_config.min_request_interval_sec = 0.001;

    g_app = server_app_start(&core_config, g_data_dir, TEST_PORT, 1);
    TEST_ASSERT_NOT_NULL(g_app);
    usleep(100000);

    /* No existing backups -- the first poll tick should back up right
     * away, no 24h wait needed on an empty backups/ dir. Stop the scheduler
     * before inspecting backups/ -- otherwise a concurrent tick could
     * recreate a file (count is back to 0 right after this test's own
     * cleanup deletes it) between this test's unlink and rmdir, racing the
     * cleanup below. */
    sleep(3);
    server_app_stop(g_app);
    g_app = NULL;

    /* tearDown() cleans up backups/ itself (every poll-tick test can leave
     * one behind, not just this test) -- just confirm one exists here. */
    char backups_dir[600];
    snprintf(backups_dir, sizeof(backups_dir), "%s/backups", g_data_dir);
    DIR *dir = opendir(backups_dir);
    TEST_ASSERT_NOT_NULL(dir);

    int found = 0;
    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL) {
        if (strncmp(entry->d_name, "bunny_", 6) == 0) {
            found++;
        }
    }
    closedir(dir);
    TEST_ASSERT_TRUE(found > 0);
}

void test_get_logs_returns_json_array_with_access_log_line(void)
{
    response_buffer_t response = {0};

    /* Unauthenticated, but still goes through civetweb's log_access
     * callback -- generates an access-log line we can look for below. */
    long status = do_request("GET", "/health", NULL, &response, false, NULL);
    TEST_ASSERT_EQUAL(200, status);
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("GET", "/logs", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_EQUAL('[', response.data[0]);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "/health"));
    free(response.data);
}

/* TEST_ASSERT must never run on this thread -- Unity's assertion macros
 * longjmp back into the test runner, which is only safe from the thread
 * that called RUN_TEST. The status is stashed in *out_status and checked on
 * the main thread instead, after pthread_join below. */
static void *run_slow_sync_request(void *arg)
{
    long *out_status = (long *)arg;
    response_buffer_t response = {0};
    *out_status = do_request("POST", "/searches/1/sync", NULL, &response, true, NULL);
    free(response.data);
    return NULL;
}

static double elapsed_ms(struct timespec start)
{
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (now.tv_sec - start.tv_sec) * 1000.0 + (now.tv_nsec - start.tv_nsec) / 1e6;
}

/* Regression test for the real production bug: a slow sync used to hold the
 * server's single core_mutex for its entire duration (including network
 * I/O), freezing every other request on the server. That mutex
 * (server_context_t.core_mutex) is gone now -- bunny_core protects itself
 * internally and never holds its own lock across network I/O (see
 * libs/core/tests/test_concurrency.c for that half of the fix) -- and on top
 * of that, POST /searches/{id}/sync no longer even calls bunny_core_sync_
 * search from this request's own thread at all: it just enqueues onto
 * task_queue and returns 202 immediately, so the slow network call now
 * happens entirely on task_queue's own dedicated thread, never occupying
 * one of civetweb's worker threads for its duration (see task_queue.h).
 * Both assertions below would have failed against the pre-M19 bug; the
 * first one (the sync POST itself returning fast) would ALSO have failed
 * against a version of this server that still called bunny_core_sync_search
 * synchronously from the route even with M19's fix applied, since that
 * alone doesn't stop a slow sync from parking a civetweb worker thread for
 * its whole duration. */
void test_concurrent_request_is_not_blocked_by_a_slow_sync(void)
{
    response_buffer_t response = {0};
    long status = do_request("POST", "/searches", "{\"site\":\"e621\",\"label\":\"wolves\",\"query\":\"wolf\",\"interval_hours\":24}", &response, true, NULL);
    TEST_ASSERT_EQUAL(201, status);
    free(response.data);

    g_e621_transport.send = slow_fake_e621_send;

    pthread_t sync_thread;
    long sync_request_status = 0;
    struct timespec start;
    clock_gettime(CLOCK_MONOTONIC, &start);
    TEST_ASSERT_EQUAL(0, pthread_create(&sync_thread, NULL, run_slow_sync_request, &sync_request_status));

    /* Give the sync request a moment to actually be enqueued before racing
     * the fast one against it. */
    usleep(100000); /* 100ms */

    response_buffer_t fast_response = {0};
    status = do_request("GET", "/searches", NULL, &fast_response, true, NULL);
    double fast_elapsed = elapsed_ms(start);
    TEST_ASSERT_EQUAL(200, status);
    free(fast_response.data);

    /* The slow sync's fake transport sleeps ~1s -- both the sync POST
     * itself (now fire-and-forget) and the unrelated GET must return in
     * well under that. */
    TEST_ASSERT_TRUE_MESSAGE(fast_elapsed < 500.0, "a concurrent request was blocked by the in-flight slow sync");

    pthread_join(sync_thread, NULL);
    TEST_ASSERT_EQUAL(202, sync_request_status);
}

void test_settings_get_and_put_default_sync_interval_hours(void)
{
    response_buffer_t response = {0};
    long status = do_request("GET", "/settings", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"default_sync_interval_hours\":24"));
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("PUT", "/settings", "{\"default_sync_interval_hours\":6}", &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("GET", "/settings", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"default_sync_interval_hours\":6"));
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("PUT", "/settings", "{\"default_sync_interval_hours\":0}", &response, true, NULL);
    TEST_ASSERT_EQUAL(400, status);
    free(response.data);
}

void test_sync_status_is_inactive_when_nothing_is_running(void)
{
    response_buffer_t response = {0};
    long status = do_request("GET", "/sync/status", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"active\":false"));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"started_at\":null"));
    free(response.data);
}

/* Exercises the full /sync/all lifecycle against the slow fake transport:
 * status reports the search by name while the forced sync is still running
 * (any device polling GET /sync/status should see this, not just the one
 * that triggered it), a duplicate /sync/all while one is already in flight
 * is rejected (409) rather than piling up a second full pass, and status
 * goes back to inactive once the background worker finishes. */
void test_sync_all_reports_progress_and_rejects_duplicate_while_running(void)
{
    response_buffer_t response = {0};
    long status = do_request("POST", "/searches", "{\"site\":\"e621\",\"label\":\"wolves\",\"query\":\"wolf\",\"interval_hours\":24}", &response, true, NULL);
    TEST_ASSERT_EQUAL(201, status);
    free(response.data);
    memset(&response, 0, sizeof(response));

    g_e621_transport.send = slow_fake_e621_send;

    status = do_request("POST", "/sync/all", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(202, status);
    free(response.data);
    memset(&response, 0, sizeof(response));

    usleep(200000); /* 200ms -- give the worker time to pick the job up */

    status = do_request("GET", "/sync/status", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"active\":true"));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"search_label\":\"wolves\""));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"position\":1"));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"total\":1"));
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("POST", "/sync/all", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(409, status);
    free(response.data);
    memset(&response, 0, sizeof(response));

    TEST_ASSERT_TRUE(poll_until_response_contains("GET", "/sync/status", "\"active\":false"));
}

/* GET /tasks (M24) -- the live task_queue snapshot, as opposed to /sync/
 * status's single "what's running right now" view. Two HIGH-priority
 * single-search syncs enqueued back-to-back (with the e621 transport
 * slowed down so the first stays visible while running) come back with the
 * expected fields and in enqueue order -- their timestamps can tie within
 * the same second, so this also exercises the id tiebreak in task_queue.c's
 * compare_entries, not just the priority ordering. */
void test_tasks_endpoint_lists_pending_and_running_jobs_in_fifo_order(void)
{
    response_buffer_t response = {0};

    long status = do_request("POST", "/searches", "{\"site\":\"e621\",\"label\":\"wolves\",\"query\":\"wolf\",\"interval_hours\":24}", &response, true, NULL);
    TEST_ASSERT_EQUAL(201, status);
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("POST", "/searches", "{\"site\":\"e621\",\"label\":\"foxes\",\"query\":\"fox\",\"interval_hours\":24}", &response, true, NULL);
    TEST_ASSERT_EQUAL(201, status);
    free(response.data);
    memset(&response, 0, sizeof(response));

    g_e621_transport.send = slow_fake_e621_send;

    status = do_request("POST", "/searches/1/sync", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(202, status);
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("POST", "/searches/2/sync", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(202, status);
    free(response.data);
    memset(&response, 0, sizeof(response));

    usleep(200000); /* give the worker time to pick up the first job */

    status = do_request("GET", "/tasks", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"priority\":\"high\""));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"status\":\"running\""));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"status\":\"pending\""));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"type\":\"sync_search\""));

    const char *wolves_pos = strstr(response.data, "\"label\":\"Sync: wolves\"");
    const char *foxes_pos = strstr(response.data, "\"label\":\"Sync: foxes\"");
    TEST_ASSERT_NOT_NULL(wolves_pos);
    TEST_ASSERT_NOT_NULL(foxes_pos);
    TEST_ASSERT_TRUE(wolves_pos < foxes_pos);

    free(response.data);
}

/* The scheduler's own background due-search pass is LOW priority (M24) --
 * when a user explicitly asks for the same work via POST /sync (HIGH)
 * while the background pass is already pending/running, task_queue merges
 * them (promoting the existing slot) instead of queuing a redundant second
 * copy, and still reports success rather than the 409 a genuine duplicate
 * HIGH-priority request gets (see
 * test_sync_all_reports_progress_and_rejects_duplicate_while_running). */
void test_user_triggered_due_sync_promotes_a_pending_background_one_instead_of_duplicating(void)
{
    server_app_stop(g_app);

    g_e621_transport.send = slow_fake_e621_send;

    bunny_core_config_t core_config;
    memset(&core_config, 0, sizeof(core_config));
    core_config.db_path = ":memory:";
    core_config.user_agent = "bunny-tests/1.0 (integration)";
    core_config.e621_transport = &g_e621_transport;
    core_config.min_request_interval_sec = 0.001;

    g_app = server_app_start(&core_config, g_data_dir, TEST_PORT, 1);
    TEST_ASSERT_NOT_NULL(g_app);
    usleep(100000);

    response_buffer_t response = {0};
    long status = do_request("POST", "/searches", "{\"site\":\"e621\",\"label\":\"wolves\",\"query\":\"wolf\",\"interval_hours\":24}", &response, true, NULL);
    TEST_ASSERT_EQUAL(201, status);
    free(response.data);
    memset(&response, 0, sizeof(response));

    /* Wait for the scheduler's first tick to enqueue its LOW-priority
     * due-sync (the new search is due immediately) -- slowed down above so
     * it's still pending/running when the HIGH-priority request below
     * arrives. */
    TEST_ASSERT_TRUE(poll_until_response_contains("GET", "/tasks", "\"type\":\"sync_due\""));

    status = do_request("POST", "/sync", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(202, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"enqueued\":true"));
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("GET", "/tasks", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    const char *first_sync_due = strstr(response.data, "\"type\":\"sync_due\"");
    TEST_ASSERT_NOT_NULL(first_sync_due);
    TEST_ASSERT_NULL(strstr(first_sync_due + 1, "\"type\":\"sync_due\"")); /* merged, not duplicated */
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"priority\":\"high\""));  /* promoted from low */
    free(response.data);
}

int main(void)
{
    curl_global_init(CURL_GLOBAL_DEFAULT);
    UNITY_BEGIN();
    RUN_TEST(test_health_check_no_auth_needed);
    RUN_TEST(test_request_without_token_is_rejected);
    RUN_TEST(test_request_with_wrong_token_is_rejected);
    RUN_TEST(test_verify_account);
    RUN_TEST(test_full_account_search_sync_favorite_flow);
    RUN_TEST(test_sync_single_search_forces_even_when_not_due);
    RUN_TEST(test_blacklist_add_list_remove);
    RUN_TEST(test_blacklist_e621_sync_imports_new_tags_and_skips_multi_tag_lines);
    RUN_TEST(test_search_pin_and_unpin);
    RUN_TEST(test_group_crud_and_assign_search);
    RUN_TEST(test_search_touch_viewed);
    RUN_TEST(test_search_auto_favorite_create_and_update);
    RUN_TEST(test_my_inkbunny_favorites_searches_and_caches_with_favorite_marked);
    RUN_TEST(test_scheduler_syncs_search_automatically);
    RUN_TEST(test_scheduler_backs_up_database_automatically);
    RUN_TEST(test_get_logs_returns_json_array_with_access_log_line);
    RUN_TEST(test_concurrent_request_is_not_blocked_by_a_slow_sync);
    RUN_TEST(test_settings_get_and_put_default_sync_interval_hours);
    RUN_TEST(test_sync_status_is_inactive_when_nothing_is_running);
    RUN_TEST(test_sync_all_reports_progress_and_rejects_duplicate_while_running);
    RUN_TEST(test_tasks_endpoint_lists_pending_and_running_jobs_in_fifo_order);
    RUN_TEST(test_user_triggered_due_sync_promotes_a_pending_background_one_instead_of_duplicating);
    int result = UNITY_END();
    curl_global_cleanup();
    return result;
}
