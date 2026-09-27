#include "unity.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#include "e621/client.h"

typedef struct {
    long response_status;
    char *response_body; /* not owned; caller manages lifecycle */
    size_t response_body_len;
    bunny_http_result_t forced_result;

    bunny_http_method_t last_method;
    char last_url[1024];
    bool last_had_auth_header;
} fake_transport_state_t;

static fake_transport_state_t g_state;
static bunny_http_transport_t g_transport;

static bunny_http_result_t fake_send(void *user_data, const bunny_http_request_t *request,
                                      bunny_http_response_t *out_response) {
    fake_transport_state_t *state = (fake_transport_state_t *)user_data;

    state->last_method = request->method;
    strncpy(state->last_url, request->url, sizeof(state->last_url) - 1);
    state->last_url[sizeof(state->last_url) - 1] = '\0';

    state->last_had_auth_header = false;
    for (size_t i = 0; i < request->header_count; i++) {
        if (strcasecmp(request->headers[i].name, "Authorization") == 0) {
            state->last_had_auth_header = true;
        }
    }

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

static char *read_fixture(const char *filename) {
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

static e621_client_t *make_test_client(bool with_auth) {
    e621_config_t config;
    memset(&config, 0, sizeof(config));
    config.user_agent = "bunny-tests/1.0 (unit tests)";
    config.min_request_interval_sec = 0; /* no rate-limit delay in tests */
    config.transport = &g_transport;
    if (with_auth) {
        config.username = "tester";
        config.api_key = "secret-key";
    }
    return e621_client_create(&config);
}

void setUp(void) {
    memset(&g_state, 0, sizeof(g_state));
    g_state.forced_result = BUNNY_HTTP_OK;
    g_transport.send = fake_send;
    g_transport.user_data = &g_state;
}

void tearDown(void) {}

void test_search_posts_success(void) {
    e621_client_t *client = make_test_client(false);
    TEST_ASSERT_NOT_NULL(client);

    char *fixture = read_fixture("posts_search.json");
    TEST_ASSERT_NOT_NULL(fixture);
    g_state.response_status = 200;
    g_state.response_body = fixture;
    g_state.response_body_len = strlen(fixture);

    e621_post_list_t list;
    e621_result_t result = e621_search_posts(client, "wolf forest", 1, 50, &list);

    TEST_ASSERT_EQUAL(E621_OK, result);
    TEST_ASSERT_EQUAL(2, (int)list.count);
    TEST_ASSERT_NOT_NULL(strstr(g_state.last_url, "tags=wolf%20forest"));
    TEST_ASSERT_EQUAL(BUNNY_HTTP_GET, g_state.last_method);

    e621_post_list_free(&list);
    e621_client_destroy(client);
    free(fixture);
}

void test_get_post_success(void) {
    e621_client_t *client = make_test_client(false);

    char *fixture = read_fixture("post_single.json");
    TEST_ASSERT_NOT_NULL(fixture);
    g_state.response_status = 200;
    g_state.response_body = fixture;
    g_state.response_body_len = strlen(fixture);

    e621_post_t post;
    e621_result_t result = e621_get_post(client, 12345, &post);

    TEST_ASSERT_EQUAL(E621_OK, result);
    TEST_ASSERT_EQUAL(12345, (int)post.id);
    TEST_ASSERT_EQUAL(E621_RATING_SAFE, post.rating);
    TEST_ASSERT_EQUAL(2, (int)post.tags.species.count);
    TEST_ASSERT_TRUE(post.is_favorited);

    e621_post_free(&post);
    e621_client_destroy(client);
    free(fixture);
}

void test_get_post_not_found(void) {
    e621_client_t *client = make_test_client(false);
    g_state.response_status = 404;

    e621_post_t post;
    e621_result_t result = e621_get_post(client, 999999, &post);

    TEST_ASSERT_EQUAL(E621_ERR_NOT_FOUND, result);

    e621_client_destroy(client);
}

void test_search_posts_auth_error(void) {
    e621_client_t *client = make_test_client(false);
    g_state.response_status = 401;

    e621_post_list_t list;
    e621_result_t result = e621_search_posts(client, "test", 1, 10, &list);

    TEST_ASSERT_EQUAL(E621_ERR_AUTH, result);

    e621_client_destroy(client);
}

void test_search_posts_rate_limited(void) {
    e621_client_t *client = make_test_client(false);
    g_state.response_status = 429;

    e621_post_list_t list;
    e621_result_t result = e621_search_posts(client, "test", 1, 10, &list);

    TEST_ASSERT_EQUAL(E621_ERR_RATE_LIMITED, result);

    e621_client_destroy(client);
}

void test_search_posts_malformed_json(void) {
    e621_client_t *client = make_test_client(false);
    char *body = strdup("{ this is not valid json ");
    g_state.response_status = 200;
    g_state.response_body = body;
    g_state.response_body_len = strlen(body);

    e621_post_list_t list;
    e621_result_t result = e621_search_posts(client, "test", 1, 10, &list);

    TEST_ASSERT_EQUAL(E621_ERR_PARSE, result);

    free(body);
    e621_client_destroy(client);
}

void test_search_posts_network_error(void) {
    e621_client_t *client = make_test_client(false);
    g_state.forced_result = BUNNY_HTTP_ERR_NETWORK;

    e621_post_list_t list;
    e621_result_t result = e621_search_posts(client, "test", 1, 10, &list);

    TEST_ASSERT_EQUAL(E621_ERR_NETWORK, result);

    e621_client_destroy(client);
}

void test_favorite_add_requires_auth(void) {
    e621_client_t *client = make_test_client(false);

    e621_result_t result = e621_favorite_add(client, 123);

    TEST_ASSERT_EQUAL(E621_ERR_AUTH, result);

    e621_client_destroy(client);
}

void test_favorite_add_sends_auth_header(void) {
    e621_client_t *client = make_test_client(true);
    char *body = strdup("{}");
    g_state.response_status = 200;
    g_state.response_body = body;
    g_state.response_body_len = strlen(body);

    e621_result_t result = e621_favorite_add(client, 123);

    TEST_ASSERT_EQUAL(E621_OK, result);
    TEST_ASSERT_TRUE(g_state.last_had_auth_header);
    TEST_ASSERT_EQUAL(BUNNY_HTTP_POST, g_state.last_method);

    free(body);
    e621_client_destroy(client);
}

void test_vote_invalid_score(void) {
    e621_client_t *client = make_test_client(true);

    e621_result_t result = e621_vote(client, 123, 5, false);

    TEST_ASSERT_EQUAL(E621_ERR_INVALID_ARG, result);

    e621_client_destroy(client);
}

void test_comment_list_success(void) {
    e621_client_t *client = make_test_client(false);
    char *fixture = read_fixture("comments_list.json");
    TEST_ASSERT_NOT_NULL(fixture);
    g_state.response_status = 200;
    g_state.response_body = fixture;
    g_state.response_body_len = strlen(fixture);

    e621_comment_list_t comments;
    e621_result_t result = e621_comment_list(client, 12345, &comments);

    TEST_ASSERT_EQUAL(E621_OK, result);
    TEST_ASSERT_EQUAL(2, (int)comments.count);
    TEST_ASSERT_EQUAL_STRING("someone", comments.items[0].creator_name);

    e621_comment_list_free(&comments);
    e621_client_destroy(client);
    free(fixture);
}

int main(void) {
    UNITY_BEGIN();
    RUN_TEST(test_search_posts_success);
    RUN_TEST(test_get_post_success);
    RUN_TEST(test_get_post_not_found);
    RUN_TEST(test_search_posts_auth_error);
    RUN_TEST(test_search_posts_rate_limited);
    RUN_TEST(test_search_posts_malformed_json);
    RUN_TEST(test_search_posts_network_error);
    RUN_TEST(test_favorite_add_requires_auth);
    RUN_TEST(test_favorite_add_sends_auth_header);
    RUN_TEST(test_vote_invalid_score);
    RUN_TEST(test_comment_list_success);
    return UNITY_END();
}
