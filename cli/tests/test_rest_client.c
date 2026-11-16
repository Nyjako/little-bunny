#include "unity.h"

#include "rest_client.h"

#include <stdlib.h>
#include <string.h>

/* Fakes the transport, not rest_client.c's own request-building/response-
 * mapping logic -- same philosophy as every other fake transport in this
 * codebase (bunny_core's injectable e621_transport, app/lib's
 * HttpBunnyRepository.withClient). Never performs a real TLS handshake, so
 * this never exercises bunny_cli_rest_client_init's own certificate-pinning
 * code -- that's covered separately by bunny_cli_rest_fingerprint_matches'
 * own tests below (the exact comparison the real pinning callback uses) and
 * by manual end-to-end verification against a real bunny_server instance
 * (same precedent as http_bunny_repository_test.dart's own doc comment). */
typedef struct
{
    bunny_http_method_t last_method;
    char last_url[512];
    char last_header_names[8][64];
    char last_header_values[8][256];
    size_t last_header_count;
    char last_body[512];

    long canned_status;
    const char *canned_body;
} fake_transport_state_t;

static fake_transport_state_t g_state;
static bunny_http_transport_t g_transport;

static bunny_http_result_t fake_send(void *user_data, const bunny_http_request_t *request, bunny_http_response_t *out_response)
{
    fake_transport_state_t *state = (fake_transport_state_t *)user_data;
    state->last_method = request->method;
    strncpy(state->last_url, request->url, sizeof(state->last_url) - 1);
    state->last_header_count = request->header_count;
    for (size_t i = 0; i < request->header_count && i < 8; i++) {
        strncpy(state->last_header_names[i], request->headers[i].name, sizeof(state->last_header_names[i]) - 1);
        strncpy(state->last_header_values[i], request->headers[i].value, sizeof(state->last_header_values[i]) - 1);
    }
    state->last_body[0] = '\0';
    if (request->body) {
        size_t len = request->body_len < sizeof(state->last_body) - 1 ? request->body_len : sizeof(state->last_body) - 1;
        memcpy(state->last_body, request->body, len);
        state->last_body[len] = '\0';
    }

    if (state->canned_status == 0) {
        return BUNNY_HTTP_ERR_NETWORK;
    }

    out_response->status = state->canned_status;
    out_response->body = strdup(state->canned_body ? state->canned_body : "");
    out_response->body_len = strlen(out_response->body);
    return BUNNY_HTTP_OK;
}

static const char *header_value(const char *name)
{
    for (size_t i = 0; i < g_state.last_header_count; i++) {
        if (strcmp(g_state.last_header_names[i], name) == 0) {
            return g_state.last_header_values[i];
        }
    }
    return NULL;
}

static bunny_cli_rest_client_t g_client;

void setUp(void)
{
    memset(&g_state, 0, sizeof(g_state));
    g_state.canned_status = 200;
    g_state.canned_body = "{\"ok\":true}";
    g_transport.send = fake_send;
    g_transport.user_data = &g_state;
    bunny_cli_rest_client_init_with_transport(&g_client, "https://example.test:8443", "the-token", g_transport);
}

void tearDown(void)
{
    bunny_cli_rest_client_free(&g_client);
}

void test_request_builds_the_full_url_and_bearer_header(void)
{
    cJSON *out = NULL;
    bunny_cli_rest_result_t result = bunny_cli_rest_request(&g_client, BUNNY_HTTP_GET, "/pools/42", NULL, &out);

    TEST_ASSERT_EQUAL(BUNNY_CLI_REST_OK, result);
    TEST_ASSERT_EQUAL(BUNNY_HTTP_GET, g_state.last_method);
    TEST_ASSERT_EQUAL_STRING("https://example.test:8443/pools/42", g_state.last_url);
    TEST_ASSERT_EQUAL_STRING("Bearer the-token", header_value("Authorization"));
    cJSON_Delete(out);
}

void test_a_json_body_is_sent_with_a_content_type_header(void)
{
    cJSON *body = cJSON_CreateObject();
    cJSON_AddNumberToObject(body, "score", 1);

    cJSON *out = NULL;
    bunny_cli_rest_result_t result = bunny_cli_rest_request(&g_client, BUNNY_HTTP_POST, "/posts/1/vote", body, &out);
    cJSON_Delete(body);

    TEST_ASSERT_EQUAL(BUNNY_CLI_REST_OK, result);
    TEST_ASSERT_EQUAL(BUNNY_HTTP_POST, g_state.last_method);
    TEST_ASSERT_EQUAL_STRING("application/json", header_value("Content-Type"));
    TEST_ASSERT_EQUAL_STRING("{\"score\":1}", g_state.last_body);
    cJSON_Delete(out);
}

void test_no_body_means_no_content_type_header(void)
{
    cJSON *out = NULL;
    bunny_cli_rest_request(&g_client, BUNNY_HTTP_DELETE, "/posts/1/favorite", NULL, &out);

    TEST_ASSERT_NULL(header_value("Content-Type"));
    TEST_ASSERT_EQUAL_STRING("", g_state.last_body);
    cJSON_Delete(out);
}

void test_a_2xx_status_parses_the_response_body(void)
{
    g_state.canned_status = 202;
    g_state.canned_body = "{\"queued\":true}";

    cJSON *out = NULL;
    bunny_cli_rest_result_t result = bunny_cli_rest_request(&g_client, BUNNY_HTTP_POST, "/posts/1/favorite", NULL, &out);

    TEST_ASSERT_EQUAL(BUNNY_CLI_REST_OK, result);
    TEST_ASSERT_NOT_NULL(out);
    cJSON *queued = cJSON_GetObjectItemCaseSensitive(out, "queued");
    TEST_ASSERT_TRUE(cJSON_IsTrue(queued));
    cJSON_Delete(out);
}

