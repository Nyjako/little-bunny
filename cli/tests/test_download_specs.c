#include "unity.h"

#include "commands.h"

void setUp(void)
{}
void tearDown(void)
{}

void test_a_pool_spec_parses_its_id(void)
{
    bunny_cli_spec_kind_t kind;
    int64_t id = 0;
    TEST_ASSERT_TRUE(bunny_cli_parse_download_spec("pool:115522", &kind, &id));
    TEST_ASSERT_EQUAL(BUNNY_CLI_SPEC_POOL, kind);
    TEST_ASSERT_EQUAL(115522, id);
}

void test_a_search_spec_parses_its_id(void)
{
    bunny_cli_spec_kind_t kind;
    int64_t id = 0;
    TEST_ASSERT_TRUE(bunny_cli_parse_download_spec("search:12", &kind, &id));
    TEST_ASSERT_EQUAL(BUNNY_CLI_SPEC_SEARCH, kind);
    TEST_ASSERT_EQUAL(12, id);
}

void test_a_bare_tag_query_is_a_tags_spec(void)
{
    bunny_cli_spec_kind_t kind;
    int64_t id = 0;
    TEST_ASSERT_TRUE(bunny_cli_parse_download_spec("female standing", &kind, &id));
    TEST_ASSERT_EQUAL(BUNNY_CLI_SPEC_TAGS, kind);
}

void test_a_tag_that_merely_contains_pool_colon_mid_string_is_still_a_tags_spec(void)
{
    /* Only a *prefix* match counts -- "pool:" has to start the spec. */
    bunny_cli_spec_kind_t kind;
    int64_t id = 0;
    TEST_ASSERT_TRUE(bunny_cli_parse_download_spec("not_a_pool:123", &kind, &id));
    TEST_ASSERT_EQUAL(BUNNY_CLI_SPEC_TAGS, kind);
}

void test_pool_with_no_id_is_rejected(void)
{
    bunny_cli_spec_kind_t kind;
    int64_t id = 0;
    TEST_ASSERT_FALSE(bunny_cli_parse_download_spec("pool:", &kind, &id));
}

void test_pool_with_a_non_numeric_id_is_rejected(void)
{
    bunny_cli_spec_kind_t kind;
    int64_t id = 0;
    TEST_ASSERT_FALSE(bunny_cli_parse_download_spec("pool:abc", &kind, &id));
}

void test_pool_with_trailing_garbage_after_the_id_is_rejected(void)
{
    bunny_cli_spec_kind_t kind;
    int64_t id = 0;
    TEST_ASSERT_FALSE(bunny_cli_parse_download_spec("pool:123abc", &kind, &id));
}

void test_pool_with_a_zero_id_is_rejected(void)
{
    bunny_cli_spec_kind_t kind;
    int64_t id = 0;
    TEST_ASSERT_FALSE(bunny_cli_parse_download_spec("pool:0", &kind, &id));
}

void test_pool_with_a_negative_id_is_rejected(void)
{
    bunny_cli_spec_kind_t kind;
    int64_t id = 0;
    TEST_ASSERT_FALSE(bunny_cli_parse_download_spec("pool:-5", &kind, &id));
}

void test_search_with_no_id_is_rejected(void)
{
    bunny_cli_spec_kind_t kind;
    int64_t id = 0;
    TEST_ASSERT_FALSE(bunny_cli_parse_download_spec("search:", &kind, &id));
}

void test_search_with_a_non_numeric_id_is_rejected(void)
{
    bunny_cli_spec_kind_t kind;
    int64_t id = 0;
    TEST_ASSERT_FALSE(bunny_cli_parse_download_spec("search:abc", &kind, &id));
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_a_pool_spec_parses_its_id);
    RUN_TEST(test_a_search_spec_parses_its_id);
    RUN_TEST(test_a_bare_tag_query_is_a_tags_spec);
    RUN_TEST(test_a_tag_that_merely_contains_pool_colon_mid_string_is_still_a_tags_spec);
    RUN_TEST(test_pool_with_no_id_is_rejected);
    RUN_TEST(test_pool_with_a_non_numeric_id_is_rejected);
    RUN_TEST(test_pool_with_trailing_garbage_after_the_id_is_rejected);
    RUN_TEST(test_pool_with_a_zero_id_is_rejected);
    RUN_TEST(test_pool_with_a_negative_id_is_rejected);
    RUN_TEST(test_search_with_no_id_is_rejected);
    RUN_TEST(test_search_with_a_non_numeric_id_is_rejected);
    return UNITY_END();
}
