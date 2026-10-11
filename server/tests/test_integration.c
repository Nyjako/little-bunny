#include "unity.h"

#include <bunny_common/http.h>
#include <curl/curl.h>

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
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

static bunny_http_result_t fake_e621_send(void *user_data, const bunny_http_request_t *request, bunny_http_response_t *out_response)
{
    (void)user_data;
    const char *body = E621_FIXTURE;
    if (strstr(request->url, "/posts/42.json")) {
        body = E621_SINGLE_POST_FIXTURE;
    } else if (strstr(request->url, "/pools/5.json")) {
        body = E621_POOL_FIXTURE;
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
    server_app_stop(g_app);
    g_app = NULL;

    char path[512];
    snprintf(path, sizeof(path), "%s/auth_token", g_data_dir);
    unlink(path);
    snprintf(path, sizeof(path), "%s/server.pem", g_data_dir);
    unlink(path);
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

    /* Fake e621 transport (set up in setUp) means this hits no real network. */
    status = do_request("POST", "/sync", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"posts_upserted\":1"));
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("GET", "/searches/1/posts", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"external_id\":1"));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"is_seen\":false"));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"sample_url\":\"https://static1.e621.net/data/sample/1.png\""));
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("GET", "/tags/autocomplete?site=e621&prefix=on", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"name\":\"one\""));
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
     * status 200, which the fake transport always returns. */
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"actions_succeeded\":2"));
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("GET", "/searches/1/posts", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"user_vote\":1"));
    free(response.data);
    memset(&response, 0, sizeof(response));

    /* M10.2: post 1 (tags "one"/"someartist") was favorited a few requests
     * ago, so both tags now show up here with count 1. */
    status = do_request("GET", "/tags/top_favorited?site=e621", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"name\":\"one\""));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"name\":\"someartist\""));
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

void test_sync_single_search_forces_even_when_not_due(void)
{
    response_buffer_t response = {0};

    long status = do_request("POST", "/searches", "{\"site\":\"e621\",\"label\":\"wolves\",\"query\":\"wolf\",\"interval_hours\":24}", &response, true, NULL);
    TEST_ASSERT_EQUAL(201, status);
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("POST", "/searches/1/sync", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"searches_checked\":1"));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"searches_synced\":1"));
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"posts_upserted\":1"));
    free(response.data);
    memset(&response, 0, sizeof(response));

    /* The batch POST /sync would skip this (just touched, 24h interval) --
     * the per-search route must force it anyway (M13.2). */
    status = do_request("POST", "/searches/1/sync", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"searches_synced\":1"));
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
    RUN_TEST(test_search_pin_and_unpin);
    RUN_TEST(test_search_auto_favorite_create_and_update);
    RUN_TEST(test_my_inkbunny_favorites_searches_and_caches_with_favorite_marked);
    RUN_TEST(test_scheduler_syncs_search_automatically);
    int result = UNITY_END();
    curl_global_cleanup();
    return result;
}