static void expect_status_maps_to(long status, bunny_cli_rest_result_t expected)
{
    g_state.canned_status = status;
    g_state.canned_body = "{\"error\":\"something\"}";

    cJSON *out = NULL;
    bunny_cli_rest_result_t result = bunny_cli_rest_request(&g_client, BUNNY_HTTP_GET, "/whatever", NULL, &out);

    TEST_ASSERT_EQUAL(expected, result);
    cJSON_Delete(out); /* even on error, the parsed error body is handed back so the caller can log it */
}

void test_status_codes_map_to_the_right_result(void)
{
    expect_status_maps_to(400, BUNNY_CLI_REST_ERR_INVALID_ARG);
    expect_status_maps_to(401, BUNNY_CLI_REST_ERR_UNAUTHORIZED);
    expect_status_maps_to(404, BUNNY_CLI_REST_ERR_NOT_FOUND);
    expect_status_maps_to(415, BUNNY_CLI_REST_ERR_UNSUPPORTED);
    expect_status_maps_to(502, BUNNY_CLI_REST_ERR_SITE);
    expect_status_maps_to(500, BUNNY_CLI_REST_ERR_SERVER);
}

void test_an_error_response_body_is_still_handed_back_for_logging(void)
{
    g_state.canned_status = 400;
    g_state.canned_body = "{\"error\":\"invalid_arg\"}";

    cJSON *out = NULL;
    bunny_cli_rest_result_t result = bunny_cli_rest_request(&g_client, BUNNY_HTTP_GET, "/whatever", NULL, &out);

    TEST_ASSERT_EQUAL(BUNNY_CLI_REST_ERR_INVALID_ARG, result);
    TEST_ASSERT_NOT_NULL(out);
    TEST_ASSERT_EQUAL_STRING("invalid_arg", cJSON_GetObjectItemCaseSensitive(out, "error")->valuestring);
    cJSON_Delete(out);
}

void test_a_transport_failure_reports_network_error(void)
{
    g_state.canned_status = 0; /* fake_send's own sentinel for "simulate BUNNY_HTTP_ERR_NETWORK" */

    cJSON *out = NULL;
    bunny_cli_rest_result_t result = bunny_cli_rest_request(&g_client, BUNNY_HTTP_GET, "/whatever", NULL, &out);

    TEST_ASSERT_EQUAL(BUNNY_CLI_REST_ERR_NETWORK, result);
    TEST_ASSERT_NULL(out);
}

void test_url_encode_passes_unreserved_characters_through_unchanged(void)
{
    char *encoded = bunny_cli_rest_url_encode("abcXYZ019-._~");
    TEST_ASSERT_EQUAL_STRING("abcXYZ019-._~", encoded);
    free(encoded);
}

void test_url_encode_escapes_spaces_and_punctuation(void)
{
    char *encoded = bunny_cli_rest_url_encode("big tail/wet!");
    TEST_ASSERT_EQUAL_STRING("big%20tail%2Fwet%21", encoded);
    free(encoded);
}

/* ---- certificate-fingerprint matching (the exact comparison the real
 * pinned transport's OpenSSL verify callback uses -- see rest_client.c's
 * own doc comment on why the TLS handshake itself isn't exercised here) -- */

void test_fingerprint_matches_lowercase_hex_with_no_colons(void)
{
    unsigned char digest[32] = {0xAB, 0xCD, 0xEF, 0x01, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x02};
    TEST_ASSERT_TRUE(bunny_cli_rest_fingerprint_matches(digest, 32, "abcdef0100000000000000000000000000000000000000000000000000000002"));
}

void test_fingerprint_matches_uppercase_hex_with_colons(void)
{
    unsigned char digest[32] = {0xAB, 0xCD, 0xEF, 0x01, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x02};
    TEST_ASSERT_TRUE(bunny_cli_rest_fingerprint_matches(digest, 32, "AB:CD:EF:01:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:02"));
}

void test_fingerprint_mismatch_is_rejected(void)
{
    unsigned char digest[32] = {0};
    TEST_ASSERT_FALSE(bunny_cli_rest_fingerprint_matches(digest, 32, "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"));
}

void test_fingerprint_with_wrong_digest_length_is_rejected(void)
{
    unsigned char digest[20] = {0}; /* SHA-1 length, not SHA-256 -- must never be accepted */
    TEST_ASSERT_FALSE(bunny_cli_rest_fingerprint_matches(digest, 20, "0000000000000000000000000000000000000000000000000000000000000000"));
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_request_builds_the_full_url_and_bearer_header);
    RUN_TEST(test_a_json_body_is_sent_with_a_content_type_header);
    RUN_TEST(test_no_body_means_no_content_type_header);
    RUN_TEST(test_a_2xx_status_parses_the_response_body);
    RUN_TEST(test_status_codes_map_to_the_right_result);
    RUN_TEST(test_an_error_response_body_is_still_handed_back_for_logging);
    RUN_TEST(test_a_transport_failure_reports_network_error);
    RUN_TEST(test_url_encode_passes_unreserved_characters_through_unchanged);
    RUN_TEST(test_url_encode_escapes_spaces_and_punctuation);
    RUN_TEST(test_fingerprint_matches_lowercase_hex_with_no_colons);
    RUN_TEST(test_fingerprint_matches_uppercase_hex_with_colons);
    RUN_TEST(test_fingerprint_mismatch_is_rejected);
    RUN_TEST(test_fingerprint_with_wrong_digest_length_is_rejected);
    return UNITY_END();
}
