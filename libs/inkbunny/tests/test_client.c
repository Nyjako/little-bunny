#include "unity.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "inkbunny/client.h"

typedef struct
{
    long response_status;
    char *response_body; /* not owned; caller manages lifecycle */
    size_t response_body_len;
    bunny_http_result_t forced_result;

    bunny_http_method_t last_method;
    char last_url[1024];
} fake_transport_state_t;

static fake_transport_state_t g_state;
static bunny_http_transport_t g_transport;

static bunny_http_result_t fake_send(void *user_data, const bunny_http_request_t *request, bunny_http_response_t *out_response)
{
    fake_transport_state_t *state = (fake_transport_state_t *)user_data;

    state->last_method = request->method;
    strncpy(state->last_url, request->url, sizeof(state->last_url) - 1);
    state->last_url[sizeof(state->last_url) - 1] = '\0';

    if (state->forced_result != BUNNY_HTTP_OK) {
        return state->forced_result;
    }

    out_response->status = state->response_status;
    if (state->response_body) {
        out_response->body = strdup(state->response_body);
        out_response->body_len = state->response_body_len;
    } else {
        out_response->body = strdup("");
        out_response->body_len = 0;
    }
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

static inkbunny_client_t *make_test_client(void)
{
    inkbunny_config_t config;
    memset(&config, 0, sizeof(config));
    /* 0 means "use the built-in ~0.5s default" (see inkbunny_config_t), which
     * would slow down tests that make more than one call on the same client
     * (e.g. login then search) -- use a negligible delay instead. */
    config.min_request_interval_sec = 0.001;
    config.transport = &g_transport;
    return inkbunny_client_create(&config);
}

/* Logs the test client in against the fixture-backed fake transport, then
 * resets the fake state's response fields so the next call can set its own. */
static void login_test_client(inkbunny_client_t *client, char **out_fixture_to_free)
{
    char *fixture = read_fixture("login_success.json");
    TEST_ASSERT_NOT_NULL(fixture);
    g_state.response_status = 200;
    g_state.response_body = fixture;
    g_state.response_body_len = strlen(fixture);

    inkbunny_result_t result = inkbunny_login(client, "guest", "");
    TEST_ASSERT_EQUAL(INKBUNNY_OK, result);

    *out_fixture_to_free = fixture;
}

void setUp(void)
{
    memset(&g_state, 0, sizeof(g_state));
    g_state.forced_result = BUNNY_HTTP_OK;
    g_transport.send = fake_send;
    g_transport.user_data = &g_state;
}

void tearDown(void)
{}

void test_login_success(void)
{
    inkbunny_client_t *client = make_test_client();
    TEST_ASSERT_NOT_NULL(client);

    char *fixture = NULL;
    login_test_client(client, &fixture);

    TEST_ASSERT_NOT_NULL(strstr(g_state.last_url, "api_login.php"));
    TEST_ASSERT_NOT_NULL(strstr(g_state.last_url, "username=guest"));

    free(fixture);
    inkbunny_client_destroy(client);
}

void test_login_failure(void)
{
    inkbunny_client_t *client = make_test_client();
    char *fixture = read_fixture("login_failure.json");
    TEST_ASSERT_NOT_NULL(fixture);
    g_state.response_status = 200;
    g_state.response_body = fixture;
    g_state.response_body_len = strlen(fixture);

    inkbunny_result_t result = inkbunny_login(client, "baduser", "badpass");

    TEST_ASSERT_EQUAL(INKBUNNY_ERR_AUTH, result);

    free(fixture);
    inkbunny_client_destroy(client);
}

void test_search_requires_login(void)
{
    inkbunny_client_t *client = make_test_client();

    inkbunny_submission_list_t list;
    inkbunny_result_t result = inkbunny_search(client, NULL, &list);

    TEST_ASSERT_EQUAL(INKBUNNY_ERR_AUTH, result);

    inkbunny_client_destroy(client);
}

void test_search_success(void)
{
    inkbunny_client_t *client = make_test_client();
    char *login_fixture = NULL;
    login_test_client(client, &login_fixture);
    free(login_fixture);

    char *fixture = read_fixture("search_response.json");
    TEST_ASSERT_NOT_NULL(fixture);
    g_state.response_status = 200;
    g_state.response_body = fixture;
    g_state.response_body_len = strlen(fixture);

    inkbunny_search_params_t params;
    memset(&params, 0, sizeof(params));
    params.text = "digimon beatbreak";

    inkbunny_submission_list_t list;
    inkbunny_result_t result = inkbunny_search(client, &params, &list);

    TEST_ASSERT_EQUAL(INKBUNNY_OK, result);
    TEST_ASSERT_EQUAL(2, (int)list.count);
    TEST_ASSERT_NOT_NULL(strstr(g_state.last_url, "api_search.php"));
    TEST_ASSERT_NOT_NULL(strstr(g_state.last_url, "sid="));
    TEST_ASSERT_NOT_NULL(strstr(g_state.last_url, "text=digimon%20beatbreak"));

    inkbunny_submission_list_free(&list);
    free(fixture);
    inkbunny_client_destroy(client);
}

void test_get_submission_success(void)
{
    inkbunny_client_t *client = make_test_client();
    char *login_fixture = NULL;
    login_test_client(client, &login_fixture);
    free(login_fixture);

    char *fixture = read_fixture("submission_full.json");
    TEST_ASSERT_NOT_NULL(fixture);
    g_state.response_status = 200;
    g_state.response_body = fixture;
    g_state.response_body_len = strlen(fixture);

    inkbunny_submission_t submission;
    inkbunny_result_t result = inkbunny_get_submission(client, 3955918, &submission);

    TEST_ASSERT_EQUAL(INKBUNNY_OK, result);
    TEST_ASSERT_EQUAL(3955918, (int)submission.submission_id);
    TEST_ASSERT_TRUE(submission.keywords.count > 0);
    TEST_ASSERT_NOT_NULL(strstr(g_state.last_url, "api_submissions.php"));
    TEST_ASSERT_NOT_NULL(strstr(g_state.last_url, "submission_ids=3955918"));

    inkbunny_submission_free(&submission);
    free(fixture);
    inkbunny_client_destroy(client);
}

void test_get_submission_not_found(void)
{
    inkbunny_client_t *client = make_test_client();
    char *login_fixture = NULL;
    login_test_client(client, &login_fixture);
    free(login_fixture);

    char *body = strdup("{\"sid\": \"x\", \"results_count\": 0, \"submissions\": []}");
    g_state.response_status = 200;
    g_state.response_body = body;
    g_state.response_body_len = strlen(body);

    inkbunny_submission_t submission;
    inkbunny_result_t result = inkbunny_get_submission(client, 1, &submission);

    TEST_ASSERT_EQUAL(INKBUNNY_ERR_NOT_FOUND, result);

    free(body);
    inkbunny_client_destroy(client);
}

void test_get_submissions_too_many_ids(void)
{
    inkbunny_client_t *client = make_test_client();
    char *login_fixture = NULL;
    login_test_client(client, &login_fixture);
    free(login_fixture);

    int64_t ids[101];
    for (int i = 0; i < 101; i++) {
        ids[i] = i + 1;
    }

    inkbunny_submission_list_t list;
    inkbunny_result_t result = inkbunny_get_submissions(client, ids, 101, &list);

    TEST_ASSERT_EQUAL(INKBUNNY_ERR_INVALID_ARG, result);

    inkbunny_client_destroy(client);
}

void test_search_network_error(void)
{
    inkbunny_client_t *client = make_test_client();
    char *login_fixture = NULL;
    login_test_client(client, &login_fixture);
    free(login_fixture);

    g_state.forced_result = BUNNY_HTTP_ERR_NETWORK;

    inkbunny_submission_list_t list;
    inkbunny_result_t result = inkbunny_search(client, NULL, &list);

    TEST_ASSERT_EQUAL(INKBUNNY_ERR_NETWORK, result);

    inkbunny_client_destroy(client);
}

void test_search_server_error(void)
{
    inkbunny_client_t *client = make_test_client();
    char *login_fixture = NULL;
    login_test_client(client, &login_fixture);
    free(login_fixture);

    g_state.response_status = 500;
    g_state.response_body = NULL;

    inkbunny_submission_list_t list;
    inkbunny_result_t result = inkbunny_search(client, NULL, &list);

    TEST_ASSERT_EQUAL(INKBUNNY_ERR_SERVER, result);

    inkbunny_client_destroy(client);
}

void test_search_malformed_json(void)
{
    inkbunny_client_t *client = make_test_client();
    char *login_fixture = NULL;
    login_test_client(client, &login_fixture);
    free(login_fixture);

    char *body = strdup("{ this is not valid json ");
    g_state.response_status = 200;
    g_state.response_body = body;
    g_state.response_body_len = strlen(body);

    inkbunny_submission_list_t list;
    inkbunny_result_t result = inkbunny_search(client, NULL, &list);

    TEST_ASSERT_EQUAL(INKBUNNY_ERR_PARSE, result);

    free(body);
    inkbunny_client_destroy(client);
}

void test_logout_clears_session(void)
{
    inkbunny_client_t *client = make_test_client();
    char *login_fixture = NULL;
    login_test_client(client, &login_fixture);
    free(login_fixture);

    char *body = strdup("{\"sid\": \"77N2zxwuZFvRduEQzvE15zGkiR\", \"logout\": \"success\"}");
    g_state.response_status = 200;
    g_state.response_body = body;
    g_state.response_body_len = strlen(body);

    inkbunny_result_t result = inkbunny_logout(client);
    TEST_ASSERT_EQUAL(INKBUNNY_OK, result);

    /* after logout, an authenticated call should fail client-side again without hitting the network */
    inkbunny_submission_list_t list;
    inkbunny_result_t search_result = inkbunny_search(client, NULL, &list);
    TEST_ASSERT_EQUAL(INKBUNNY_ERR_AUTH, search_result);

    free(body);
    inkbunny_client_destroy(client);
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_login_success);
    RUN_TEST(test_login_failure);
    RUN_TEST(test_search_requires_login);
    RUN_TEST(test_search_success);
    RUN_TEST(test_get_submission_success);
    RUN_TEST(test_get_submission_not_found);
    RUN_TEST(test_get_submissions_too_many_ids);
    RUN_TEST(test_search_network_error);
    RUN_TEST(test_search_server_error);
    RUN_TEST(test_search_malformed_json);
    RUN_TEST(test_logout_clears_session);
    return UNITY_END();
}
