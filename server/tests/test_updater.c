#include "unity.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef _WIN32
#include <unistd.h>
#endif

#include "updater.h"

typedef struct
{
    long response_status;
    char *response_body; /* not owned; caller manages lifecycle */
    size_t response_body_len;
    bunny_http_result_t forced_result;

    char last_url[512];
    bool last_had_user_agent;
} fake_transport_state_t;

static fake_transport_state_t g_state;
static bunny_http_transport_t g_transport;

static bunny_http_result_t fake_send(void *user_data, const bunny_http_request_t *request, bunny_http_response_t *out_response)
{
    fake_transport_state_t *state = (fake_transport_state_t *)user_data;

    strncpy(state->last_url, request->url, sizeof(state->last_url) - 1);
    state->last_url[sizeof(state->last_url) - 1] = '\0';

    state->last_had_user_agent = false;
    for (size_t i = 0; i < request->header_count; i++) {
        if (strcmp(request->headers[i].name, "User-Agent") == 0) {
            state->last_had_user_agent = true;
        }
    }

    if (state->forced_result != BUNNY_HTTP_OK) {
        return state->forced_result;
    }

    out_response->status = state->response_status;
    if (state->response_body) {
        out_response->body = malloc(state->response_body_len + 1);
        memcpy(out_response->body, state->response_body, state->response_body_len);
        out_response->body[state->response_body_len] = '\0';
        out_response->body_len = state->response_body_len;
    } else {
        out_response->body = strdup("");
        out_response->body_len = 0;
    }
    return BUNNY_HTTP_OK;
}

void setUp(void)
{
    memset(&g_state, 0, sizeof(g_state));
    g_state.response_status = 200;
    g_transport.send = fake_send;
    g_transport.user_data = &g_state;
}

void tearDown(void) {}

/* --- bunny_updater_parse_latest_release (pure, offline) --------------- */

void test_parse_reports_update_available_with_matching_asset(void)
{
    const char *json = "{"
                        "\"tag_name\":\"build-42\","
                        "\"body\":\"Fixed things\","
                        "\"assets\":["
                        "{\"name\":\"bunny-server-windows-x64.zip\",\"browser_download_url\":\"https://example.invalid/win.zip\"},"
                        "{\"name\":\"bunny-server-linux-x64.tar.gz\",\"browser_download_url\":\"https://example.invalid/linux.tar.gz\"},"
                        "{\"name\":\"SHA256SUMS.txt\",\"browser_download_url\":\"https://example.invalid/SHA256SUMS.txt\"}"
                        "]}";

    bunny_updater_check_result_t result;
    bool ok = bunny_updater_parse_latest_release(json, strlen(json), 10, "linux-x64.tar.gz", &result);

    TEST_ASSERT_TRUE(ok);
    TEST_ASSERT_TRUE(result.update_available);
    TEST_ASSERT_EQUAL(42, result.latest_build_number);
    TEST_ASSERT_EQUAL_STRING("build-42", result.tag_name);
    TEST_ASSERT_EQUAL_STRING("https://example.invalid/linux.tar.gz", result.download_url);
    TEST_ASSERT_EQUAL_STRING("https://example.invalid/SHA256SUMS.txt", result.sha256_sums_url);
    TEST_ASSERT_EQUAL_STRING("Fixed things", result.release_notes);

    bunny_updater_check_result_free(&result);
}

void test_parse_leaves_sha256_sums_url_null_when_the_release_has_none(void)
{
    const char *json = "{"
                        "\"tag_name\":\"build-42\","
                        "\"assets\":["
                        "{\"name\":\"bunny-server-linux-x64.tar.gz\",\"browser_download_url\":\"https://example.invalid/linux.tar.gz\"}"
                        "]}";

    bunny_updater_check_result_t result;
    bunny_updater_parse_latest_release(json, strlen(json), 10, "linux-x64.tar.gz", &result);

    TEST_ASSERT_NULL(result.sha256_sums_url);

    bunny_updater_check_result_free(&result);
}

void test_parse_reports_no_update_when_current_build_is_latest(void)
{
    const char *json = "{\"tag_name\":\"build-10\",\"assets\":[]}";

    bunny_updater_check_result_t result;
    bool ok = bunny_updater_parse_latest_release(json, strlen(json), 10, "linux-x64.tar.gz", &result);

    TEST_ASSERT_TRUE(ok);
    TEST_ASSERT_FALSE(result.update_available);
    TEST_ASSERT_NULL(result.download_url);

    bunny_updater_check_result_free(&result);
}

