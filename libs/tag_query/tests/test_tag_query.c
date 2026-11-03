#include "unity.h"

#include <stdio.h>
#include <string.h>

#include "bunny_tag_query/tag_query.h"

void setUp(void)
{}
void tearDown(void)
{}

static bool matches(const char *query, const char *const *tags, size_t tag_count)
{
    bunny_tag_query_node_t *root = NULL;
    TEST_ASSERT_TRUE(bunny_tag_query_parse(query, BUNNY_TAG_QUERY_DIALECT_E621, &root, NULL));
    bool result = bunny_tag_query_matches(root, tags, tag_count);
    bunny_tag_query_free(root);
    return result;
}

/* --- Parser: accepted syntax ------------------------------------------- */

void test_parse_accepts_a_single_bare_tag(void)
{
    bunny_tag_query_node_t *root = NULL;
    TEST_ASSERT_TRUE(bunny_tag_query_parse("cat", BUNNY_TAG_QUERY_DIALECT_E621, &root, NULL));
    TEST_ASSERT_NOT_NULL(root);
    bunny_tag_query_free(root);
}

void test_parse_accepts_multiple_and_tags(void)
{
    bunny_tag_query_node_t *root = NULL;
    TEST_ASSERT_TRUE(bunny_tag_query_parse("cat dog bird", BUNNY_TAG_QUERY_DIALECT_E621, &root, NULL));
    TEST_ASSERT_NOT_NULL(root);
    bunny_tag_query_free(root);
}

void test_parse_accepts_negation_or_and_wildcard(void)
{
    bunny_tag_query_node_t *root = NULL;
    TEST_ASSERT_TRUE(bunny_tag_query_parse("cat -dog ~bird ~fox tag_*", BUNNY_TAG_QUERY_DIALECT_E621, &root, NULL));
    TEST_ASSERT_NOT_NULL(root);
    bunny_tag_query_free(root);
}

void test_parse_accepts_a_group_with_or_terms(void)
{
    bunny_tag_query_node_t *root = NULL;
    TEST_ASSERT_TRUE(bunny_tag_query_parse("( ~a ~b )", BUNNY_TAG_QUERY_DIALECT_E621, &root, NULL));
    TEST_ASSERT_NOT_NULL(root);
    bunny_tag_query_free(root);
}

void test_parse_accepts_a_negated_group(void)
{
    bunny_tag_query_node_t *root = NULL;
    TEST_ASSERT_TRUE(bunny_tag_query_parse("-( ~a ~b )", BUNNY_TAG_QUERY_DIALECT_E621, &root, NULL));
    TEST_ASSERT_NOT_NULL(root);
    bunny_tag_query_free(root);
}

void test_parse_accepts_an_empty_or_whitespace_only_query_as_vacuously_valid(void)
{
    bunny_tag_query_node_t *root = NULL;
    TEST_ASSERT_TRUE(bunny_tag_query_parse("", BUNNY_TAG_QUERY_DIALECT_E621, &root, NULL));
    TEST_ASSERT_NOT_NULL(root);
    bunny_tag_query_free(root);

    root = NULL;
    TEST_ASSERT_TRUE(bunny_tag_query_parse("   ", BUNNY_TAG_QUERY_DIALECT_E621, &root, NULL));
    TEST_ASSERT_NOT_NULL(root);
    bunny_tag_query_free(root);
}

void test_parse_treats_a_hyphen_mid_tag_as_literal_text_not_an_operator(void)
{
    /* Only a LEADING '-'/'~' is a prefix -- "x-ray" is one ordinary tag. */
    bunny_tag_query_node_t *root = NULL;
    TEST_ASSERT_TRUE(bunny_tag_query_parse("x-ray", BUNNY_TAG_QUERY_DIALECT_E621, &root, NULL));
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
    TEST_ASSERT_TRUE(bunny_tag_query_parse(buf, BUNNY_TAG_QUERY_DIALECT_E621, &root, NULL));
    TEST_ASSERT_NOT_NULL(root);
    bunny_tag_query_free(root);
}

