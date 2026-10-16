#include "unity.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "log.h"

void setUp(void)
{
    server_log_init(); /* idempotent -- this module has no other entry point that calls it in a standalone test binary */
    server_log_reset();
}

void tearDown(void)
{
    server_log_reset();
}

static void free_snapshot(char **lines, size_t count)
{
    for (size_t i = 0; i < count; i++) {
        free(lines[i]);
    }
    free(lines);
}

void test_empty_buffer_returns_zero(void)
{
    char **lines = NULL;
    size_t count = server_log_snapshot(&lines);
    TEST_ASSERT_EQUAL(0, (int)count);
    TEST_ASSERT_NULL(lines);
}

void test_snapshot_is_oldest_first(void)
{
    server_log("INFO", "first");
    server_log("INFO", "second");
    server_log("INFO", "third");

    char **lines = NULL;
    size_t count = server_log_snapshot(&lines);
    TEST_ASSERT_EQUAL(3, (int)count);
    TEST_ASSERT_TRUE(strstr(lines[0], "first") != NULL);
    TEST_ASSERT_TRUE(strstr(lines[1], "second") != NULL);
    TEST_ASSERT_TRUE(strstr(lines[2], "third") != NULL);
    TEST_ASSERT_TRUE(strstr(lines[0], "[INFO]") != NULL);

    free_snapshot(lines, count);
}

void test_buffer_overwrites_oldest_at_capacity(void)
{
    char message[32];
    for (int i = 0; i < 205; i++) {
        snprintf(message, sizeof(message), "line-%d", i);
        server_log("INFO", "%s", message);
    }

    char **lines = NULL;
    size_t count = server_log_snapshot(&lines);
    TEST_ASSERT_EQUAL(200, (int)count);
    TEST_ASSERT_TRUE(strstr(lines[0], "line-5") != NULL);
    TEST_ASSERT_TRUE(strstr(lines[count - 1], "line-204") != NULL);

    free_snapshot(lines, count);
}

void test_reset_clears_buffer(void)
{
    server_log("INFO", "something");
    server_log_reset();

    char **lines = NULL;
    size_t count = server_log_snapshot(&lines);
    TEST_ASSERT_EQUAL(0, (int)count);
    TEST_ASSERT_NULL(lines);
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_empty_buffer_returns_zero);
    RUN_TEST(test_snapshot_is_oldest_first);
    RUN_TEST(test_buffer_overwrites_oldest_at_capacity);
    RUN_TEST(test_reset_clears_buffer);
    return UNITY_END();
}
