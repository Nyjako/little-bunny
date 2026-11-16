#include "unity.h"

#include "destination.h"

#include <bunny_core/core.h>

#include <string.h>

/* Every expected string here is cross-checked against the exact same case
 * in app/test/services/download_manager_test.dart -- this module exists
 * specifically to keep bunny_cli's own downloads landing in the identical
 * place DownloadManager._destinationFor (Dart) already would. */

void setUp(void)
{}
void tearDown(void)
{}

void test_plain_artist_post_uses_the_artist_as_the_folder(void)
{
    char folder[BUNNY_CLI_DESTINATION_MAX];
    char filename[BUNNY_CLI_DESTINATION_MAX];
    bunny_cli_destination_for("someartist", "png", 1, 0, NULL, 0, folder, filename);

    TEST_ASSERT_EQUAL_STRING("someartist", folder);
    TEST_ASSERT_EQUAL_STRING("1.png", filename);
}

void test_illegal_characters_in_the_artist_name_are_sanitized(void)
{
    char folder[BUNNY_CLI_DESTINATION_MAX];
    char filename[BUNNY_CLI_DESTINATION_MAX];
    bunny_cli_destination_for("some/bad:artist", "png", 42, 0, NULL, 0, folder, filename);

    TEST_ASSERT_EQUAL_STRING("some_bad_artist", folder);
    TEST_ASSERT_EQUAL_STRING("42.png", filename);
}

void test_a_multi_artist_post_nests_each_artist_as_its_own_subfolder(void)
{
    char folder[BUNNY_CLI_DESTINATION_MAX];
    char filename[BUNNY_CLI_DESTINATION_MAX];
    bunny_cli_destination_for("artista, artistb", "png", 42, 0, NULL, 0, folder, filename);

    TEST_ASSERT_EQUAL_STRING("artista/artistb", folder);
}

void test_null_artist_falls_back_to_unknown(void)
{
    char folder[BUNNY_CLI_DESTINATION_MAX];
    char filename[BUNNY_CLI_DESTINATION_MAX];
    bunny_cli_destination_for(NULL, "png", 42, 0, NULL, 0, folder, filename);

    TEST_ASSERT_EQUAL_STRING("unknown", folder);
}

void test_pool_download_uses_the_pool_folder_and_page_numbered_filename(void)
{
    char folder[BUNNY_CLI_DESTINATION_MAX];
    char filename[BUNNY_CLI_DESTINATION_MAX];
    bunny_cli_destination_for(NULL, "png", 42, 1234, "My Comic", 7, folder, filename);

    TEST_ASSERT_EQUAL_STRING("pool_1234 - My Comic", folder);
    TEST_ASSERT_EQUAL_STRING("1234 - p0007 [42].png", filename);
}

void test_illegal_characters_in_the_pool_name_are_sanitized_same_as_the_artist_folder(void)
{
    char folder[BUNNY_CLI_DESTINATION_MAX];
    char filename[BUNNY_CLI_DESTINATION_MAX];
    bunny_cli_destination_for(NULL, "png", 42, 5, "Some/Bad:Comic", 1, folder, filename);

    TEST_ASSERT_EQUAL_STRING("pool_5 - Some_Bad_Comic", folder);
    TEST_ASSERT_EQUAL_STRING("5 - p0001 [42].png", filename);
}

void test_null_pool_name_falls_back_to_untitled(void)
{
    char folder[BUNNY_CLI_DESTINATION_MAX];
    char filename[BUNNY_CLI_DESTINATION_MAX];
    bunny_cli_destination_for(NULL, "png", 42, 5, NULL, 1, folder, filename);

    TEST_ASSERT_EQUAL_STRING("pool_5 - untitled", folder);
}

void test_transliterates_latin_diacritics_in_the_pool_title_to_plain_ascii(void)
{
    char folder[BUNNY_CLI_DESTINATION_MAX];
    char filename[BUNNY_CLI_DESTINATION_MAX];
    bunny_cli_destination_for(NULL, "png", 42, 5,
                              "Caf\xC3\xA9 Com\xC3\xAD"
                              "c",
                              1, folder, filename);

    TEST_ASSERT_EQUAL_STRING("pool_5 - Cafe Comic", folder);
}