void test_parse_rejects_11_levels_of_nesting_at_the_11th_open_paren(void)
{
    char buf[128];
    build_nested_query(buf, 11);
    bunny_tag_query_node_t *root = NULL;
    size_t error_pos = 999;
    TEST_ASSERT_FALSE(bunny_tag_query_parse(buf, BUNNY_TAG_QUERY_DIALECT_E621, &root, &error_pos));
    TEST_ASSERT_NULL(root);
    TEST_ASSERT_EQUAL(20, (int)error_pos);
}

void test_parse_rejects_50_levels_of_nesting_at_the_same_11th_position(void)
{
    /* Confirms the depth check short-circuits the moment the 11th '(' is
     * attempted, rather than recursing all the way through a much deeper
     * malicious input first -- the error lands at the exact same position
     * as the 11-level case above, not somewhere deeper in the string. */
    char buf[512];
    build_nested_query(buf, 50);
    bunny_tag_query_node_t *root = NULL;
    size_t error_pos = 999;
    TEST_ASSERT_FALSE(bunny_tag_query_parse(buf, BUNNY_TAG_QUERY_DIALECT_E621, &root, &error_pos));
    TEST_ASSERT_NULL(root);
    TEST_ASSERT_EQUAL(20, (int)error_pos);
}

void test_parse_depth_is_scoped_per_branch_not_cumulative_across_siblings(void)
{
    /* Two SEPARATE depth-10 groups, side by side (not nested in each
     * other) -- the second sibling's depth must be judged independently,
     * not as if it continued accumulating from the first. */
    char first[128];
    char second[128];
    build_nested_query(first, 10);
    build_nested_query(second, 10);
    char buf[300];
    snprintf(buf, sizeof(buf), "%s %s", first, second);

    bunny_tag_query_node_t *root = NULL;
    TEST_ASSERT_TRUE(bunny_tag_query_parse(buf, BUNNY_TAG_QUERY_DIALECT_E621, &root, NULL));
    TEST_ASSERT_NOT_NULL(root);
    bunny_tag_query_free(root);
}

/* Builds "t0 t1 t2 ... t(n-1)" into buf, returning the byte offset where
 * the LAST tag (index n-1) starts -- used to assert the exact error
 * position when a tag pushes the running total over the limit, without
 * having to hand-count variable-width tag names ("t9" vs "t10"). */
static size_t build_n_tags_query(char *buf, int n)
{
    char *p = buf;
    size_t last_start = 0;
    for (int i = 0; i < n; i++) {
        if (i > 0) {
            *p++ = ' ';
        }
        last_start = (size_t)(p - buf);
        p += sprintf(p, "t%d", i);
    }
    *p = '\0';
    return last_start;
}

void test_parse_accepts_exactly_40_tags_on_e621(void)
{
    char buf[256];
    build_n_tags_query(buf, 40);
    bunny_tag_query_node_t *root = NULL;
    TEST_ASSERT_TRUE(bunny_tag_query_parse(buf, BUNNY_TAG_QUERY_DIALECT_E621, &root, NULL));
    TEST_ASSERT_NOT_NULL(root);
    bunny_tag_query_free(root);
}

void test_parse_rejects_41_tags_on_e621_at_the_41st_tag(void)
{
    char buf[256];
    size_t last_tag_start = build_n_tags_query(buf, 41);
    bunny_tag_query_node_t *root = NULL;
    size_t error_pos = 999;
    TEST_ASSERT_FALSE(bunny_tag_query_parse(buf, BUNNY_TAG_QUERY_DIALECT_E621, &root, &error_pos));
    TEST_ASSERT_NULL(root);
    TEST_ASSERT_EQUAL((int)last_tag_start, (int)error_pos);
}

