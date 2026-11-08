#include "unity.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "bunny_core/core.h"
#include "test_http_server.h"

static char g_dest_dir[256];

void setUp(void)
{
    snprintf(g_dest_dir, sizeof(g_dest_dir), "/tmp/bunny_core_test_download_%d", rand());
}

static void remove_dest_dir(void)
{
    char cmd[300];
    snprintf(cmd, sizeof(cmd), "rm -rf '%s'", g_dest_dir);
    system(cmd); /* test cleanup only -- g_dest_dir is always this file's own fixed-prefix temp path */
}

void tearDown(void)
{
    remove_dest_dir();
}

/* Polls until done or a generous ceiling, so a genuine hang fails the test
 * instead of blocking the whole suite forever. */
static void poll_until_done(int64_t handle, int64_t *out_received, int64_t *out_total, bunny_core_download_outcome_t *out_outcome, char *out_error, size_t out_error_cap)
{
    for (int i = 0; i < 2000; i++) {
        bool done = false;
        bunny_core_result_t result = bunny_core_download_poll(handle, out_received, out_total, &done, out_outcome, out_error, out_error_cap);
        TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
        if (done) {
            return;
        }
        usleep(1000);
    }
    TEST_FAIL_MESSAGE("download never finished");
}

static char *read_whole_file(const char *path, long *out_len)
{
    FILE *f = fopen(path, "rb");
    if (!f) {
        return NULL;
    }
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *buf = malloc((size_t)len + 1);
    fread(buf, 1, (size_t)len, f);
    buf[len] = '\0';
    fclose(f);
    *out_len = len;
    return buf;
}

void test_downloads_and_verifies_a_matching_checksum(void)
{
    const char *body = "the quick brown fox jumps over the lazy dog";
    bunny_test_http_server_t *server = bunny_test_http_server_start("200 OK", body, strlen(body), 1);
    TEST_ASSERT_NOT_NULL(server);
    char *url = bunny_test_http_server_url(server);

    int64_t handle = -1;
    bunny_core_result_t start_result = bunny_core_download_start(url, NULL, 0, g_dest_dir, "42.png", NULL, &handle);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, start_result);
    TEST_ASSERT_TRUE(handle >= 0);

    int64_t received = 0, total = 0;
    bunny_core_download_outcome_t outcome;
    poll_until_done(handle, &received, &total, &outcome, NULL, 0);
    bunny_test_http_server_join(server);
    bunny_core_download_release(handle);

    TEST_ASSERT_EQUAL(BUNNY_CORE_DOWNLOAD_VERIFIED, outcome);
    TEST_ASSERT_EQUAL((int64_t)strlen(body), received);

    char path[400];
    snprintf(path, sizeof(path), "%s/42.png", g_dest_dir);
    long len = 0;
    char *contents = read_whole_file(path, &len);
    TEST_ASSERT_NOT_NULL(contents);
    TEST_ASSERT_EQUAL((long)strlen(body), len);
    TEST_ASSERT_EQUAL_STRING_LEN(body, contents, (size_t)len);

    free(contents);
    free(url);
}

void test_reports_checksum_mismatch_but_still_writes_the_file(void)
{
    const char *body = "some bytes that will not match the published checksum";
    bunny_test_http_server_t *server = bunny_test_http_server_start("200 OK", body, strlen(body), 1);
    TEST_ASSERT_NOT_NULL(server);
    char *url = bunny_test_http_server_url(server);

    int64_t handle = -1;
    bunny_core_download_start(url, NULL, 0, g_dest_dir, "42.png", "0000000000000000000000000000000", &handle);

    int64_t received = 0, total = 0;
    bunny_core_download_outcome_t outcome;
    poll_until_done(handle, &received, &total, &outcome, NULL, 0);
    bunny_test_http_server_join(server);
    bunny_core_download_release(handle);

    TEST_ASSERT_EQUAL(BUNNY_CORE_DOWNLOAD_CHECKSUM_MISMATCH, outcome);

    char path[400];
    snprintf(path, sizeof(path), "%s/42.png", g_dest_dir);
    long len = 0;
    char *contents = read_whole_file(path, &len);
    TEST_ASSERT_NOT_NULL(contents);
    TEST_ASSERT_EQUAL((long)strlen(body), len);

    free(contents);
    free(url);
}

void test_an_http_error_status_fails(void)
{
    bunny_test_http_server_t *server = bunny_test_http_server_start("500 Internal Server Error", NULL, 0, 1);
    TEST_ASSERT_NOT_NULL(server);
    char *url = bunny_test_http_server_url(server);

    int64_t handle = -1;
    bunny_core_download_start(url, NULL, 0, g_dest_dir, "42.png", NULL, &handle);

    int64_t received = 0, total = 0;
    bunny_core_download_outcome_t outcome;
    char error[256];
    poll_until_done(handle, &received, &total, &outcome, error, sizeof(error));
    bunny_test_http_server_join(server);
    bunny_core_download_release(handle);

    TEST_ASSERT_EQUAL(BUNNY_CORE_DOWNLOAD_FAILED, outcome);
    TEST_ASSERT_EQUAL_STRING("HTTP 500", error);

    free(url);
}

