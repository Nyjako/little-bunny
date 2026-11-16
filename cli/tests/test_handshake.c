#include "unity.h"

#include "handshake.h"

#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <stdio.h>
static void set_env(const char *name, const char *value)
{
    _putenv_s(name, value);
}
static void unset_env(const char *name)
{
    _putenv_s(name, "");
}
#else
static void set_env(const char *name, const char *value)
{
    setenv(name, value, 1);
}
static void unset_env(const char *name)
{
    unsetenv(name);
}
#endif

#ifndef FAKE_APP_HANDSHAKE_PATH
#error "FAKE_APP_HANDSHAKE_PATH must be defined by CMake to the built fixture's path"
#endif

void setUp(void)
{
    unset_env("BUNNY_CLI_TEST_SECRET");
    unset_env("BUNNY_CLI_TEST_MODE");
    unset_env("BUNNY_CLI_TEST_BEHAVIOR");
    unset_env("BUNNY_CLI_TEST_NO_DOWNLOAD_FOLDER");
    unset_env("BUNNY_CLI_TEST_NO_QUEUE_DB");
    unset_env("BUNNY_CLI_TEST_AUTO_FAVORITE");
    unset_env("BUNNY_CLI_TEST_AUTO_UPVOTE");
}

void tearDown(void)
{}

void test_unlocked_standalone_round_trips_the_right_payload(void)
{
    bunny_cli_handshake_payload_t payload;
    bunny_cli_handshake_result_t result = bunny_cli_handshake_run(FAKE_APP_HANDSHAKE_PATH, NULL, &payload);

    TEST_ASSERT_EQUAL(BUNNY_CLI_HANDSHAKE_OK, result);
    TEST_ASSERT_EQUAL(BUNNY_CLI_MODE_STANDALONE, payload.mode);
    TEST_ASSERT_EQUAL_STRING("/fake/bunny.db", payload.db_path);
    TEST_ASSERT_EQUAL_STRING("LittleBunny/1.0.0", payload.user_agent);
    TEST_ASSERT_EQUAL_STRING("/fake/downloads", payload.download_destination_folder);
    TEST_ASSERT_NULL(payload.server_base_url);
    TEST_ASSERT_FALSE(payload.auto_favorite_on_download);
    TEST_ASSERT_FALSE(payload.auto_upvote_on_download);

    bunny_cli_handshake_payload_free(&payload);
    TEST_ASSERT_NULL(payload.db_path);
}

/* The app's own global DownloadSettingsStore toggles -- mode-independent,
 * so one test covers both (networked mode's own test above already covers
 * the "reported, but both off" default for that mode). */
void test_auto_favorite_and_upvote_on_download_are_reported_when_enabled(void)
{
    set_env("BUNNY_CLI_TEST_AUTO_FAVORITE", "1");
    set_env("BUNNY_CLI_TEST_AUTO_UPVOTE", "1");

    bunny_cli_handshake_payload_t payload;
    bunny_cli_handshake_result_t result = bunny_cli_handshake_run(FAKE_APP_HANDSHAKE_PATH, NULL, &payload);

    TEST_ASSERT_EQUAL(BUNNY_CLI_HANDSHAKE_OK, result);
    TEST_ASSERT_TRUE(payload.auto_favorite_on_download);
    TEST_ASSERT_TRUE(payload.auto_upvote_on_download);

    bunny_cli_handshake_payload_free(&payload);
}

void test_a_null_download_destination_folder_is_reported_as_null_not_a_protocol_error(void)
{
    set_env("BUNNY_CLI_TEST_NO_DOWNLOAD_FOLDER", "1");

    bunny_cli_handshake_payload_t payload;
    bunny_cli_handshake_result_t result = bunny_cli_handshake_run(FAKE_APP_HANDSHAKE_PATH, NULL, &payload);

    TEST_ASSERT_EQUAL(BUNNY_CLI_HANDSHAKE_OK, result);
    TEST_ASSERT_EQUAL(BUNNY_CLI_MODE_STANDALONE, payload.mode);
    TEST_ASSERT_NULL(payload.download_destination_folder);
    bunny_cli_handshake_payload_free(&payload);
}

void test_networked_mode_round_trips_server_url_bearer_token_and_cert_fingerprint(void)
{
    set_env("BUNNY_CLI_TEST_MODE", "networked");

    bunny_cli_handshake_payload_t payload;
    bunny_cli_handshake_result_t result = bunny_cli_handshake_run(FAKE_APP_HANDSHAKE_PATH, NULL, &payload);

    TEST_ASSERT_EQUAL(BUNNY_CLI_HANDSHAKE_OK, result);
    TEST_ASSERT_EQUAL(BUNNY_CLI_MODE_NETWORKED, payload.mode);
    TEST_ASSERT_EQUAL_STRING("https://bunny.example:9443", payload.server_base_url);
    TEST_ASSERT_EQUAL_STRING("test-token", payload.bearer_token);
    TEST_ASSERT_EQUAL_STRING("abc123", payload.cert_fingerprint);
    TEST_ASSERT_EQUAL_STRING("/fake/downloads", payload.download_destination_folder);
    TEST_ASSERT_EQUAL_STRING("/fake/downloads.db", payload.download_queue_db_path);
    TEST_ASSERT_EQUAL_STRING("LittleBunny/1.0.0", payload.download_queue_user_agent);
    TEST_ASSERT_NULL(payload.db_path);
    TEST_ASSERT_FALSE(payload.auto_favorite_on_download);
    TEST_ASSERT_FALSE(payload.auto_upvote_on_download);

    bunny_cli_handshake_payload_free(&payload);
}