void test_parse_40_tag_limit_counts_tags_nested_inside_groups_too(void)
{
    /* 30 top-level tags + a group of 10 more = 40 total -- valid. */
    char buf[512];
    char *p = buf;
    for (int i = 0; i < 30; i++) {
        if (i > 0) {
            *p++ = ' ';
        }
        p += sprintf(p, "t%d", i);
    }
    p += sprintf(p, " ( ");
    for (int i = 0; i < 10; i++) {
        if (i > 0) {
            *p++ = ' ';
        }
        p += sprintf(p, "g%d", i);
    }
    p += sprintf(p, " )");
    *p = '\0';

    bunny_tag_query_node_t *root = NULL;
    TEST_ASSERT_TRUE(bunny_tag_query_parse(buf, BUNNY_TAG_QUERY_DIALECT_E621, &root, NULL));
    TEST_ASSERT_NOT_NULL(root);
    bunny_tag_query_free(root);

    /* Same shape, but the group has 11 tags instead of 10 -- 41 total,
     * across the group boundary -- must still be rejected. */
    char buf2[512];
    p = buf2;
    for (int i = 0; i < 30; i++) {
        if (i > 0) {
            *p++ = ' ';
        }
        p += sprintf(p, "t%d", i);
    }
    p += sprintf(p, " ( ");
    for (int i = 0; i < 11; i++) {
        if (i > 0) {
            *p++ = ' ';
        }
        p += sprintf(p, "g%d", i);
    }
    p += sprintf(p, " )");
    *p = '\0';

    bunny_tag_query_node_t *root2 = NULL;
    TEST_ASSERT_FALSE(bunny_tag_query_parse(buf2, BUNNY_TAG_QUERY_DIALECT_E621, &root2, NULL));
    TEST_ASSERT_NULL(root2);
}

/* --- Parser: rejected syntax, with exact error positions --------------- */

void test_parse_rejects_an_empty_group_at_the_open_paren(void)
{
    bunny_tag_query_node_t *root = NULL;
    size_t error_pos = 999;
    TEST_ASSERT_FALSE(bunny_tag_query_parse("(  )", BUNNY_TAG_QUERY_DIALECT_E621, &root, &error_pos));
    TEST_ASSERT_NULL(root);
    TEST_ASSERT_EQUAL(0, (int)error_pos);
}

void test_parse_rejects_a_missing_space_right_after_open_paren(void)
{
    bunny_tag_query_node_t *root = NULL;
    size_t error_pos = 999;
    TEST_ASSERT_FALSE(bunny_tag_query_parse("(~a )", BUNNY_TAG_QUERY_DIALECT_E621, &root, &error_pos));
    TEST_ASSERT_NULL(root);
    TEST_ASSERT_EQUAL(1, (int)error_pos);
}

void test_parse_rejects_a_missing_space_right_before_close_paren(void)
{
    bunny_tag_query_node_t *root = NULL;
    size_t error_pos = 999;
    TEST_ASSERT_FALSE(bunny_tag_query_parse("( ~a)", BUNNY_TAG_QUERY_DIALECT_E621, &root, &error_pos));
    TEST_ASSERT_NULL(root);
    TEST_ASSERT_EQUAL(4, (int)error_pos);
}

void test_parse_rejects_an_unmatched_close_paren(void)
{
    bunny_tag_query_node_t *root = NULL;
    size_t error_pos = 999;
    TEST_ASSERT_FALSE(bunny_tag_query_parse("cat )", BUNNY_TAG_QUERY_DIALECT_E621, &root, &error_pos));
    TEST_ASSERT_NULL(root);
    TEST_ASSERT_EQUAL(4, (int)error_pos);
}

void test_parse_rejects_an_unterminated_group(void)
{
    bunny_tag_query_node_t *root = NULL;
    size_t error_pos = 999;
    TEST_ASSERT_FALSE(bunny_tag_query_parse("( ~a", BUNNY_TAG_QUERY_DIALECT_E621, &root, &error_pos));
    TEST_ASSERT_NULL(root);
    TEST_ASSERT_EQUAL(4, (int)error_pos);
}

