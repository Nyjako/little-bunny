#include "unity.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "auth.h"

static char g_tmp_dir[] = "/tmp/bunny_server_test_auth_XXXXXX";

void setUp(void)
{
    strcpy(g_tmp_dir, "/tmp/bunny_server_test_auth_XXXXXX");
    TEST_ASSERT_NOT_NULL(mkdtemp(g_tmp_dir));
}

void tearDown(void)
{
    char path[512];
    snprintf(path, sizeof(path), "%s/auth_token", g_tmp_dir);
    unlink(path);
    rmdir(g_tmp_dir);
}

void test_generates_token_on_first_load(void)
{
    server_auth_t *auth = server_auth_load(g_tmp_dir);
    TEST_ASSERT_NOT_NULL(auth);
    TEST_ASSERT_NOT_NULL(auth->token);
    TEST_ASSERT_EQUAL(64, (int)strlen(auth->token));

    char path[512];
    snprintf(path, sizeof(path), "%s/auth_token", g_tmp_dir);
    struct stat st;
    TEST_ASSERT_EQUAL(0, stat(path, &st));
    TEST_ASSERT_EQUAL(0600, st.st_mode & 0777);

    server_auth_free(auth);
}

void test_reuses_existing_token(void)
{
    server_auth_t *first = server_auth_load(g_tmp_dir);
    TEST_ASSERT_NOT_NULL(first);
    char *first_token = strdup(first->token);
    server_auth_free(first);

    server_auth_t *second = server_auth_load(g_tmp_dir);
    TEST_ASSERT_NOT_NULL(second);
    TEST_ASSERT_EQUAL_STRING(first_token, second->token);

    free(first_token);
    server_auth_free(second);
}

void test_verify_correct_and_wrong_token(void)
{
    server_auth_t *auth = server_auth_load(g_tmp_dir);
    TEST_ASSERT_NOT_NULL(auth);

    TEST_ASSERT_TRUE(server_auth_verify(auth, auth->token));
    TEST_ASSERT_FALSE(server_auth_verify(auth, "wrong-token"));
    TEST_ASSERT_FALSE(server_auth_verify(auth, NULL));
    TEST_ASSERT_FALSE(server_auth_verify(NULL, auth->token));

    server_auth_free(auth);
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_generates_token_on_first_load);
    RUN_TEST(test_reuses_existing_token);
    RUN_TEST(test_verify_correct_and_wrong_token);
    return UNITY_END();
}
