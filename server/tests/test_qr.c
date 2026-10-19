#include "unity.h"

#include <cJSON.h>
#include <stdlib.h>
#include <string.h>

#include "qr.h"

void setUp(void) {}
void tearDown(void) {}

/* --- server_qr_build_connection_json (pure, offline) -------------------- */

void test_build_connection_json_includes_all_three_fields(void)
{
    char *payload = server_qr_build_connection_json("https://1.2.3.4:4433", "sometoken", "DEADBEEF");
    TEST_ASSERT_NOT_NULL(payload);

    cJSON *json = cJSON_Parse(payload);
    TEST_ASSERT_NOT_NULL(json);
    TEST_ASSERT_EQUAL_STRING("https://1.2.3.4:4433", cJSON_GetObjectItem(json, "server_url")->valuestring);
    TEST_ASSERT_EQUAL_STRING("sometoken", cJSON_GetObjectItem(json, "bearer_token")->valuestring);
    TEST_ASSERT_EQUAL_STRING("DEADBEEF", cJSON_GetObjectItem(json, "cert_sha256")->valuestring);

    cJSON_Delete(json);
    free(payload);
}

void test_build_connection_json_treats_null_fields_as_empty_strings(void)
{
    char *payload = server_qr_build_connection_json(NULL, NULL, NULL);
    TEST_ASSERT_NOT_NULL(payload);

    cJSON *json = cJSON_Parse(payload);
    TEST_ASSERT_NOT_NULL(json);
    TEST_ASSERT_EQUAL_STRING("", cJSON_GetObjectItem(json, "server_url")->valuestring);
    TEST_ASSERT_EQUAL_STRING("", cJSON_GetObjectItem(json, "bearer_token")->valuestring);
    TEST_ASSERT_EQUAL_STRING("", cJSON_GetObjectItem(json, "cert_sha256")->valuestring);

    cJSON_Delete(json);
    free(payload);
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_build_connection_json_includes_all_three_fields);
    RUN_TEST(test_build_connection_json_treats_null_fields_as_empty_strings);
    return UNITY_END();
}
