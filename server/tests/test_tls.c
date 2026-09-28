#include "unity.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "tls.h"

static char g_tmp_dir[] = "/tmp/bunny_server_test_tls_XXXXXX";

void setUp(void)
{
    strcpy(g_tmp_dir, "/tmp/bunny_server_test_tls_XXXXXX");
    TEST_ASSERT_NOT_NULL(mkdtemp(g_tmp_dir));
}

void tearDown(void)
{
    char path[512];
    snprintf(path, sizeof(path), "%s/server.pem", g_tmp_dir);
    unlink(path);
    rmdir(g_tmp_dir);
}

void test_generates_cert_on_first_call(void)
{
    char *path = server_tls_ensure_cert(g_tmp_dir);
    TEST_ASSERT_NOT_NULL(path);

    struct stat st;
    TEST_ASSERT_EQUAL(0, stat(path, &st));
    TEST_ASSERT_TRUE(st.st_size > 0);
    TEST_ASSERT_EQUAL(0600, st.st_mode & 0777);

    free(path);
}

void test_reuses_existing_cert(void)
{
    char *first_path = server_tls_ensure_cert(g_tmp_dir);
    TEST_ASSERT_NOT_NULL(first_path);

    struct stat first_st;
    TEST_ASSERT_EQUAL(0, stat(first_path, &first_st));

    char *second_path = server_tls_ensure_cert(g_tmp_dir);
    TEST_ASSERT_NOT_NULL(second_path);
    TEST_ASSERT_EQUAL_STRING(first_path, second_path);

    struct stat second_st;
    TEST_ASSERT_EQUAL(0, stat(second_path, &second_st));
    TEST_ASSERT_EQUAL(first_st.st_mtime, second_st.st_mtime); /* not regenerated */

    free(first_path);
    free(second_path);
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_generates_cert_on_first_call);
    RUN_TEST(test_reuses_existing_cert);
    return UNITY_END();
}