/* An app build from before downloadQueueDbPath/downloadQueueUserAgent
 * existed -- --download/--queue-list can't work against it (no local queue
 * db to claim rows from), but every other networked command still can, so
 * this must parse as a perfectly normal BUNNY_CLI_HANDSHAKE_OK, not a
 * protocol error. */
void test_networked_mode_with_no_queue_db_fields_still_parses_normally(void)
{
    set_env("BUNNY_CLI_TEST_MODE", "networked");
    set_env("BUNNY_CLI_TEST_NO_QUEUE_DB", "1");

    bunny_cli_handshake_payload_t payload;
    bunny_cli_handshake_result_t result = bunny_cli_handshake_run(FAKE_APP_HANDSHAKE_PATH, NULL, &payload);

    TEST_ASSERT_EQUAL(BUNNY_CLI_HANDSHAKE_OK, result);
    TEST_ASSERT_EQUAL(BUNNY_CLI_MODE_NETWORKED, payload.mode);
    TEST_ASSERT_EQUAL_STRING("https://bunny.example:9443", payload.server_base_url);
    TEST_ASSERT_NULL(payload.download_queue_db_path);
    TEST_ASSERT_NULL(payload.download_queue_user_agent);

    bunny_cli_handshake_payload_free(&payload);
}

void test_no_repository_configured_yet_reports_mode_none(void)
{
    set_env("BUNNY_CLI_TEST_MODE", "none");

    bunny_cli_handshake_payload_t payload;
    bunny_cli_handshake_result_t result = bunny_cli_handshake_run(FAKE_APP_HANDSHAKE_PATH, NULL, &payload);

    TEST_ASSERT_EQUAL(BUNNY_CLI_HANDSHAKE_OK, result);
    TEST_ASSERT_EQUAL(BUNNY_CLI_MODE_NONE, payload.mode);
    TEST_ASSERT_NULL(payload.db_path);
}

void test_correct_secret_unlocks_it(void)
{
    set_env("BUNNY_CLI_TEST_SECRET", "my-pin");

    bunny_cli_handshake_payload_t payload;
    bunny_cli_handshake_result_t result = bunny_cli_handshake_run(FAKE_APP_HANDSHAKE_PATH, "my-pin", &payload);

    TEST_ASSERT_EQUAL(BUNNY_CLI_HANDSHAKE_OK, result);
    TEST_ASSERT_EQUAL(BUNNY_CLI_MODE_STANDALONE, payload.mode);

    bunny_cli_handshake_payload_free(&payload);
}

void test_wrong_secret_reports_locked_without_ever_producing_a_config(void)
{
    set_env("BUNNY_CLI_TEST_SECRET", "my-pin");

    bunny_cli_handshake_payload_t payload;
    bunny_cli_handshake_result_t result = bunny_cli_handshake_run(FAKE_APP_HANDSHAKE_PATH, "wrong-pin", &payload);

    TEST_ASSERT_EQUAL(BUNNY_CLI_HANDSHAKE_LOCKED, result);
    TEST_ASSERT_EQUAL(BUNNY_CLI_MODE_NONE, payload.mode);
    TEST_ASSERT_NULL(payload.db_path);
    TEST_ASSERT_NULL(payload.server_base_url);
}

void test_no_supplied_secret_against_a_locked_app_reports_locked(void)
{
    set_env("BUNNY_CLI_TEST_SECRET", "my-pin");

    bunny_cli_handshake_payload_t payload;
    bunny_cli_handshake_result_t result = bunny_cli_handshake_run(FAKE_APP_HANDSHAKE_PATH, NULL, &payload);

    TEST_ASSERT_EQUAL(BUNNY_CLI_HANDSHAKE_LOCKED, result);
}

void test_app_executable_not_found_is_reported_distinctly_not_a_crash(void)
{
    bunny_cli_handshake_payload_t payload;
    bunny_cli_handshake_result_t result = bunny_cli_handshake_run("/path/that/does/not/exist/at/all", NULL, &payload);

    TEST_ASSERT_EQUAL(BUNNY_CLI_HANDSHAKE_APP_NOT_FOUND, result);
}

void test_app_crashing_before_writing_anything_is_a_protocol_error_not_a_hang(void)
{
    set_env("BUNNY_CLI_TEST_BEHAVIOR", "crash");

    bunny_cli_handshake_payload_t payload;
    bunny_cli_handshake_result_t result = bunny_cli_handshake_run(FAKE_APP_HANDSHAKE_PATH, NULL, &payload);

    TEST_ASSERT_EQUAL(BUNNY_CLI_HANDSHAKE_PROTOCOL_ERROR, result);
}

