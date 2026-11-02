#include "unity.h"

#include <string.h>

#include "bunny_tag_query/tag_query.h"

void setUp(void) {}
void tearDown(void) {}

static bool matches(const char *query, const char *const *tags, size_t tag_count)
{
    bunny_tag_query_node_t *root = NULL;
    TEST_ASSERT_TRUE(bunny_tag_query_parse(query, &root, NULL));
    bool result = bunny_tag_query_matches(root, tags, tag_count);
    bunny_tag_query_free(root);
    return result;
}

/* --- Parser: accepted syntax ------------------------------------------- */

void test_parse_accepts_a_single_bare_tag(void)
{
    bunny_tag_query_node_t *root = NULL;
    TEST_ASSERT_TRUE(bunny_tag_query_parse("cat", &root, NULL));
    TEST_ASSERT_NOT_NULL(root);
    bunny_tag_query_free(root);
}

void test_parse_accepts_multiple_and_tags(void)
{
    bunny_tag_query_node_t *root = NULL;
    TEST_ASSERT_TRUE(bunny_tag_query_parse("cat dog bird", &root, NULL));
    TEST_ASSERT_NOT_NULL(root);
    bunny_tag_query_free(root);
}

void test_parse_accepts_negation_or_and_wildcard(void)
{
    bunny_tag_query_node_t *root = NULL;
    TEST_ASSERT_TRUE(bunny_tag_query_parse("cat -dog ~bird ~fox tag_*", &root, NULL));
    TEST_ASSERT_NOT_NULL(root);
    bunny_tag_query_free(root);
}

void test_parse_accepts_a_group_with_or_terms(void)
{
    bunny_tag_query_node_t *root = NULL;
    TEST_ASSERT_TRUE(bunny_tag_query_parse("( ~a ~b )", &root, NULL));
    TEST_ASSERT_NOT_NULL(root);
    bunny_tag_query_free(root);
}

void test_parse_accepts_a_negated_group(void)
{
    bunny_tag_query_node_t *root = NULL;
    TEST_ASSERT_TRUE(bunny_tag_query_parse("-( ~a ~b )", &root, NULL));
    TEST_ASSERT_NOT_NULL(root);
    bunny_tag_query_free(root);
}

void test_parse_accepts_an_empty_or_whitespace_only_query_as_vacuously_valid(void)
{
    bunny_tag_query_node_t *root = NULL;
    TEST_ASSERT_TRUE(bunny_tag_query_parse("", &root, NULL));
    TEST_ASSERT_NOT_NULL(root);
    bunny_tag_query_free(root);

    root = NULL;
    TEST_ASSERT_TRUE(bunny_tag_query_parse("   ", &root, NULL));
    TEST_ASSERT_NOT_NULL(root);
    bunny_tag_query_free(root);
}

void test_parse_treats_a_hyphen_mid_tag_as_literal_text_not_an_operator(void)
{
    /* Only a LEADING '-'/'~' is a prefix -- "x-ray" is one ordinary tag. */
    bunny_tag_query_node_t *root = NULL;
    TEST_ASSERT_TRUE(bunny_tag_query_parse("x-ray", &root, NULL));
    TEST_ASSERT_NOT_NULL(root);
    const char *tags[] = {"x-ray"};
    TEST_ASSERT_TRUE(bunny_tag_query_matches(root, tags, 1));
    bunny_tag_query_free(root);
}

static void build_nested_query(char *buf, int depth)
{
    char *p = buf;
    for (int i = 0; i < depth; i++) {
        *p++ = '(';
        *p++ = ' ';
    }
    *p++ = 'a';
    for (int i = 0; i < depth; i++) {
        *p++ = ' ';
        *p++ = ')';
    }
    *p = '\0';
}

void test_parse_accepts_exactly_10_levels_of_nesting(void)
{
    char buf[128];
    build_nested_query(buf, 10);
    bunny_tag_query_node_t *root = NULL;
    TEST_ASSERT_TRUE(bunny_tag_query_parse(buf, &root, NULL));
    TEST_ASSERT_NOT_NULL(root);
    bunny_tag_query_free(root);
}

void test_parse_rejects_11_levels_of_nesting_at_the_11th_open_paren(void)
{
    char buf[128];
    build_nested_query(buf, 11);
    bunny_tag_query_node_t *root = NULL;
    size_t error_pos = 999;
    TEST_ASSERT_FALSE(bunny_tag_query_parse(buf, &root, &error_pos));
    TEST_ASSERT_NULL(root);
    TEST_ASSERT_EQUAL(20, (int)error_pos);
}

