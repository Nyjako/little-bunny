#include "unity.h"

#include <stdlib.h>
#include <string.h>

#include "bunny_common/download.h"
#include "bunny_common/md5.h"
#include "test_http_server.h"

void setUp(void)
{}
void tearDown(void)
{}

typedef struct
{
    char *data;
    size_t len;
} growable_buf_t;

static int collect_chunk(void *user_data, const void *data, size_t len)
{
    growable_buf_t *buf = (growable_buf_t *)user_data;
    char *new_data = realloc(buf->data, buf->len + len);
    if (!new_data) {
        return 1;
    }
    memcpy(new_data + buf->len, data, len);
    buf->data = new_data;
    buf->len += len;
    return 0;
}

static int always_fail_chunk(void *user_data, const void *data, size_t len)
{
    (void)user_data;
    (void)data;
    (void)len;
    return 1;
}

/* on_chunk and on_progress share one user_data pointer (bunny_download_sink_t
 * has a single field for both) -- a test exercising both needs one combined
 * context, not two separately-typed pointers aimed at the same address. */
typedef struct
{
    growable_buf_t buf;
    int progress_call_count;
    int64_t last_received;
} buf_with_progress_t;

static int collect_chunk_with_progress(void *user_data, const void *data, size_t len)
{
    buf_with_progress_t *ctx = (buf_with_progress_t *)user_data;
    return collect_chunk(&ctx->buf, data, len);
}

static void record_progress(void *user_data, int64_t received, int64_t total)
{
    buf_with_progress_t *ctx = (buf_with_progress_t *)user_data;
    (void)total;
    ctx->progress_call_count++;
    ctx->last_received = received;
}

static int md5_update_chunk(void *user_data, const void *data, size_t len)
{
    bunny_md5_update((bunny_md5_ctx_t *)user_data, data, len);
    return 0;
}

void test_fetches_a_whole_response_body(void)
{
    const char *body = "the quick brown fox jumps over the lazy dog";
    bunny_test_http_server_t *server = bunny_test_http_server_start("200 OK", body, strlen(body), 1);
    TEST_ASSERT_NOT_NULL(server);
    char *url = bunny_test_http_server_url(server);
    growable_buf_t buf = {0};

    bunny_download_sink_t sink = {collect_chunk, NULL, &buf};
    long status = -1;
    bunny_http_result_t result = bunny_download_fetch(url, NULL, 0, &sink, &status);

    bunny_test_http_server_join(server);
    TEST_ASSERT_EQUAL(BUNNY_HTTP_OK, result);
    TEST_ASSERT_EQUAL(200, status);
    TEST_ASSERT_EQUAL(strlen(body), buf.len);
    TEST_ASSERT_EQUAL_STRING_LEN(body, buf.data, buf.len);

    free(buf.data);
    free(url);
}

void test_reports_the_response_status_even_for_an_error(void)
{
    bunny_test_http_server_t *server = bunny_test_http_server_start("404 Not Found", NULL, 0, 1);
    TEST_ASSERT_NOT_NULL(server);
    char *url = bunny_test_http_server_url(server);
    growable_buf_t buf = {0};

    bunny_download_sink_t sink = {collect_chunk, NULL, &buf};
    long status = -1;
    bunny_http_result_t result = bunny_download_fetch(url, NULL, 0, &sink, &status);

    bunny_test_http_server_join(server);
    /* A 404 is still a successful transfer as far as bunny_download_fetch
     * is concerned -- the caller inspects status itself. */
    TEST_ASSERT_EQUAL(BUNNY_HTTP_OK, result);
    TEST_ASSERT_EQUAL(404, status);

    free(buf.data);
    free(url);
}

void test_reports_progress_as_bytes_arrive(void)
{
    const char *body = "0123456789";
    bunny_test_http_server_t *server = bunny_test_http_server_start("200 OK", body, strlen(body), 1);
    TEST_ASSERT_NOT_NULL(server);
    char *url = bunny_test_http_server_url(server);
    buf_with_progress_t ctx = {0};

    bunny_download_sink_t sink = {collect_chunk_with_progress, record_progress, &ctx};
    long status = -1;
    bunny_download_fetch(url, NULL, 0, &sink, &status);

    bunny_test_http_server_join(server);
    TEST_ASSERT_TRUE(ctx.progress_call_count > 0);
    TEST_ASSERT_EQUAL(strlen(body), ctx.last_received);

    free(ctx.buf.data);
    free(url);
}