/* The skip-fetch fast path (M66): a file already sitting at dest_dir/
 * filename with a matching checksum must short-circuit before any network
 * I/O at all -- proven here by pointing file_url at a port nothing is
 * listening on; if the fetch were actually attempted, this would fail. */
void test_skips_the_fetch_when_a_verified_file_already_exists(void)
{
    const char *body = "already on disk from a previous run";
    char dir_cmd[300];
    snprintf(dir_cmd, sizeof(dir_cmd), "mkdir -p '%s'", g_dest_dir);
    system(dir_cmd);
    char path[400];
    snprintf(path, sizeof(path), "%s/42.png", g_dest_dir);
    FILE *f = fopen(path, "wb");
    fwrite(body, 1, strlen(body), f);
    fclose(f);

    int64_t handle = -1;
    bunny_core_result_t start_result = bunny_core_download_start("http://127.0.0.1:1/unreachable", NULL, 0, g_dest_dir, "42.png", NULL, &handle);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, start_result);

    int64_t received = 0, total = 0;
    bunny_core_download_outcome_t outcome;
    poll_until_done(handle, &received, &total, &outcome, NULL, 0);
    bunny_core_download_release(handle);

    TEST_ASSERT_EQUAL(BUNNY_CORE_DOWNLOAD_VERIFIED, outcome);
}

void test_poll_and_release_reject_an_unknown_handle(void)
{
    int64_t received = 0, total = 0;
    bool done = false;
    TEST_ASSERT_EQUAL(BUNNY_CORE_ERR_NOT_FOUND, bunny_core_download_poll(999, &received, &total, &done, NULL, NULL, 0));
    bunny_core_download_release(999); /* must not crash */
}

void test_start_rejects_missing_required_arguments(void)
{
    int64_t handle = -1;
    TEST_ASSERT_EQUAL(BUNNY_CORE_ERR_INVALID_ARG, bunny_core_download_start(NULL, NULL, 0, g_dest_dir, "42.png", NULL, &handle));
    TEST_ASSERT_EQUAL(BUNNY_CORE_ERR_INVALID_ARG, bunny_core_download_start("http://x/y", NULL, 0, NULL, "42.png", NULL, &handle));
    TEST_ASSERT_EQUAL(BUNNY_CORE_ERR_INVALID_ARG, bunny_core_download_start("http://x/y", NULL, 0, g_dest_dir, NULL, NULL, &handle));
    TEST_ASSERT_EQUAL(BUNNY_CORE_ERR_INVALID_ARG, bunny_core_download_start("http://x/y", NULL, 0, g_dest_dir, "42.png", NULL, NULL));
}

/* Several concurrent downloads must not race on their own temp files or
 * clobber each other's output, even when they target the same destination
 * directory -- mirrors DownloadQueueService's own 3-way concurrency. */
void test_several_concurrent_downloads_each_land_correctly(void)
{
    const char *bodies[3] = {"first file contents", "second file contents, a bit longer", "third"};
    bunny_test_http_server_t *servers[3];
    char *urls[3];
    int64_t handles[3];

    for (int i = 0; i < 3; i++) {
        servers[i] = bunny_test_http_server_start("200 OK", bodies[i], strlen(bodies[i]), 1);
        TEST_ASSERT_NOT_NULL(servers[i]);
        urls[i] = bunny_test_http_server_url(servers[i]);
        char filename[32];
        snprintf(filename, sizeof(filename), "file%d.bin", i);
        bunny_core_result_t start_result = bunny_core_download_start(urls[i], NULL, 0, g_dest_dir, filename, NULL, &handles[i]);
        TEST_ASSERT_EQUAL(BUNNY_CORE_OK, start_result);
    }

    for (int i = 0; i < 3; i++) {
        int64_t received = 0, total = 0;
        bunny_core_download_outcome_t outcome;
        poll_until_done(handles[i], &received, &total, &outcome, NULL, 0);
        bunny_test_http_server_join(servers[i]);
        bunny_core_download_release(handles[i]);
        TEST_ASSERT_EQUAL(BUNNY_CORE_DOWNLOAD_VERIFIED, outcome);

        char path[400];
        snprintf(path, sizeof(path), "%s/file%d.bin", g_dest_dir, i);
        long len = 0;
        char *contents = read_whole_file(path, &len);
        TEST_ASSERT_NOT_NULL(contents);
        TEST_ASSERT_EQUAL_STRING_LEN(bodies[i], contents, (size_t)len);
        free(contents);
        free(urls[i]);
    }
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_downloads_and_verifies_a_matching_checksum);
    RUN_TEST(test_reports_checksum_mismatch_but_still_writes_the_file);
    RUN_TEST(test_an_http_error_status_fails);
    RUN_TEST(test_skips_the_fetch_when_a_verified_file_already_exists);
    RUN_TEST(test_poll_and_release_reject_an_unknown_handle);
    RUN_TEST(test_start_rejects_missing_required_arguments);
    RUN_TEST(test_several_concurrent_downloads_each_land_correctly);
    return UNITY_END();
}
