#include "unity.h"

#include <goblin/cstr.h>

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bunny_core/core.h"
#include "test_http_server.h"

typedef struct
{
    const char *bodies[4];
    size_t body_count;
    size_t next_index;
} fake_transport_state_t;

static fake_transport_state_t g_inkbunny_state;
static bunny_http_transport_t g_inkbunny_transport;
static bunny_core_t *g_core;
static char g_epub_path[256];

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
    if (fread(buf, 1, (size_t)size, f) != (size_t)size) {
        fclose(f);
        free(buf);
        return NULL;
    }
    buf[size] = '\0';
    fclose(f);
    return buf;
}

/* Reads inkbunny_submission_writing.json and substitutes every
 * "__FILE_URL__" placeholder with `file_url` -- lets each test point the
 * seeded post's cover image at its own local bunny_test_http_server
 * instance instead of a real, unreachable Inkbunny URL. */
static char *build_submission_writing_fixture(const char *file_url)
{
    char *raw = read_fixture("inkbunny_submission_writing.json");
    if (!raw) {
        return NULL;
    }
    char *substituted = goblin_replace_cstr(raw, "__FILE_URL__", file_url);
    free(raw);
    return substituted;
}

void setUp(void)
{
    memset(&g_inkbunny_state, 0, sizeof(g_inkbunny_state));
    g_inkbunny_transport.send = fake_send;
    g_inkbunny_transport.user_data = &g_inkbunny_state;

    bunny_core_config_t config;
    memset(&config, 0, sizeof(config));
    config.db_path = ":memory:";
    config.user_agent = "bunny-tests/1.0 (unit tests)";
    config.inkbunny_transport = &g_inkbunny_transport;
    config.min_request_interval_sec = 0.001;

    bunny_core_result_t result = bunny_core_open(&config, &g_core);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);

    snprintf(g_epub_path, sizeof(g_epub_path), "/tmp/bunny_core_test_writing_%d.epub", rand());
}

void tearDown(void)
{
    bunny_core_close(g_core);
    g_core = NULL;
    remove(g_epub_path);
}

static int64_t seed_writing_post(const char *cover_file_url)
{
    char *login_fixture = read_fixture("inkbunny_login_success.json");
    char *submission_fixture = build_submission_writing_fixture(cover_file_url ? cover_file_url : "https://example.invalid/cover.jpg");
    TEST_ASSERT_NOT_NULL(login_fixture);
    TEST_ASSERT_NOT_NULL(submission_fixture);
    g_inkbunny_state.bodies[0] = login_fixture;
    g_inkbunny_state.bodies[1] = submission_fixture;
    g_inkbunny_state.body_count = 2;

    int64_t post_id = 0;
    bunny_core_result_t result = bunny_core_fetch_and_cache_post(g_core, BUNNY_DB_SITE_INKBUNNY, 373335, &post_id);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_TRUE(post_id > 0);

    free(login_fixture);
    free(submission_fixture);
    return post_id;
}

void test_get_writing_doc_parses_cached_writing_into_blocks(void)
{
    int64_t post_id = seed_writing_post(NULL);

    bunny_doc_t doc;
    bunny_core_result_t result = bunny_core_get_writing_doc(g_core, post_id, &doc);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(2, (int)doc.count);
    TEST_ASSERT_EQUAL_STRING("Once upon a time, in a den far away, two foxes shared a story.", doc.items[0].runs.items[0].text);
    TEST_ASSERT_EQUAL(BUNNY_DOC_RUN_BOLD, doc.items[1].runs.items[0].kind);
    TEST_ASSERT_EQUAL_STRING("The end.", doc.items[1].runs.items[0].text);

    bunny_doc_free(&doc);
}

void test_get_writing_doc_returns_not_found_for_a_post_without_writing(void)
{
    char *login_fixture = read_fixture("inkbunny_login_success.json");
    char *submission_fixture = read_fixture("inkbunny_submission_full.json");
    TEST_ASSERT_NOT_NULL(login_fixture);
    TEST_ASSERT_NOT_NULL(submission_fixture);
    g_inkbunny_state.bodies[0] = login_fixture;
    g_inkbunny_state.bodies[1] = submission_fixture;
    g_inkbunny_state.body_count = 2;

    int64_t post_id = 0;
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, bunny_core_fetch_and_cache_post(g_core, BUNNY_DB_SITE_INKBUNNY, 3955918, &post_id));

    bunny_doc_t doc;
    TEST_ASSERT_EQUAL(BUNNY_CORE_ERR_NOT_FOUND, bunny_core_get_writing_doc(g_core, post_id, &doc));

    free(login_fixture);
    free(submission_fixture);
}