void test_parse_rejects_a_bare_operator_with_nothing_after_it(void)
{
    bunny_tag_query_node_t *root = NULL;
    size_t error_pos = 999;
    TEST_ASSERT_FALSE(bunny_tag_query_parse("-", BUNNY_TAG_QUERY_DIALECT_E621, &root, &error_pos));
    TEST_ASSERT_NULL(root);
    TEST_ASSERT_EQUAL(1, (int)error_pos);
}

void test_parse_rejects_a_term_directly_glued_to_a_following_group_with_no_space(void)
{
    bunny_tag_query_node_t *root = NULL;
    size_t error_pos = 999;
    TEST_ASSERT_FALSE(bunny_tag_query_parse("cat( ~a )", BUNNY_TAG_QUERY_DIALECT_E621, &root, &error_pos));
    TEST_ASSERT_NULL(root);
    TEST_ASSERT_EQUAL(3, (int)error_pos);
}

void test_parse_rejects_a_term_directly_glued_after_a_closing_group_with_no_space(void)
{
    bunny_tag_query_node_t *root = NULL;
    size_t error_pos = 999;
    TEST_ASSERT_FALSE(bunny_tag_query_parse("( ~a )cat", BUNNY_TAG_QUERY_DIALECT_E621, &root, &error_pos));
    TEST_ASSERT_NULL(root);
    TEST_ASSERT_EQUAL(6, (int)error_pos);
}

void test_parse_rejects_a_stray_close_paren_after_a_properly_closed_group(void)
{
    bunny_tag_query_node_t *root = NULL;
    size_t error_pos = 999;
    TEST_ASSERT_FALSE(bunny_tag_query_parse("( a ) )", BUNNY_TAG_QUERY_DIALECT_E621, &root, &error_pos));
    TEST_ASSERT_NULL(root);
    TEST_ASSERT_EQUAL(6, (int)error_pos);
}

void test_parse_rejects_an_empty_group_nested_two_levels_deep(void)
{
    /* The error must point at the INNER (empty) group's own '(', not the
     * outer one, even though the outer is also -- transitively -- empty
     * as a result. */
    bunny_tag_query_node_t *root = NULL;
    size_t error_pos = 999;
    TEST_ASSERT_FALSE(bunny_tag_query_parse("( ( ) )", BUNNY_TAG_QUERY_DIALECT_E621, &root, &error_pos));
    TEST_ASSERT_NULL(root);
    TEST_ASSERT_EQUAL(2, (int)error_pos);
}

void test_parse_rejects_a_bare_dash_surrounded_by_whitespace(void)
{
    bunny_tag_query_node_t *root = NULL;
    size_t error_pos = 999;
    TEST_ASSERT_FALSE(bunny_tag_query_parse("   -   ", BUNNY_TAG_QUERY_DIALECT_E621, &root, &error_pos));
    TEST_ASSERT_NULL(root);
    TEST_ASSERT_EQUAL(4, (int)error_pos);
}

void test_parse_treats_stacked_leading_operators_as_literal_tag_text(void)
{
    /* Only the term's FIRST character is ever consumed as a prefix --
     * "--cat" is '-' (forbidden) + the bare tag "-cat" (literal, since a
     * mid-scan '-' is never special). Matching against the literal "-cat"
     * text (not "cat") proves this isn't accidentally double-stripping. */
    const char *has_dash_cat[] = {"-cat"};
    TEST_ASSERT_FALSE(matches("--cat", has_dash_cat, 1)); /* forbidden "-cat" IS present */
    const char *has_plain_cat[] = {"cat"};
    TEST_ASSERT_TRUE(matches("--cat", has_plain_cat, 1)); /* forbidden "-cat" is NOT present */

    const char *has_tilde_cat[] = {"~cat"};
    TEST_ASSERT_TRUE(matches("~~cat", has_tilde_cat, 1)); /* or-set's sole member "~cat" present */
    const char *has_plain_cat2[] = {"cat"};
    TEST_ASSERT_FALSE(matches("~~cat", has_plain_cat2, 1)); /* literal "~cat" is NOT present */
}

