#include "unity.h"

#include <cJSON.h>
#include <qrcodegen.h>
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

/* --- server_qr_render_png (pure, offline) -------------------------------- */

void test_render_png_produces_a_valid_png_signature(void)
{
    char *payload = server_qr_build_connection_json("https://1.2.3.4:4433", "sometoken", "DEADBEEF");
    TEST_ASSERT_NOT_NULL(payload);

    uint8_t qrcode[qrcodegen_BUFFER_LEN_MAX];
    uint8_t temp_buffer[qrcodegen_BUFFER_LEN_MAX];
    bool encoded = qrcodegen_encodeText(payload, temp_buffer, qrcode, qrcodegen_Ecc_LOW, qrcodegen_VERSION_MIN, qrcodegen_VERSION_MAX, qrcodegen_Mask_AUTO, true);
    free(payload);
    TEST_ASSERT_TRUE(encoded);

    uint8_t *png_data = NULL;
    size_t png_len = 0;
    bool ok = server_qr_render_png(qrcode, &png_data, &png_len);
    TEST_ASSERT_TRUE(ok);
    TEST_ASSERT_NOT_NULL(png_data);
    TEST_ASSERT_GREATER_THAN(8, png_len);

    static const uint8_t png_signature[8] = {0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'};
    TEST_ASSERT_EQUAL_MEMORY(png_signature, png_data, sizeof(png_signature));

    free(png_data);
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_build_connection_json_includes_all_three_fields);
    RUN_TEST(test_build_connection_json_treats_null_fields_as_empty_strings);
    RUN_TEST(test_render_png_produces_a_valid_png_signature);
    return UNITY_END();
}