void test_get_writing_doc_rejects_a_nonexistent_post(void)
{
    bunny_doc_t doc;
    TEST_ASSERT_NOT_EQUAL(BUNNY_CORE_OK, bunny_core_get_writing_doc(g_core, 999999, &doc));
}

void test_build_writing_epub_embeds_the_cover_and_parsed_body(void)
{
    const char *cover_bytes = "fake-jpeg-bytes";
    bunny_test_http_server_t *server = bunny_test_http_server_start("200 OK", cover_bytes, strlen(cover_bytes), 1);
    TEST_ASSERT_NOT_NULL(server);
    char *cover_url = bunny_test_http_server_url(server);

    int64_t post_id = seed_writing_post(cover_url);

    bunny_core_result_t result = bunny_core_build_writing_epub(g_core, post_id, g_epub_path);
    bunny_test_http_server_join(server);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);

    bunny_doc_t doc;
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, bunny_core_read_writing_epub(g_epub_path, &doc));
    TEST_ASSERT_EQUAL(2, (int)doc.count);
    TEST_ASSERT_EQUAL_STRING("Once upon a time, in a den far away, two foxes shared a story.", doc.items[0].runs.items[0].text);

    bunny_doc_free(&doc);
    free(cover_url);
}

void test_build_writing_epub_still_succeeds_when_the_cover_fetch_fails(void)
{
    /* Nothing is listening on this URL -- the cover fetch fails, but the
     * epub itself must still build (just without a cover), same
     * best-effort spirit as every other network call in this app. */
    int64_t post_id = seed_writing_post("http://127.0.0.1:1/no-such-server.jpg");

    bunny_core_result_t result = bunny_core_build_writing_epub(g_core, post_id, g_epub_path);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);

    bunny_doc_t doc;
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, bunny_core_read_writing_epub(g_epub_path, &doc));
    TEST_ASSERT_EQUAL(2, (int)doc.count);
    bunny_doc_free(&doc);
}

void test_build_writing_epub_returns_not_found_for_a_post_without_writing(void)
{
    char *login_fixture = read_fixture("inkbunny_login_success.json");
    char *submission_fixture = read_fixture("inkbunny_submission_full.json");
    g_inkbunny_state.bodies[0] = login_fixture;
    g_inkbunny_state.bodies[1] = submission_fixture;
    g_inkbunny_state.body_count = 2;

    int64_t post_id = 0;
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, bunny_core_fetch_and_cache_post(g_core, BUNNY_DB_SITE_INKBUNNY, 3955918, &post_id));

    TEST_ASSERT_EQUAL(BUNNY_CORE_ERR_NOT_FOUND, bunny_core_build_writing_epub(g_core, post_id, g_epub_path));

    free(login_fixture);
    free(submission_fixture);
}

void test_read_writing_epub_rejects_a_nonexistent_file(void)
{
    bunny_doc_t doc;
    TEST_ASSERT_NOT_EQUAL(BUNNY_CORE_OK, bunny_core_read_writing_epub("/tmp/bunny_core_test_writing_does_not_exist.epub", &doc));
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_get_writing_doc_parses_cached_writing_into_blocks);
    RUN_TEST(test_get_writing_doc_returns_not_found_for_a_post_without_writing);
    RUN_TEST(test_get_writing_doc_rejects_a_nonexistent_post);
    RUN_TEST(test_build_writing_epub_embeds_the_cover_and_parsed_body);
    RUN_TEST(test_build_writing_epub_still_succeeds_when_the_cover_fetch_fails);
    RUN_TEST(test_build_writing_epub_returns_not_found_for_a_post_without_writing);
    RUN_TEST(test_read_writing_epub_rejects_a_nonexistent_file);
    return UNITY_END();
}