void test_parse_wildcard_matches_up_to_the_first_asterisk_even_with_several(void)
{
    const char *matching[] = {"ca"};
    TEST_ASSERT_TRUE(matches("ca*t*", matching, 1));
    const char *non_matching[] = {"xx"};
    TEST_ASSERT_FALSE(matches("ca*t*", non_matching, 1));
}

void test_parse_accepts_a_very_long_tag_name(void)
{
    char buf[600];
    memset(buf, 'a', 500);
    buf[500] = '\0';
    bunny_tag_query_node_t *root = NULL;
    TEST_ASSERT_TRUE(bunny_tag_query_parse(buf, BUNNY_TAG_QUERY_DIALECT_E621, &root, NULL));
    TEST_ASSERT_NOT_NULL(root);
    const char *tags[] = {buf};
    TEST_ASSERT_TRUE(bunny_tag_query_matches(root, tags, 1));
    bunny_tag_query_free(root);
}

void test_parse_accepts_a_tag_containing_multibyte_utf8_bytes(void)
{
    /* "café" (UTF-8: 'c','a','f', 0xC3, 0xA9) -- every continuation byte
     * is >= 0x80, never equal to the ASCII delimiter set, so the whole
     * sequence is swept into one tag's literal bytes with no special
     * handling needed. */
    const char tag[] = "caf\xc3\xa9";
    bunny_tag_query_node_t *root = NULL;
    TEST_ASSERT_TRUE(bunny_tag_query_parse(tag, BUNNY_TAG_QUERY_DIALECT_E621, &root, NULL));
    TEST_ASSERT_NOT_NULL(root);
    const char *tags[] = {tag};
    TEST_ASSERT_TRUE(bunny_tag_query_matches(root, tags, 1));
    bunny_tag_query_free(root);
}

void test_parse_accepts_tabs_and_multiple_spaces_as_separators(void)
{
    const char *tags[] = {"cat", "bird"};
    TEST_ASSERT_TRUE(matches("cat\t\t-dog   bird", tags, 2));
}

void test_parse_accepts_consecutive_sibling_groups(void)
{
    const char *both[] = {"a", "b"};
    TEST_ASSERT_TRUE(matches("( a ) ( b )", both, 2));
    const char *only_a[] = {"a"};
    TEST_ASSERT_FALSE(matches("( a ) ( b )", only_a, 1));
}

void test_parse_double_negation_of_nested_groups_cancels_out(void)
{
    /* "-( -( cat ) )" -- forbidding a group whose own content forbids a
     * group requiring "cat" -- double-negates back to "requires cat". */
    const char *has_cat[] = {"cat"};
    TEST_ASSERT_TRUE(matches("-( -( cat ) )", has_cat, 1));
    TEST_ASSERT_FALSE(matches("-( -( cat ) )", NULL, 0));
}

/* --- Inkbunny dialect: a strict subset (AND + '-' exclude only) -------- */

void test_inkbunny_accepts_bare_words_and_negation(void)
{
    bunny_tag_query_node_t *root = NULL;
    TEST_ASSERT_TRUE(bunny_tag_query_parse("leopard -snow", BUNNY_TAG_QUERY_DIALECT_INKBUNNY, &root, NULL));
    TEST_ASSERT_NOT_NULL(root);
    const char *leopard_only[] = {"leopard"};
    TEST_ASSERT_TRUE(bunny_tag_query_matches(root, leopard_only, 1));
    const char *snow_leopard[] = {"leopard", "snow"};
    TEST_ASSERT_FALSE(bunny_tag_query_matches(root, snow_leopard, 2));
    bunny_tag_query_free(root);
}