void test_falls_back_to_underscore_for_non_latin_text_with_no_ascii_transliteration(void)
{
    char folder[BUNNY_CLI_DESTINATION_MAX];
    char filename[BUNNY_CLI_DESTINATION_MAX];
    /* "ab中cd" -- U+4E2D CJK UNIFIED IDEOGRAPH, UTF-8 E4 B8 AD. */
    bunny_cli_destination_for(NULL, "png", 42, 5,
                              "ab\xE4\xB8\xAD"
                              "cd",
                              1, folder, filename);

    TEST_ASSERT_EQUAL_STRING("pool_5 - ab_cd", folder);
}

void test_truncates_a_very_long_pool_title_so_the_folder_name_stays_within_the_shared_length_budget(void)
{
    char long_title[501];
    memset(long_title, 'A', 500);
    long_title[500] = '\0';

    char folder[BUNNY_CLI_DESTINATION_MAX];
    char filename[BUNNY_CLI_DESTINATION_MAX];
    bunny_cli_destination_for(NULL, "png", 42, 5, long_title, 1, folder, filename);

    TEST_ASSERT_EQUAL(bunny_filename_max_len(), strlen(folder));
    TEST_ASSERT_EQUAL_STRING_LEN("pool_5 - AAA", folder, strlen("pool_5 - AAA"));
}

void test_a_page_number_past_999_still_works_without_truncating(void)
{
    char folder[BUNNY_CLI_DESTINATION_MAX];
    char filename[BUNNY_CLI_DESTINATION_MAX];
    bunny_cli_destination_for(NULL, "png", 42, 5, "Comic", 1000, folder, filename);

    TEST_ASSERT_EQUAL_STRING("5 - p1000 [42].png", filename);
}

void test_falls_back_to_the_plain_artist_scheme_when_pool_id_is_zero(void)
{
    char folder[BUNNY_CLI_DESTINATION_MAX];
    char filename[BUNNY_CLI_DESTINATION_MAX];
    bunny_cli_destination_for("someartist", "png", 42, 0, "Comic", 1, folder, filename);

    TEST_ASSERT_EQUAL_STRING("someartist", folder);
    TEST_ASSERT_EQUAL_STRING("42.png", filename);
}

void test_falls_back_to_the_plain_artist_scheme_when_pool_page_is_zero_even_with_a_pool_id_set(void)
{
    char folder[BUNNY_CLI_DESTINATION_MAX];
    char filename[BUNNY_CLI_DESTINATION_MAX];
    bunny_cli_destination_for("someartist", "png", 42, 5, "Comic", 0, folder, filename);

    TEST_ASSERT_EQUAL_STRING("someartist", folder);
    TEST_ASSERT_EQUAL_STRING("42.png", filename);
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_plain_artist_post_uses_the_artist_as_the_folder);
    RUN_TEST(test_illegal_characters_in_the_artist_name_are_sanitized);
    RUN_TEST(test_a_multi_artist_post_nests_each_artist_as_its_own_subfolder);
    RUN_TEST(test_null_artist_falls_back_to_unknown);
    RUN_TEST(test_pool_download_uses_the_pool_folder_and_page_numbered_filename);
    RUN_TEST(test_illegal_characters_in_the_pool_name_are_sanitized_same_as_the_artist_folder);
    RUN_TEST(test_null_pool_name_falls_back_to_untitled);
    RUN_TEST(test_transliterates_latin_diacritics_in_the_pool_title_to_plain_ascii);
    RUN_TEST(test_falls_back_to_underscore_for_non_latin_text_with_no_ascii_transliteration);
    RUN_TEST(test_truncates_a_very_long_pool_title_so_the_folder_name_stays_within_the_shared_length_budget);
    RUN_TEST(test_a_page_number_past_999_still_works_without_truncating);
    RUN_TEST(test_falls_back_to_the_plain_artist_scheme_when_pool_id_is_zero);
    RUN_TEST(test_falls_back_to_the_plain_artist_scheme_when_pool_page_is_zero_even_with_a_pool_id_set);
    return UNITY_END();
}
