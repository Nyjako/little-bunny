#include "unity.h"

#include <string.h>

#include "bunny_core/core.h"

void setUp(void)
{}
void tearDown(void)
{}

static char g_buf[256];

void test_leaves_already_safe_ascii_untouched(void)
{
    size_t len = bunny_sanitize_filename_segment("My Comic (Part 2)", false, g_buf, sizeof(g_buf));
    TEST_ASSERT_EQUAL_STRING("My Comic (Part 2)", g_buf);
    TEST_ASSERT_EQUAL(strlen("My Comic (Part 2)"), len);
}

void test_replaces_windows_reserved_characters_with_underscore(void)
{
    const char *input = "Some/Bad:Comic*Name?\"<>|\\";
    size_t len = bunny_sanitize_filename_segment(input, false, g_buf, sizeof(g_buf));
    /* One '_' per disallowed byte -- same length as the input, every
     * reserved character (9 of them here: / : * ? " < > | \) swapped
     * 1:1 for '_', every other byte untouched. */
    TEST_ASSERT_EQUAL(strlen(input), len);
    for (size_t i = 0; i < len; i++) {
        bool is_reserved = strchr("/:*?\"<>|\\", input[i]) != NULL;
        TEST_ASSERT_EQUAL(is_reserved ? '_' : input[i], g_buf[i]);
    }
}

void test_replaces_control_bytes(void)
{
    char input[] = {'a', '\t', '\n', 'b', '\0'};
    bunny_sanitize_filename_segment(input, false, g_buf, sizeof(g_buf));
    TEST_ASSERT_EQUAL_STRING("a__b", g_buf);
}

void test_null_input_falls_back_to_underscore(void)
{
    bunny_sanitize_filename_segment(NULL, false, g_buf, sizeof(g_buf));
    TEST_ASSERT_EQUAL_STRING("_", g_buf);
}

void test_empty_input_falls_back_to_underscore(void)
{
    bunny_sanitize_filename_segment("", false, g_buf, sizeof(g_buf));
    TEST_ASSERT_EQUAL_STRING("_", g_buf);
}

/* Reserved characters are each replaced 1:1 with '_' (see the dedicated
 * test above), never stripped outright -- the only way to actually end up
 * with nothing is a trailing run of '.'/' ' trimming away the whole
 * (already entirely trailing) result. */
void test_input_that_trims_to_nothing_falls_back_to_underscore(void)
{
    bunny_sanitize_filename_segment(" . . ", false, g_buf, sizeof(g_buf));
    TEST_ASSERT_EQUAL_STRING("_", g_buf);
}

void test_trims_trailing_dots_and_spaces(void)
{
    bunny_sanitize_filename_segment("My Title. ", false, g_buf, sizeof(g_buf));
    TEST_ASSERT_EQUAL_STRING("My Title", g_buf);
}

void test_ascii_only_true_collapses_a_non_ascii_codepoint_to_one_underscore(void)
{
    /* U+00E9 ("e"), 2 bytes in UTF-8 (0xC3 0xA9) -- must become exactly one
     * '_', not two. */
    bunny_sanitize_filename_segment("caf\xC3\xA9 au lait", true, g_buf, sizeof(g_buf));
    TEST_ASSERT_EQUAL_STRING("caf_ au lait", g_buf);
}

void test_ascii_only_false_preserves_non_ascii_bytes_verbatim(void)
{
    bunny_sanitize_filename_segment("caf\xC3\xA9", false, g_buf, sizeof(g_buf));
    TEST_ASSERT_EQUAL_STRING("caf\xC3\xA9", g_buf);
}

void test_truncates_to_fit_out_buf_size(void)
{
    char small_buf[6];
    size_t len = bunny_sanitize_filename_segment("abcdefghij", false, small_buf, sizeof(small_buf));
    TEST_ASSERT_EQUAL_STRING("abcde", small_buf);
    TEST_ASSERT_EQUAL(5, len);
}

void test_truncation_never_splits_a_multibyte_sequence_when_not_ascii_only(void)
{
    /* "ab" + U+00E9 (2 bytes) -- a 4-byte buffer only has room for "ab" plus
     * the NUL, so the 2-byte sequence must be dropped whole, not split. */
    char small_buf[4];
    bunny_sanitize_filename_segment("ab\xC3\xA9", false, small_buf, sizeof(small_buf));
    TEST_ASSERT_EQUAL_STRING("ab", small_buf);
}

void test_out_buf_size_one_writes_only_the_nul_terminator(void)
{
    char tiny_buf[1];
    size_t len = bunny_sanitize_filename_segment("anything", false, tiny_buf, sizeof(tiny_buf));
    TEST_ASSERT_EQUAL(0, len);
    TEST_ASSERT_EQUAL_STRING("", tiny_buf);
}

void test_max_len_matches_the_documented_constant(void)
{
    TEST_ASSERT_EQUAL(BUNNY_FILENAME_MAX_LEN, bunny_filename_max_len());
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_leaves_already_safe_ascii_untouched);
    RUN_TEST(test_replaces_windows_reserved_characters_with_underscore);
    RUN_TEST(test_replaces_control_bytes);
    RUN_TEST(test_null_input_falls_back_to_underscore);
    RUN_TEST(test_empty_input_falls_back_to_underscore);
    RUN_TEST(test_input_that_trims_to_nothing_falls_back_to_underscore);
    RUN_TEST(test_trims_trailing_dots_and_spaces);
    RUN_TEST(test_ascii_only_true_collapses_a_non_ascii_codepoint_to_one_underscore);
    RUN_TEST(test_ascii_only_false_preserves_non_ascii_bytes_verbatim);
    RUN_TEST(test_truncates_to_fit_out_buf_size);
    RUN_TEST(test_truncation_never_splits_a_multibyte_sequence_when_not_ascii_only);
    RUN_TEST(test_out_buf_size_one_writes_only_the_nul_terminator);
    RUN_TEST(test_max_len_matches_the_documented_constant);
    return UNITY_END();
}