void test_inkbunny_rejects_or_syntax(void)
{
    bunny_tag_query_node_t *root = NULL;
    size_t error_pos = 999;
    TEST_ASSERT_FALSE(bunny_tag_query_parse("~cat", BUNNY_TAG_QUERY_DIALECT_INKBUNNY, &root, &error_pos));
    TEST_ASSERT_NULL(root);
    TEST_ASSERT_EQUAL(0, (int)error_pos);
}

void test_inkbunny_rejects_wildcard_syntax(void)
{
    bunny_tag_query_node_t *root = NULL;
    size_t error_pos = 999;
    TEST_ASSERT_FALSE(bunny_tag_query_parse("cat_*", BUNNY_TAG_QUERY_DIALECT_INKBUNNY, &root, &error_pos));
    TEST_ASSERT_NULL(root);
    TEST_ASSERT_EQUAL(4, (int)error_pos);
}

void test_inkbunny_rejects_group_syntax(void)
{
    bunny_tag_query_node_t *root = NULL;
    size_t error_pos = 999;
    TEST_ASSERT_FALSE(bunny_tag_query_parse("( cat dog )", BUNNY_TAG_QUERY_DIALECT_INKBUNNY, &root, &error_pos));
    TEST_ASSERT_NULL(root);
    TEST_ASSERT_EQUAL(0, (int)error_pos);
}

void test_inkbunny_accepts_the_same_valid_syntax_e621_would_parse_identically(void)
{
    /* Confirms both dialects produce the exact same AST shape for syntax
     * they both support -- the matcher never needs dialect-awareness. */
    const char *tags[] = {"cat", "dog"};
    bunny_tag_query_node_t *root = NULL;
    TEST_ASSERT_TRUE(bunny_tag_query_parse("cat dog", BUNNY_TAG_QUERY_DIALECT_INKBUNNY, &root, NULL));
    TEST_ASSERT_TRUE(bunny_tag_query_matches(root, tags, 2));
    bunny_tag_query_free(root);
}

void test_inkbunny_has_no_40_tag_limit(void)
{
    /* e621's "max 40 tags" is specific to e621 -- Inkbunny has no such
     * documented cap, so 50 keywords must still parse fine. */
    char buf[256];
    build_n_tags_query(buf, 50);
    bunny_tag_query_node_t *root = NULL;
    TEST_ASSERT_TRUE(bunny_tag_query_parse(buf, BUNNY_TAG_QUERY_DIALECT_INKBUNNY, &root, NULL));
    TEST_ASSERT_NOT_NULL(root);
    bunny_tag_query_free(root);
}

void test_inkbunny_rejects_a_group_wherever_the_open_paren_appears(void)
{
    bunny_tag_query_node_t *root = NULL;
    size_t error_pos = 999;

    TEST_ASSERT_FALSE(bunny_tag_query_parse("( cat )", BUNNY_TAG_QUERY_DIALECT_INKBUNNY, &root, &error_pos));
    TEST_ASSERT_NULL(root);
    TEST_ASSERT_EQUAL(0, (int)error_pos);

    error_pos = 999;
    TEST_ASSERT_FALSE(bunny_tag_query_parse("cat ( dog )", BUNNY_TAG_QUERY_DIALECT_INKBUNNY, &root, &error_pos));
    TEST_ASSERT_NULL(root);
    TEST_ASSERT_EQUAL(4, (int)error_pos);

    /* Even deeply "nested" -- Inkbunny rejects at the FIRST '(' it sees,
     * never getting far enough to evaluate nesting depth at all. */
    char buf[128];
    build_nested_query(buf, 10);
    error_pos = 999;
    TEST_ASSERT_FALSE(bunny_tag_query_parse(buf, BUNNY_TAG_QUERY_DIALECT_INKBUNNY, &root, &error_pos));
    TEST_ASSERT_NULL(root);
    TEST_ASSERT_EQUAL(0, (int)error_pos);
}

