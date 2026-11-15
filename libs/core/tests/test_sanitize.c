#include "unity.h"

#include <string.h>

#include "bunny_core/core.h"

/* bunny_sanitize_filename_segment is now a thin wrapper over GOBLIN's own
 * goblin_sanitize_filename_segment (see libs/core/src/sanitize.c) -- its
 * own test suite (GOBLIN's tests/sanitize_filename_test.c) already covers
 * reserved-character replacement, control bytes, trailing dot/space
 * trimming, reserved device names, and truncation-without-splitting-UTF-8,
 * so this file only covers what bunny_core's wrapper adds on top: smoke
 * tests that delegation actually happens, and the transliterate-then-
 * sanitize composition for ascii_only (GOBLIN's own sanitize_filename_test
 * has no notion of this -- it's bunny_core's own choice to compose the two
 * headers, per their doc comments' recommendation). */

void setUp(void)
{}
void tearDown(void)
{}

static char g_buf[256];

void test_delegates_reserved_character_replacement_to_goblin(void)
{
    bunny_sanitize_filename_segment("Some/Bad:Comic", false, g_buf, sizeof(g_buf));
    TEST_ASSERT_EQUAL_STRING("Some_Bad_Comic", g_buf);
}

void test_ascii_only_folds_known_latin_diacritics_instead_of_collapsing_to_underscore(void)
{
    /* "Café Comíc" -- goblin_sanitize_filename_segment alone
     * would turn each diacritic into '_'; composed with
     * goblin_transliterate_to_ascii first (what this wrapper now does),
     * they fold to their plain-ASCII base letter instead. */
    bunny_sanitize_filename_segment("Caf\xC3\xA9 Com\xC3\xAD"
                                    "c",
                                    true, g_buf, sizeof(g_buf));
    TEST_ASSERT_EQUAL_STRING("Cafe Comic", g_buf);
}

void test_ascii_only_still_falls_back_to_underscore_for_non_latin_text(void)
{
    /* U+4E2D ("CJK middle"), 3 bytes -- no Latin transliteration, so
     * goblin_transliterate_to_ascii's own fallback_byte ('_') applies,
     * same end result as the old hand-rolled behavior for anything outside
     * the Latin-1/Latin Extended-A table. */
    bunny_sanitize_filename_segment("ab\xE4\xB8\xAD"
                                    "cd",
                                    true, g_buf, sizeof(g_buf));
    TEST_ASSERT_EQUAL_STRING("ab_cd", g_buf);
}

void test_ascii_only_false_leaves_non_ascii_bytes_untouched_not_transliterated(void)
{
    /* Transliteration is deliberately NOT applied when ascii_only is
     * false -- the caller asked to keep non-ASCII text verbatim. */
    bunny_sanitize_filename_segment("Caf\xC3\xA9", false, g_buf, sizeof(g_buf));
    TEST_ASSERT_EQUAL_STRING("Caf\xC3\xA9", g_buf);
}

void test_null_input_with_ascii_only_true_falls_back_to_underscore(void)
{
    bunny_sanitize_filename_segment(NULL, true, g_buf, sizeof(g_buf));
    TEST_ASSERT_EQUAL_STRING("_", g_buf);
}

void test_max_len_matches_the_documented_constant(void)
{
    TEST_ASSERT_EQUAL(BUNNY_FILENAME_MAX_LEN, bunny_filename_max_len());
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_delegates_reserved_character_replacement_to_goblin);
    RUN_TEST(test_ascii_only_folds_known_latin_diacritics_instead_of_collapsing_to_underscore);
    RUN_TEST(test_ascii_only_still_falls_back_to_underscore_for_non_latin_text);
    RUN_TEST(test_ascii_only_false_leaves_non_ascii_bytes_untouched_not_transliterated);
    RUN_TEST(test_null_input_with_ascii_only_true_falls_back_to_underscore);
    RUN_TEST(test_max_len_matches_the_documented_constant);
    return UNITY_END();
}