void test_parse_reports_no_update_when_current_build_is_newer(void)
{
    /* Shouldn't happen in practice (nothing can be newer than "latest"),
     * but a local/dev build could have a higher BUNNY_BUILD_NUMBER than
     * whatever's actually been released -- must not treat that as "update
     * available" just because the numbers differ. */
    const char *json = "{\"tag_name\":\"build-5\",\"assets\":[]}";

    bunny_updater_check_result_t result;
    bunny_updater_parse_latest_release(json, strlen(json), 10, "linux-x64.tar.gz", &result);

    TEST_ASSERT_FALSE(result.update_available);

    bunny_updater_check_result_free(&result);
}

void test_parse_reports_no_update_for_local_dev_build(void)
{
    /* current_build_number 0 is the local/dev-build sentinel (CMakeLists.txt
     * defaults BUNNY_BUILD_NUMBER to "0") -- must never be treated as
     * outdated relative to any real release, no matter how high. */
    const char *json = "{\"tag_name\":\"build-999999\",\"assets\":[]}";

    bunny_updater_check_result_t result;
    bunny_updater_parse_latest_release(json, strlen(json), 0, "linux-x64.tar.gz", &result);

    TEST_ASSERT_FALSE(result.update_available);

    bunny_updater_check_result_free(&result);
}

void test_parse_update_available_but_no_matching_asset(void)
{
    const char *json = "{\"tag_name\":\"build-42\",\"assets\":["
                        "{\"name\":\"bunny-server-windows-x64.zip\",\"browser_download_url\":\"https://example.invalid/win.zip\"}"
                        "]}";

    bunny_updater_check_result_t result;
    bunny_updater_parse_latest_release(json, strlen(json), 10, "linux-x64.tar.gz", &result);

    TEST_ASSERT_TRUE(result.update_available);
    TEST_ASSERT_NULL(result.download_url);

    bunny_updater_check_result_free(&result);
}

void test_parse_ignores_a_tag_not_matching_this_projects_own_scheme(void)
{
    const char *json = "{\"tag_name\":\"v1.2.3\",\"assets\":[]}";

    bunny_updater_check_result_t result;
    bool ok = bunny_updater_parse_latest_release(json, strlen(json), 10, "linux-x64.tar.gz", &result);

    TEST_ASSERT_TRUE(ok);
    TEST_ASSERT_FALSE(result.update_available);
    TEST_ASSERT_NULL(result.tag_name);

    bunny_updater_check_result_free(&result);
}

void test_parse_rejects_malformed_json(void)
{
    bunny_updater_check_result_t result;
    bool ok = bunny_updater_parse_latest_release("{not json", 9, 10, "linux-x64.tar.gz", &result);
    TEST_ASSERT_FALSE(ok);
}

void test_parse_rejects_missing_tag_name(void)
{
    bunny_updater_check_result_t result;
    bool ok = bunny_updater_parse_latest_release("{}", 2, 10, "linux-x64.tar.gz", &result);
    TEST_ASSERT_FALSE(ok);
}

/* --- bunny_updater_check (via the fake transport) ---------------------- */

void test_check_sends_the_right_url_and_user_agent(void)
{
    g_state.response_body = "{\"tag_name\":\"build-1\",\"assets\":[]}";
    g_state.response_body_len = strlen(g_state.response_body);

    bunny_updater_check_result_t result;
    bunny_http_result_t http_result = bunny_updater_check(&g_transport, "Nyjako", "little-bunny", "LittleBunny-Server/0.1", "linux-x64.tar.gz", 0, &result);

    TEST_ASSERT_EQUAL(BUNNY_HTTP_OK, http_result);
    TEST_ASSERT_EQUAL_STRING("https://api.github.com/repos/Nyjako/little-bunny/releases/latest", g_state.last_url);
    TEST_ASSERT_TRUE(g_state.last_had_user_agent);

    bunny_updater_check_result_free(&result);
}