void test_inkbunny_rejects_a_leading_tilde_even_when_followed_by_more_tildes(void)
{
    /* Unlike '-', a leading '~' is checked and rejected immediately for
     * Inkbunny -- it never falls through to being swept up as literal tag
     * text the way a second stacked '-' does. */
    bunny_tag_query_node_t *root = NULL;
    size_t error_pos = 999;
    TEST_ASSERT_FALSE(bunny_tag_query_parse("~~cat", BUNNY_TAG_QUERY_DIALECT_INKBUNNY, &root, &error_pos));
    TEST_ASSERT_NULL(root);
    TEST_ASSERT_EQUAL(0, (int)error_pos);
}

void test_inkbunny_treats_a_stacked_leading_dash_as_literal_tag_text(void)
{
    /* Same dialect-independent behavior as e621's own version of this
     * test -- only the first character is ever consumed as a prefix. */
    const char *has_dash_cat[] = {"-cat"};
    bunny_tag_query_node_t *root = NULL;
    TEST_ASSERT_TRUE(bunny_tag_query_parse("--cat", BUNNY_TAG_QUERY_DIALECT_INKBUNNY, &root, NULL));
    TEST_ASSERT_NOT_NULL(root);
    TEST_ASSERT_FALSE(bunny_tag_query_matches(root, has_dash_cat, 1)); /* forbidden "-cat" IS present */
    bunny_tag_query_free(root);
}

void test_inkbunny_rejects_a_wildcard_asterisk_anywhere_in_a_tag(void)
{
    bunny_tag_query_node_t *root = NULL;
    size_t error_pos = 999;
    TEST_ASSERT_FALSE(bunny_tag_query_parse("ca*t", BUNNY_TAG_QUERY_DIALECT_INKBUNNY, &root, &error_pos));
    TEST_ASSERT_NULL(root);
    TEST_ASSERT_EQUAL(2, (int)error_pos);
}

void test_inkbunny_accepts_a_long_tag_and_multibyte_utf8_text(void)
{
    char buf[600];
    memset(buf, 'a', 500);
    buf[500] = '\0';
    bunny_tag_query_node_t *root = NULL;
    TEST_ASSERT_TRUE(bunny_tag_query_parse(buf, BUNNY_TAG_QUERY_DIALECT_INKBUNNY, &root, NULL));
    TEST_ASSERT_NOT_NULL(root);
    bunny_tag_query_free(root);

    const char tag[] = "caf\xc3\xa9";
    bunny_tag_query_node_t *root2 = NULL;
    TEST_ASSERT_TRUE(bunny_tag_query_parse(tag, BUNNY_TAG_QUERY_DIALECT_INKBUNNY, &root2, NULL));
    TEST_ASSERT_NOT_NULL(root2);
    const char *tags[] = {tag};
    TEST_ASSERT_TRUE(bunny_tag_query_matches(root2, tags, 1));
    bunny_tag_query_free(root2);
}

void test_inkbunny_rejects_a_bare_dash_surrounded_by_whitespace(void)
{
    bunny_tag_query_node_t *root = NULL;
    size_t error_pos = 999;
    TEST_ASSERT_FALSE(bunny_tag_query_parse("   -   ", BUNNY_TAG_QUERY_DIALECT_INKBUNNY, &root, &error_pos));
    TEST_ASSERT_NULL(root);
    TEST_ASSERT_EQUAL(4, (int)error_pos);
}

void test_inkbunny_accepts_tabs_and_multiple_spaces_as_separators(void)
{
    bunny_tag_query_node_t *root = NULL;
    TEST_ASSERT_TRUE(bunny_tag_query_parse("leopard\t\t-snow   tiger", BUNNY_TAG_QUERY_DIALECT_INKBUNNY, &root, NULL));
    TEST_ASSERT_NOT_NULL(root);
    const char *tags[] = {"leopard", "tiger"};
    TEST_ASSERT_TRUE(bunny_tag_query_matches(root, tags, 2));
    bunny_tag_query_free(root);
}

