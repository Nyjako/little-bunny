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
}

void tearDown(void)
{
    bunny_core_close(g_core);
    g_core = NULL;
}

void test_download_queue_add_and_list(void)
{
    int64_t id = 0;
    bunny_core_result_t result = bunny_core_download_queue_add(g_core, 42, 0, NULL, 0, &id);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_TRUE(id > 0);

    bunny_db_download_queue_list_t list;
    result = bunny_core_download_queue_list(g_core, &list);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(1, (int)list.count);
    TEST_ASSERT_EQUAL(id, list.items[0].id);
    TEST_ASSERT_EQUAL(42, list.items[0].post_id);
    TEST_ASSERT_EQUAL(BUNNY_DB_DOWNLOAD_QUEUE_QUEUED, list.items[0].status);
    bunny_db_download_queue_list_free(&list);
}

void test_download_queue_set_status(void)
{
    int64_t id = 0;
    bunny_core_download_queue_add(g_core, 7, 0, NULL, 0, &id);

    bunny_core_result_t result = bunny_core_download_queue_set_status(g_core, id, BUNNY_DB_DOWNLOAD_QUEUE_FAILED, "HTTP 500");
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);

    bunny_db_download_queue_list_t list;
    bunny_core_download_queue_list(g_core, &list);
    TEST_ASSERT_EQUAL(BUNNY_DB_DOWNLOAD_QUEUE_FAILED, list.items[0].status);
    TEST_ASSERT_EQUAL_STRING("HTTP 500", list.items[0].failure_reason);
    bunny_db_download_queue_list_free(&list);
}

void test_download_queue_clear_finished_drops_terminal_rows_only(void)
{
    int64_t queued_id = 0, failed_id = 0;
    bunny_core_download_queue_add(g_core, 1, 0, NULL, 0, &queued_id);
    bunny_core_download_queue_add(g_core, 2, 0, NULL, 0, &failed_id);
    bunny_core_download_queue_set_status(g_core, failed_id, BUNNY_DB_DOWNLOAD_QUEUE_FAILED, "oops");

    bunny_core_result_t result = bunny_core_download_queue_clear_finished(g_core);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);

    bunny_db_download_queue_list_t list;
    bunny_core_download_queue_list(g_core, &list);
    TEST_ASSERT_EQUAL(1, (int)list.count);
    TEST_ASSERT_EQUAL(queued_id, list.items[0].id);
    bunny_db_download_queue_list_free(&list);
}

void test_download_queue_claim_next_marks_downloading_and_skips_claimed_rows(void)
{
    int64_t first_id = 0, second_id = 0;
    bunny_core_download_queue_add(g_core, 10, 0, NULL, 0, &first_id);
    bunny_core_download_queue_add(g_core, 11, 0, NULL, 0, &second_id);

    bunny_db_download_queue_item_t item;
    bool found = false;
    bunny_core_result_t result = bunny_core_download_queue_claim_next(g_core, &item, &found);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_TRUE(found);
    TEST_ASSERT_EQUAL(first_id, item.id);
    bunny_db_download_queue_item_free(&item);

    result = bunny_core_download_queue_claim_next(g_core, &item, &found);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_TRUE(found);
    TEST_ASSERT_EQUAL(second_id, item.id);
    bunny_db_download_queue_item_free(&item);

    result = bunny_core_download_queue_claim_next(g_core, &item, &found);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_FALSE(found);
}

void test_download_queue_count_queued(void)
{
    int64_t queued_id = 0, downloading_id = 0;
    bunny_core_download_queue_add(g_core, 20, 0, NULL, 0, &queued_id);
    bunny_core_download_queue_add(g_core, 21, 0, NULL, 0, &downloading_id);
    bunny_core_download_queue_set_status(g_core, downloading_id, BUNNY_DB_DOWNLOAD_QUEUE_DOWNLOADING, NULL);

    int count = -1;
    bunny_core_result_t result = bunny_core_download_queue_count_queued(g_core, &count);
    TEST_ASSERT_EQUAL(BUNNY_CORE_OK, result);
    TEST_ASSERT_EQUAL(1, count);
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_download_queue_add_and_list);
    RUN_TEST(test_download_queue_set_status);
    RUN_TEST(test_download_queue_clear_finished_drops_terminal_rows_only);
    RUN_TEST(test_download_queue_claim_next_marks_downloading_and_skips_claimed_rows);
    RUN_TEST(test_download_queue_count_queued);
    return UNITY_END();
}
