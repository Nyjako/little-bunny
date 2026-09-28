#include "unity.h"

#include <string.h>

#include "bunny_core/core.h"

static bunny_core_t *g_core;

void setUp(void)
{
    bunny_core_config_t config;
    memset(&config, 0, sizeof(config));
    config.db_path = ":memory:";
    config.user_agent = "bunny-tests/1.0 (unit tests)";

    bunny_core_result_t result = bunny_core_open(&config, &g_core);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_NOT_NULL(g_core);
}

void tearDown(void)
{
    bunny_core_close(g_core);
    g_core = NULL;
}

void test_open_close(void)
{
    bunny_core_close(NULL);
}

void test_account_set_and_get(void)
{
    bunny_core_result_t result = bunny_core_account_set(g_core, BUNNY_DB_SITE_E621, "someuser", "someapikey");
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);

    bunny_db_account_t account;
    result = bunny_core_account_get(g_core, BUNNY_DB_SITE_E621, &account);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL_STRING("someuser", account.username);
    TEST_ASSERT_EQUAL_STRING("someapikey", account.secret);
    bunny_db_account_free(&account);
}

void test_account_set_upserts(void)
{
    bunny_core_account_set(g_core, BUNNY_DB_SITE_E621, "user1", "secret1");
    bunny_core_account_set(g_core, BUNNY_DB_SITE_E621, "user2", "secret2");

    bunny_db_account_t account;
    bunny_core_account_get(g_core, BUNNY_DB_SITE_E621, &account);
    TEST_ASSERT_EQUAL_STRING("user2", account.username);
    TEST_ASSERT_EQUAL_STRING("secret2", account.secret);
    bunny_db_account_free(&account);
}

void test_account_get_not_found(void)
{
    bunny_db_account_t account;
    bunny_core_result_t result = bunny_core_account_get(g_core, BUNNY_DB_SITE_INKBUNNY, &account);
    TEST_ASSERT_EQUAL(BUNNY_CORE_ERR_NOT_FOUND, result);
}

void test_account_delete(void)
{
    bunny_core_account_set(g_core, BUNNY_DB_SITE_E621, "user", "secret");

    bunny_core_result_t result = bunny_core_account_delete(g_core, BUNNY_DB_SITE_E621);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);

    bunny_db_account_t account;
    result = bunny_core_account_get(g_core, BUNNY_DB_SITE_E621, &account);
    TEST_ASSERT_EQUAL(BUNNY_CORE_ERR_NOT_FOUND, result);
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_open_close);
    RUN_TEST(test_account_set_and_get);
    RUN_TEST(test_account_set_upserts);
    RUN_TEST(test_account_get_not_found);
    RUN_TEST(test_account_delete);
    return UNITY_END();
}