/* --- Validate-only surface ---------------------------------------------- */

void test_validate_matches_parse_success_and_failure(void)
{
    TEST_ASSERT_TRUE(bunny_tag_query_validate("cat ~dog -bird ( ~a ~b )", BUNNY_TAG_QUERY_DIALECT_E621, NULL));
    size_t error_pos = 999;
    TEST_ASSERT_FALSE(bunny_tag_query_validate("(  )", BUNNY_TAG_QUERY_DIALECT_E621, &error_pos));
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
    RUN_TEST(test_parse_rejects_50_levels_of_nesting_at_the_same_11th_position);
    RUN_TEST(test_parse_depth_is_scoped_per_branch_not_cumulative_across_siblings);
    RUN_TEST(test_parse_accepts_exactly_40_tags_on_e621);
    RUN_TEST(test_parse_rejects_41_tags_on_e621_at_the_41st_tag);
    RUN_TEST(test_parse_40_tag_limit_counts_tags_nested_inside_groups_too);
    RUN_TEST(test_parse_rejects_an_empty_group_at_the_open_paren);
    RUN_TEST(test_parse_rejects_a_missing_space_right_after_open_paren);
    RUN_TEST(test_parse_rejects_a_missing_space_right_before_close_paren);
    RUN_TEST(test_parse_rejects_an_unmatched_close_paren);
    RUN_TEST(test_parse_rejects_an_unterminated_group);
    RUN_TEST(test_parse_rejects_a_bare_operator_with_nothing_after_it);
    RUN_TEST(test_parse_rejects_a_term_directly_glued_to_a_following_group_with_no_space);
    RUN_TEST(test_parse_rejects_a_term_directly_glued_after_a_closing_group_with_no_space);
    RUN_TEST(test_parse_rejects_a_stray_close_paren_after_a_properly_closed_group);
    RUN_TEST(test_parse_rejects_an_empty_group_nested_two_levels_deep);
    RUN_TEST(test_parse_rejects_a_bare_dash_surrounded_by_whitespace);
    RUN_TEST(test_parse_treats_stacked_leading_operators_as_literal_tag_text);
    RUN_TEST(test_parse_wildcard_matches_up_to_the_first_asterisk_even_with_several);
    RUN_TEST(test_parse_accepts_a_very_long_tag_name);
    RUN_TEST(test_parse_accepts_a_tag_containing_multibyte_utf8_bytes);
    RUN_TEST(test_parse_accepts_tabs_and_multiple_spaces_as_separators);
    RUN_TEST(test_parse_accepts_consecutive_sibling_groups);
    RUN_TEST(test_parse_double_negation_of_nested_groups_cancels_out);
    RUN_TEST(test_inkbunny_accepts_bare_words_and_negation);
    RUN_TEST(test_inkbunny_rejects_or_syntax);
    RUN_TEST(test_inkbunny_rejects_wildcard_syntax);
    RUN_TEST(test_inkbunny_rejects_group_syntax);
    RUN_TEST(test_inkbunny_accepts_the_same_valid_syntax_e621_would_parse_identically);
    RUN_TEST(test_inkbunny_has_no_40_tag_limit);
    RUN_TEST(test_inkbunny_rejects_a_group_wherever_the_open_paren_appears);
    RUN_TEST(test_inkbunny_rejects_a_leading_tilde_even_when_followed_by_more_tildes);
    RUN_TEST(test_inkbunny_treats_a_stacked_leading_dash_as_literal_tag_text);
    RUN_TEST(test_inkbunny_rejects_a_wildcard_asterisk_anywhere_in_a_tag);
    RUN_TEST(test_inkbunny_accepts_a_long_tag_and_multibyte_utf8_text);
    RUN_TEST(test_inkbunny_rejects_a_bare_dash_surrounded_by_whitespace);
    RUN_TEST(test_inkbunny_accepts_tabs_and_multiple_spaces_as_separators);
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