void test_garbage_non_json_output_is_a_protocol_error(void)
{
    set_env("BUNNY_CLI_TEST_BEHAVIOR", "garbage");

    bunny_cli_handshake_payload_t payload;
    bunny_cli_handshake_result_t result = bunny_cli_handshake_run(FAKE_APP_HANDSHAKE_PATH, NULL, &payload);

    TEST_ASSERT_EQUAL(BUNNY_CLI_HANDSHAKE_PROTOCOL_ERROR, result);
}

void test_a_slow_app_still_succeeds_once_it_finally_responds(void)
{
    set_env("BUNNY_CLI_TEST_BEHAVIOR", "slow");

    bunny_cli_handshake_payload_t payload;
    bunny_cli_handshake_result_t result = bunny_cli_handshake_run(FAKE_APP_HANDSHAKE_PATH, NULL, &payload);

    TEST_ASSERT_EQUAL(BUNNY_CLI_HANDSHAKE_OK, result);
    bunny_cli_handshake_payload_free(&payload);
}

void test_finds_the_real_response_among_native_plugin_noise_on_stdout(void)
{
    /* Regression: a real Flutter build's own linked native plugins
     * (confirmed live with media_kit/fvp) can print their own banner text
     * to stdout before the app's real handshake response -- bunny_cli must
     * not mistake that for the response and must not simply read "the
     * first line". */
    set_env("BUNNY_CLI_TEST_BEHAVIOR", "noisy_stdout");

    bunny_cli_handshake_payload_t payload;
    bunny_cli_handshake_result_t result = bunny_cli_handshake_run(FAKE_APP_HANDSHAKE_PATH, NULL, &payload);

    TEST_ASSERT_EQUAL(BUNNY_CLI_HANDSHAKE_OK, result);
    TEST_ASSERT_EQUAL(BUNNY_CLI_MODE_STANDALONE, payload.mode);
    TEST_ASSERT_EQUAL_STRING("/fake/bunny.db", payload.db_path);
    bunny_cli_handshake_payload_free(&payload);
}

void test_valid_json_with_no_trailing_newline_still_parses(void)
{
    set_env("BUNNY_CLI_TEST_BEHAVIOR", "no_newline");

    bunny_cli_handshake_payload_t payload;
    bunny_cli_handshake_result_t result = bunny_cli_handshake_run(FAKE_APP_HANDSHAKE_PATH, NULL, &payload);

    TEST_ASSERT_EQUAL(BUNNY_CLI_HANDSHAKE_OK, result);
    TEST_ASSERT_EQUAL(BUNNY_CLI_MODE_STANDALONE, payload.mode);
    bunny_cli_handshake_payload_free(&payload);
}

void test_null_app_exe_path_is_a_protocol_error_not_a_crash(void)
{
    bunny_cli_handshake_payload_t payload;
    bunny_cli_handshake_result_t result = bunny_cli_handshake_run(NULL, NULL, &payload);

    TEST_ASSERT_EQUAL(BUNNY_CLI_HANDSHAKE_PROTOCOL_ERROR, result);
}

void test_find_app_executable_resolves_to_little_bunny_next_to_this_process(void)
{
    char *path = bunny_cli_find_app_executable();
    TEST_ASSERT_NOT_NULL(path);
#ifdef _WIN32
    TEST_ASSERT_NOT_NULL(strstr(path, "little_bunny.exe"));
#else
    TEST_ASSERT_NOT_NULL(strstr(path, "little_bunny"));
#endif
    free(path);
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_unlocked_standalone_round_trips_the_right_payload);
    RUN_TEST(test_a_null_download_destination_folder_is_reported_as_null_not_a_protocol_error);
    RUN_TEST(test_networked_mode_round_trips_server_url_bearer_token_and_cert_fingerprint);
    RUN_TEST(test_networked_mode_with_no_queue_db_fields_still_parses_normally);
    RUN_TEST(test_auto_favorite_and_upvote_on_download_are_reported_when_enabled);
    RUN_TEST(test_no_repository_configured_yet_reports_mode_none);
    RUN_TEST(test_correct_secret_unlocks_it);
    RUN_TEST(test_wrong_secret_reports_locked_without_ever_producing_a_config);
    RUN_TEST(test_no_supplied_secret_against_a_locked_app_reports_locked);
    RUN_TEST(test_app_executable_not_found_is_reported_distinctly_not_a_crash);
    RUN_TEST(test_app_crashing_before_writing_anything_is_a_protocol_error_not_a_hang);
    RUN_TEST(test_garbage_non_json_output_is_a_protocol_error);
    RUN_TEST(test_a_slow_app_still_succeeds_once_it_finally_responds);
    RUN_TEST(test_finds_the_real_response_among_native_plugin_noise_on_stdout);
    RUN_TEST(test_valid_json_with_no_trailing_newline_still_parses);
    RUN_TEST(test_null_app_exe_path_is_a_protocol_error_not_a_crash);
    RUN_TEST(test_find_app_executable_resolves_to_little_bunny_next_to_this_process);
    return UNITY_END();
}