void test_on_chunk_abort_surfaces_as_network_error(void)
{
    const char *body = "some content";
    bunny_test_http_server_t *server = bunny_test_http_server_start("200 OK", body, strlen(body), 1);
    TEST_ASSERT_NOT_NULL(server);
    char *url = bunny_test_http_server_url(server);

    bunny_download_sink_t sink = {always_fail_chunk, NULL, NULL};
    long status = -1;
    bunny_http_result_t result = bunny_download_fetch(url, NULL, 0, &sink, &status);

    bunny_test_http_server_join(server);
    TEST_ASSERT_EQUAL(BUNNY_HTTP_ERR_NETWORK, result);

    free(url);
}

void test_nothing_listening_fails_with_a_network_error(void)
{
    growable_buf_t buf = {0};
    bunny_download_sink_t sink = {collect_chunk, NULL, &buf};
    long status = -1;

    /* Port 1 requires root to bind -- nothing is ever listening there in
     * any normal test environment, so connecting as a client reliably
     * fails. */
    bunny_http_result_t result = bunny_download_fetch("http://127.0.0.1:1/", NULL, 0, &sink, &status);

    TEST_ASSERT_EQUAL(BUNNY_HTTP_ERR_NETWORK, result);
    free(buf.data);
}

void test_missing_required_arguments_are_rejected(void)
{
    growable_buf_t buf = {0};
    bunny_download_sink_t sink = {collect_chunk, NULL, &buf};
    long status = -1;

    TEST_ASSERT_EQUAL(BUNNY_HTTP_ERR_INVALID_ARG, bunny_download_fetch(NULL, NULL, 0, &sink, &status));
    TEST_ASSERT_EQUAL(BUNNY_HTTP_ERR_INVALID_ARG, bunny_download_fetch("http://127.0.0.1:1/", NULL, 0, NULL, &status));
    TEST_ASSERT_EQUAL(BUNNY_HTTP_ERR_INVALID_ARG, bunny_download_fetch("http://127.0.0.1:1/", NULL, 0, &sink, NULL));

    free(buf.data);
}

/* Exercises the full streamed fetch -> incremental MD5 composition the
 * download pipeline (M66) actually relies on. */
void test_streamed_chunks_hash_the_same_as_the_whole_response(void)
{
    const char *body = "content used to prove streamed hashing matches a one-shot hash of the same bytes";
    bunny_test_http_server_t *server = bunny_test_http_server_start("200 OK", body, strlen(body), 1);
    TEST_ASSERT_NOT_NULL(server);
    char *url = bunny_test_http_server_url(server);
    bunny_md5_ctx_t ctx;
    char streamed_hex[33];
    char one_shot_hex[33];

    bunny_md5_init(&ctx);
    bunny_download_sink_t sink = {md5_update_chunk, NULL, &ctx};

    long status = -1;
    bunny_download_fetch(url, NULL, 0, &sink, &status);
    bunny_test_http_server_join(server);
    bunny_md5_final(&ctx, streamed_hex);

    bunny_md5(body, strlen(body), one_shot_hex);
    TEST_ASSERT_EQUAL_STRING(one_shot_hex, streamed_hex);

    free(url);
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_fetches_a_whole_response_body);
    RUN_TEST(test_reports_the_response_status_even_for_an_error);
    RUN_TEST(test_reports_progress_as_bytes_arrive);
    RUN_TEST(test_on_chunk_abort_surfaces_as_network_error);
    RUN_TEST(test_nothing_listening_fails_with_a_network_error);
    RUN_TEST(test_missing_required_arguments_are_rejected);
    RUN_TEST(test_streamed_chunks_hash_the_same_as_the_whole_response);
    return UNITY_END();
}
