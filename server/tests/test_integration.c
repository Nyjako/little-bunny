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
                                  "\"sample\":{\"has\":false},\"score\":{\"up\":1,\"down\":0,\"total\":1},"
                                  "\"tags\":{\"general\":[\"one\"],\"species\":[],\"character\":[],\"copyright\":[],\"artist\":[\"someartist\"],\"invalid\":[],\"lore\":[],\"meta\":[]},"
                                  "\"rating\":\"s\",\"fav_count\":1,\"sources\":[],\"description\":\"a test post\",\"comment_count\":0,\"is_favorited\":false,\"pools\":[]}]}";

static bunny_http_result_t fake_e621_send(void *user_data, const bunny_http_request_t *request, bunny_http_response_t *out_response)
{
    (void)user_data;
    (void)request;
    out_response->status = 200;
    out_response->body = strdup(E621_FIXTURE);
    out_response->body_len = strlen(E621_FIXTURE);
    return BUNNY_HTTP_OK;
}

static bunny_http_transport_t g_e621_transport;
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

    strcpy(g_data_dir, "/tmp/bunny_server_test_integration_XXXXXX");
    TEST_ASSERT_NOT_NULL(mkdtemp(g_data_dir));

    bunny_core_config_t core_config;
    memset(&core_config, 0, sizeof(core_config));
    core_config.db_path = ":memory:";
    core_config.user_agent = "bunny-tests/1.0 (integration)";
    core_config.e621_transport = &g_e621_transport;
    core_config.min_request_interval_sec = 0.001;

    g_app = server_app_start(&core_config, g_data_dir, TEST_PORT);
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

void test_full_account_search_sync_favorite_flow(void)
{
    response_buffer_t response = {0};

    long status = do_request("POST", "/accounts", "{\"site\":\"e621\",\"username\":\"tester\",\"secret\":\"testkey\"}", &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("GET", "/accounts/e621", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"username\":\"tester\""));
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
    free(response.data);
    memset(&response, 0, sizeof(response));

    /* The synced post's local id is 1 (first row in a fresh :memory: db). */
    status = do_request("POST", "/posts/1/favorite", "{}", &response, true, NULL);
    TEST_ASSERT_EQUAL(202, status);
    free(response.data);
    memset(&response, 0, sizeof(response));

    status = do_request("POST", "/queue/process", NULL, &response, true, NULL);
    TEST_ASSERT_EQUAL(200, status);
    /* No e621 account credentials matter here -- favorite_add just needs
     * status 200, which the fake transport always returns. */
    TEST_ASSERT_NOT_NULL(strstr(response.data, "\"actions_succeeded\":1"));
    free(response.data);
}

int main(void)
{
    curl_global_init(CURL_GLOBAL_DEFAULT);
    UNITY_BEGIN();
    RUN_TEST(test_health_check_no_auth_needed);
    RUN_TEST(test_request_without_token_is_rejected);
    RUN_TEST(test_request_with_wrong_token_is_rejected);
    RUN_TEST(test_full_account_search_sync_favorite_flow);
    int result = UNITY_END();
    curl_global_cleanup();
    return result;
}