/* --- Parser: rejected syntax, with exact error positions --------------- */

void test_parse_rejects_an_empty_group_at_the_open_paren(void)
{
    bunny_tag_query_node_t *root = NULL;
    size_t error_pos = 999;
    TEST_ASSERT_FALSE(bunny_tag_query_parse("(  )", &root, &error_pos));
    TEST_ASSERT_NULL(root);
    TEST_ASSERT_EQUAL(0, (int)error_pos);
}

void test_parse_rejects_a_missing_space_right_after_open_paren(void)
{
    bunny_tag_query_node_t *root = NULL;
    size_t error_pos = 999;
    TEST_ASSERT_FALSE(bunny_tag_query_parse("(~a )", &root, &error_pos));
    TEST_ASSERT_NULL(root);
    TEST_ASSERT_EQUAL(1, (int)error_pos);
}

void test_parse_rejects_a_missing_space_right_before_close_paren(void)
{
    bunny_tag_query_node_t *root = NULL;
    size_t error_pos = 999;
    TEST_ASSERT_FALSE(bunny_tag_query_parse("( ~a)", &root, &error_pos));
    TEST_ASSERT_NULL(root);
    TEST_ASSERT_EQUAL(4, (int)error_pos);
}

void test_parse_rejects_an_unmatched_close_paren(void)
{
    bunny_tag_query_node_t *root = NULL;
    size_t error_pos = 999;
    TEST_ASSERT_FALSE(bunny_tag_query_parse("cat )", &root, &error_pos));
    TEST_ASSERT_NULL(root);
    TEST_ASSERT_EQUAL(4, (int)error_pos);
}

void test_parse_rejects_an_unterminated_group(void)
{
    bunny_tag_query_node_t *root = NULL;
    size_t error_pos = 999;
    TEST_ASSERT_FALSE(bunny_tag_query_parse("( ~a", &root, &error_pos));
    TEST_ASSERT_NULL(root);
    TEST_ASSERT_EQUAL(4, (int)error_pos);
}

void test_parse_rejects_a_bare_operator_with_nothing_after_it(void)
{
    bunny_tag_query_node_t *root = NULL;
    size_t error_pos = 999;
    TEST_ASSERT_FALSE(bunny_tag_query_parse("-", &root, &error_pos));
    TEST_ASSERT_NULL(root);
    TEST_ASSERT_EQUAL(1, (int)error_pos);
}

void test_parse_rejects_a_term_directly_glued_to_a_following_group_with_no_space(void)
{
    bunny_tag_query_node_t *root = NULL;
    size_t error_pos = 999;
    TEST_ASSERT_FALSE(bunny_tag_query_parse("cat( ~a )", &root, &error_pos));
    TEST_ASSERT_NULL(root);
    TEST_ASSERT_EQUAL(3, (int)error_pos);
}

void test_parse_rejects_a_term_directly_glued_after_a_closing_group_with_no_space(void)
{
    bunny_tag_query_node_t *root = NULL;
    size_t error_pos = 999;
    TEST_ASSERT_FALSE(bunny_tag_query_parse("( ~a )cat", &root, &error_pos));
    TEST_ASSERT_NULL(root);
    TEST_ASSERT_EQUAL(6, (int)error_pos);
}

/* --- Validate-only surface ---------------------------------------------- */

void test_validate_matches_parse_success_and_failure(void)
{
    TEST_ASSERT_TRUE(bunny_tag_query_validate("cat ~dog -bird ( ~a ~b )", NULL));
    size_t error_pos = 999;
    TEST_ASSERT_FALSE(bunny_tag_query_validate("(  )", &error_pos));
    TEST_ASSERT_EQUAL(0, (int)error_pos);
}

/* --- Matcher ------------------------------------------------------------- */

void test_matches_and_requires_every_tag(void)
{
    const char *all[] = {"cat", "dog", "bird"};
    TEST_ASSERT_TRUE(matches("cat dog", all, 3));

    const char *partial[] = {"cat"};
    TEST_ASSERT_FALSE(matches("cat dog", partial, 1));
}