void test_check_propagates_a_network_error(void)
{
    g_state.forced_result = BUNNY_HTTP_ERR_NETWORK;

    bunny_updater_check_result_t result;
    bunny_http_result_t http_result = bunny_updater_check(&g_transport, "Nyjako", "little-bunny", "LittleBunny-Server/0.1", "linux-x64.tar.gz", 0, &result);

    TEST_ASSERT_EQUAL(BUNNY_HTTP_ERR_NETWORK, http_result);
}

void test_check_treats_a_non_200_status_as_an_error(void)
{
    g_state.response_status = 404;
    g_state.response_body = "{}";
    g_state.response_body_len = 2;

    bunny_updater_check_result_t result;
    bunny_http_result_t http_result = bunny_updater_check(&g_transport, "Nyjako", "little-bunny", "LittleBunny-Server/0.1", "linux-x64.tar.gz", 0, &result);

    TEST_ASSERT_EQUAL(BUNNY_HTTP_ERR_NETWORK, http_result);
}

/* --- bunny_updater_download_file (via the fake transport) --------------
 * mkstemp isn't portable -- guarded like the extraction test below, since
 * this whole binary is Linux-only in CI anyway (no Windows C test job). */
#ifndef _WIN32
void test_download_file_writes_the_response_body_verbatim_including_embedded_nul(void)
{
    char body[] = {'a', 'b', '\0', 'c', 'd'}; /* embedded NUL -- binary-safety check */
    g_state.response_body = body;
    g_state.response_body_len = sizeof(body);

    char dest_path[] = "/tmp/bunny_updater_test_download_XXXXXX";
    int fd = mkstemp(dest_path);
    TEST_ASSERT_TRUE(fd >= 0);
    close(fd);

    bunny_http_result_t result = bunny_updater_download_file(&g_transport, "https://example.invalid/asset", "LittleBunny-Server/0.1", dest_path);
    TEST_ASSERT_EQUAL(BUNNY_HTTP_OK, result);

    FILE *f = fopen(dest_path, "rb");
    TEST_ASSERT_NOT_NULL(f);
    char read_back[16];
    size_t n = fread(read_back, 1, sizeof(read_back), f);
    fclose(f);
    remove(dest_path);

    TEST_ASSERT_EQUAL(sizeof(body), n);
    TEST_ASSERT_EQUAL_MEMORY(body, read_back, sizeof(body));
}
#endif

/* --- bunny_updater_download_text ---------------------------------------- */

void test_download_text_returns_the_response_body_as_a_string(void)
{
    g_state.response_body = "deadbeef  bunny-server-linux-x64.tar.gz\n";
    g_state.response_body_len = strlen(g_state.response_body);

    char *text = bunny_updater_download_text(&g_transport, "https://example.invalid/SHA256SUMS.txt", "LittleBunny-Server/0.1");

    TEST_ASSERT_NOT_NULL(text);
    TEST_ASSERT_EQUAL_STRING(g_state.response_body, text);
    free(text);
}

void test_download_text_returns_null_on_a_non_200_status(void)
{
    g_state.response_status = 404;

    char *text = bunny_updater_download_text(&g_transport, "https://example.invalid/missing.txt", "LittleBunny-Server/0.1");

    TEST_ASSERT_NULL(text);
}

/* --- bunny_updater_sha256_hex -------------------------------------------- */

#ifndef _WIN32
void test_sha256_hex_matches_a_known_test_vector(void)
{
    /* SHA-256("abc") -- the canonical FIPS 180-4 test vector. */
    char path[] = "/tmp/bunny_updater_test_sha256_XXXXXX";
    int fd = mkstemp(path);
    TEST_ASSERT_TRUE(fd >= 0);
    TEST_ASSERT_EQUAL(3, write(fd, "abc", 3));
    close(fd);

    char hex[65];
    bool ok = bunny_updater_sha256_hex(path, hex);
    remove(path);

    TEST_ASSERT_TRUE(ok);
    TEST_ASSERT_EQUAL_STRING("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", hex);
}

void test_sha256_hex_returns_false_for_a_missing_file(void)
{
    char hex[65];
    bool ok = bunny_updater_sha256_hex("/tmp/bunny_updater_test_sha256_does_not_exist", hex);
    TEST_ASSERT_FALSE(ok);
}
#endif

/* --- bunny_updater_find_sha256 ------------------------------------------- */