void test_matches_or_requires_at_least_one_of_the_set(void)
{
    const char *has_dog[] = {"dog"};
    TEST_ASSERT_TRUE(matches("~cat ~dog", has_dog, 1));

    const char *has_neither[] = {"bird"};
    TEST_ASSERT_FALSE(matches("~cat ~dog", has_neither, 1));

    TEST_ASSERT_FALSE(matches("~cat ~dog", NULL, 0));
}

void test_matches_negation_excludes(void)
{
    const char *cat_only[] = {"cat"};
    TEST_ASSERT_TRUE(matches("cat -dog", cat_only, 1));

    const char *cat_and_dog[] = {"cat", "dog"};
    TEST_ASSERT_FALSE(matches("cat -dog", cat_and_dog, 2));
}

void test_matches_wildcard_as_a_prefix_match(void)
{
    const char *cat_girl[] = {"cat_girl"};
    TEST_ASSERT_TRUE(matches("cat_*", cat_girl, 1));

    const char *dog_girl[] = {"dog_girl"};
    TEST_ASSERT_FALSE(matches("cat_*", dog_girl, 1));
}

void test_matches_empty_query_matches_any_tag_set(void)
{
    const char *some_tags[] = {"anything"};
    TEST_ASSERT_TRUE(matches("", some_tags, 1));
    TEST_ASSERT_TRUE(matches("", NULL, 0));
}

void test_matches_nested_group_combined_with_an_outer_negation(void)
{
    /* "cat -( ~a ~b )" -- requires cat, and requires that the group
     * (which itself requires at least one of a/b) does NOT hold. */
    const char *cat_only[] = {"cat"};
    TEST_ASSERT_TRUE(matches("cat -( ~a ~b )", cat_only, 1));

    const char *cat_and_a[] = {"cat", "a"};
    TEST_ASSERT_FALSE(matches("cat -( ~a ~b )", cat_and_a, 2));
}

void test_matches_group_as_the_sole_member_of_an_outer_or_set(void)
{
    /* "~( cat dog )" -- the group requires BOTH cat and dog internally;
     * as the only member of the outer or-set, the whole query's result
     * is exactly the group's own result. */
    const char *both[] = {"cat", "dog"};
    TEST_ASSERT_TRUE(matches("~( cat dog )", both, 2));

    const char *only_cat[] = {"cat"};
    TEST_ASSERT_FALSE(matches("~( cat dog )", only_cat, 1));
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_parse_accepts_a_single_bare_tag);
    RUN_TEST(test_parse_accepts_multiple_and_tags);
    RUN_TEST(test_parse_accepts_negation_or_and_wildcard);
    RUN_TEST(test_parse_accepts_a_group_with_or_terms);
    RUN_TEST(test_parse_accepts_a_negated_group);
    RUN_TEST(test_parse_accepts_an_empty_or_whitespace_only_query_as_vacuously_valid);
    RUN_TEST(test_parse_treats_a_hyphen_mid_tag_as_literal_text_not_an_operator);
    RUN_TEST(test_parse_accepts_exactly_10_levels_of_nesting);
    RUN_TEST(test_parse_rejects_11_levels_of_nesting_at_the_11th_open_paren);
    RUN_TEST(test_parse_rejects_an_empty_group_at_the_open_paren);
    RUN_TEST(test_parse_rejects_a_missing_space_right_after_open_paren);
    RUN_TEST(test_parse_rejects_a_missing_space_right_before_close_paren);
    RUN_TEST(test_parse_rejects_an_unmatched_close_paren);
    RUN_TEST(test_parse_rejects_an_unterminated_group);
    RUN_TEST(test_parse_rejects_a_bare_operator_with_nothing_after_it);
    RUN_TEST(test_parse_rejects_a_term_directly_glued_to_a_following_group_with_no_space);
    RUN_TEST(test_parse_rejects_a_term_directly_glued_after_a_closing_group_with_no_space);
    RUN_TEST(test_validate_matches_parse_success_and_failure);
    RUN_TEST(test_matches_and_requires_every_tag);
    RUN_TEST(test_matches_or_requires_at_least_one_of_the_set);
    RUN_TEST(test_matches_negation_excludes);
    RUN_TEST(test_matches_wildcard_as_a_prefix_match);
    RUN_TEST(test_matches_empty_query_matches_any_tag_set);
    RUN_TEST(test_matches_nested_group_combined_with_an_outer_negation);
    RUN_TEST(test_matches_group_as_the_sole_member_of_an_outer_or_set);
    return UNITY_END();
}