void test_find_sha256_locates_the_right_entry_among_multiple_lines(void)
{
    const char *sums = "1111111111111111111111111111111111111111111111111111111111111111  bunny-server-windows-x64.zip\n"
                        "2222222222222222222222222222222222222222222222222222222222222222  bunny-server-linux-x64.tar.gz\n"
                        "3333333333333333333333333333333333333333333333333333333333333333  bunny-server-linux-x64-ubuntu22.tar.gz\n";

    char hex[65];
    bool ok = bunny_updater_find_sha256(sums, "bunny-server-linux-x64.tar.gz", hex);

    TEST_ASSERT_TRUE(ok);
    TEST_ASSERT_EQUAL_STRING("2222222222222222222222222222222222222222222222222222222222222222", hex);
}

void test_find_sha256_handles_binary_mode_asterisk_prefix(void)
{
    const char *sums = "4444444444444444444444444444444444444444444444444444444444444444 *bunny-server-linux-x64.tar.gz\n";

    char hex[65];
    bool ok = bunny_updater_find_sha256(sums, "bunny-server-linux-x64.tar.gz", hex);

    TEST_ASSERT_TRUE(ok);
    TEST_ASSERT_EQUAL_STRING("4444444444444444444444444444444444444444444444444444444444444444", hex);
}

void test_find_sha256_returns_false_when_filename_is_not_listed(void)
{
    const char *sums = "1111111111111111111111111111111111111111111111111111111111111111  bunny-server-windows-x64.zip\n";

    char hex[65];
    bool ok = bunny_updater_find_sha256(sums, "bunny-server-linux-x64.tar.gz", hex);

    TEST_ASSERT_FALSE(ok);
}

/* --- bunny_updater_extract_tar_gz --------------------------------------- */

#ifndef _WIN32
void test_extract_tar_gz_produces_the_archived_file(void)
{
    char dest_dir[] = "/tmp/bunny_updater_test_extract_XXXXXX";
    TEST_ASSERT_NOT_NULL(mkdtemp(dest_dir));

    char archive_path[512];
    snprintf(archive_path, sizeof(archive_path), "%s/sample_update.tar.gz", FIXTURES_DIR);

    bool ok = bunny_updater_extract_tar_gz(archive_path, dest_dir);
    TEST_ASSERT_TRUE(ok);

    char extracted_path[600];
    snprintf(extracted_path, sizeof(extracted_path), "%s/bunny_server", dest_dir);
    FILE *f = fopen(extracted_path, "rb");
    TEST_ASSERT_NOT_NULL(f);
    if (f) {
        fclose(f);
    }
}
#endif

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_parse_reports_update_available_with_matching_asset);
    RUN_TEST(test_parse_reports_no_update_when_current_build_is_latest);
    RUN_TEST(test_parse_reports_no_update_when_current_build_is_newer);
    RUN_TEST(test_parse_reports_no_update_for_local_dev_build);
    RUN_TEST(test_parse_update_available_but_no_matching_asset);
    RUN_TEST(test_parse_leaves_sha256_sums_url_null_when_the_release_has_none);
    RUN_TEST(test_parse_ignores_a_tag_not_matching_this_projects_own_scheme);
    RUN_TEST(test_parse_rejects_malformed_json);
    RUN_TEST(test_parse_rejects_missing_tag_name);
    RUN_TEST(test_check_sends_the_right_url_and_user_agent);
    RUN_TEST(test_check_propagates_a_network_error);
    RUN_TEST(test_check_treats_a_non_200_status_as_an_error);
    RUN_TEST(test_download_text_returns_the_response_body_as_a_string);
    RUN_TEST(test_download_text_returns_null_on_a_non_200_status);
    RUN_TEST(test_find_sha256_locates_the_right_entry_among_multiple_lines);
    RUN_TEST(test_find_sha256_handles_binary_mode_asterisk_prefix);
    RUN_TEST(test_find_sha256_returns_false_when_filename_is_not_listed);
#ifndef _WIN32
    RUN_TEST(test_download_file_writes_the_response_body_verbatim_including_embedded_nul);
    RUN_TEST(test_extract_tar_gz_produces_the_archived_file);
    RUN_TEST(test_sha256_hex_matches_a_known_test_vector);
    RUN_TEST(test_sha256_hex_returns_false_for_a_missing_file);
#endif
    return UNITY_END();
}
