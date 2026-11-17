#include "unity.h"

#include <string.h>

#include "bunny_bbcode/bbcode.h"

void setUp(void)
{}
void tearDown(void)
{}

static bunny_doc_t parse(const char *bbcode)
{
    bunny_doc_t doc;
    TEST_ASSERT_EQUAL(BUNNY_BBCODE_OK, bunny_bbcode_parse(bbcode, &doc));
    return doc;
}

void test_plain_text_becomes_one_paragraph_with_one_plain_run(void)
{
    bunny_doc_t doc = parse("Once upon a time.");
    TEST_ASSERT_EQUAL(1, (int)doc.count);
    TEST_ASSERT_EQUAL(BUNNY_DOC_BLOCK_PARAGRAPH, doc.items[0].kind);
    TEST_ASSERT_EQUAL(1, (int)doc.items[0].runs.count);
    TEST_ASSERT_EQUAL(BUNNY_DOC_RUN_PLAIN, doc.items[0].runs.items[0].kind);
    TEST_ASSERT_EQUAL_STRING("Once upon a time.", doc.items[0].runs.items[0].text);
    bunny_doc_free(&doc);
}

void test_blank_line_splits_into_two_paragraphs(void)
{
    bunny_doc_t doc = parse("First paragraph.\n\nSecond paragraph.");
    TEST_ASSERT_EQUAL(2, (int)doc.count);
    TEST_ASSERT_EQUAL_STRING("First paragraph.", doc.items[0].runs.items[0].text);
    TEST_ASSERT_EQUAL_STRING("Second paragraph.", doc.items[1].runs.items[0].text);
    bunny_doc_free(&doc);
}

void test_single_newline_is_a_soft_break_joined_with_a_space(void)
{
    bunny_doc_t doc = parse("First line\nsecond line.");
    TEST_ASSERT_EQUAL(1, (int)doc.count);
    TEST_ASSERT_EQUAL(1, (int)doc.items[0].runs.count);
    TEST_ASSERT_EQUAL_STRING("First line second line.", doc.items[0].runs.items[0].text);
    bunny_doc_free(&doc);
}

void test_bold_tag_produces_a_bold_run(void)
{
    bunny_doc_t doc = parse("plain [b]bold[/b] plain");
    TEST_ASSERT_EQUAL(1, (int)doc.count);
    bunny_doc_run_list_t runs = doc.items[0].runs;
    TEST_ASSERT_EQUAL(3, (int)runs.count);
    TEST_ASSERT_EQUAL(BUNNY_DOC_RUN_PLAIN, runs.items[0].kind);
    TEST_ASSERT_EQUAL_STRING("plain ", runs.items[0].text);
    TEST_ASSERT_EQUAL(BUNNY_DOC_RUN_BOLD, runs.items[1].kind);
    TEST_ASSERT_EQUAL_STRING("bold", runs.items[1].text);
    TEST_ASSERT_EQUAL(BUNNY_DOC_RUN_PLAIN, runs.items[2].kind);
    TEST_ASSERT_EQUAL_STRING(" plain", runs.items[2].text);
    bunny_doc_free(&doc);
}

void test_italic_and_underline_tags(void)
{
    bunny_doc_t doc = parse("[i]italic[/i] [u]underline[/u]");
    bunny_doc_run_list_t runs = doc.items[0].runs;
    TEST_ASSERT_EQUAL(3, (int)runs.count);
    TEST_ASSERT_EQUAL(BUNNY_DOC_RUN_ITALIC, runs.items[0].kind);
    TEST_ASSERT_EQUAL_STRING("italic", runs.items[0].text);
    TEST_ASSERT_EQUAL(BUNNY_DOC_RUN_UNDERLINE, runs.items[2].kind);
    TEST_ASSERT_EQUAL_STRING("underline", runs.items[2].text);
    bunny_doc_free(&doc);
}

void test_nested_bold_italic_innermost_style_wins(void)
{
    /* The shared run model has one kind per run, not a combinable style
     * set -- nested styling collapses to whichever tag is innermost,
     * a deliberate, documented simplification. */
    bunny_doc_t doc = parse("[b]bold [i]both[/i] still bold[/b]");
    bunny_doc_run_list_t runs = doc.items[0].runs;
    TEST_ASSERT_EQUAL(3, (int)runs.count);
    TEST_ASSERT_EQUAL(BUNNY_DOC_RUN_BOLD, runs.items[0].kind);
    TEST_ASSERT_EQUAL_STRING("bold ", runs.items[0].text);
    TEST_ASSERT_EQUAL(BUNNY_DOC_RUN_ITALIC, runs.items[1].kind);
    TEST_ASSERT_EQUAL_STRING("both", runs.items[1].text);
    TEST_ASSERT_EQUAL(BUNNY_DOC_RUN_BOLD, runs.items[2].kind);
    TEST_ASSERT_EQUAL_STRING(" still bold", runs.items[2].text);
    bunny_doc_free(&doc);
}

void test_url_tag_with_attribute_and_label(void)
{
    bunny_doc_t doc = parse("see [url=https://e621.net]this site[/url] now");
    bunny_doc_run_list_t runs = doc.items[0].runs;
    TEST_ASSERT_EQUAL(3, (int)runs.count);
    TEST_ASSERT_EQUAL(BUNNY_DOC_RUN_URL, runs.items[1].kind);
    TEST_ASSERT_EQUAL_STRING("this site", runs.items[1].text);
    TEST_ASSERT_EQUAL_STRING("https://e621.net", runs.items[1].url);
    bunny_doc_free(&doc);
}

void test_url_tag_without_attribute_uses_content_as_both_text_and_url(void)
{
    bunny_doc_t doc = parse("[url]https://e621.net[/url]");
    bunny_doc_run_list_t runs = doc.items[0].runs;
    TEST_ASSERT_EQUAL(1, (int)runs.count);
    TEST_ASSERT_EQUAL(BUNNY_DOC_RUN_URL, runs.items[0].kind);
    TEST_ASSERT_EQUAL_STRING("https://e621.net", runs.items[0].text);
    TEST_ASSERT_EQUAL_STRING("https://e621.net", runs.items[0].url);
    bunny_doc_free(&doc);
}

void test_bare_url_is_detected_and_trailing_punctuation_trimmed(void)
{
    bunny_doc_t doc = parse("check https://example.com/page, it's great.");
    bunny_doc_run_list_t runs = doc.items[0].runs;
    TEST_ASSERT_EQUAL(3, (int)runs.count);
    TEST_ASSERT_EQUAL(BUNNY_DOC_RUN_URL, runs.items[1].kind);
    TEST_ASSERT_EQUAL_STRING("https://example.com/page", runs.items[1].text);
    bunny_doc_free(&doc);
}

void test_img_tag_renders_as_a_url_run_not_a_fetched_image(void)
{
    bunny_doc_t doc = parse("look [img]https://example.com/pic.png[/img] nice");
    bunny_doc_run_list_t runs = doc.items[0].runs;
    TEST_ASSERT_EQUAL(3, (int)runs.count);
    TEST_ASSERT_EQUAL(BUNNY_DOC_RUN_URL, runs.items[1].kind);
    TEST_ASSERT_EQUAL_STRING("https://example.com/pic.png", runs.items[1].url);
    bunny_doc_free(&doc);
}

void test_unknown_tag_degrades_to_plain_text_keeping_content(void)
{
    bunny_doc_t doc = parse("before [spoiler]secret[/spoiler] after");
    bunny_doc_run_list_t runs = doc.items[0].runs;
    TEST_ASSERT_EQUAL(1, (int)runs.count);
    TEST_ASSERT_EQUAL(BUNNY_DOC_RUN_PLAIN, runs.items[0].kind);
    TEST_ASSERT_EQUAL_STRING("before secret after", runs.items[0].text);
    bunny_doc_free(&doc);
}

void test_stray_mismatched_closing_tag_is_ignored_without_crashing(void)
{
    bunny_doc_t doc = parse("oops[/b] fine");
    bunny_doc_run_list_t runs = doc.items[0].runs;
    TEST_ASSERT_EQUAL(1, (int)runs.count);
    TEST_ASSERT_EQUAL_STRING("oops fine", runs.items[0].text);
    bunny_doc_free(&doc);
}

void test_unclosed_bold_tag_runs_to_end_of_text_without_crashing(void)
{
    bunny_doc_t doc = parse("[b]never closes");
    bunny_doc_run_list_t runs = doc.items[0].runs;
    TEST_ASSERT_EQUAL(1, (int)runs.count);
    TEST_ASSERT_EQUAL(BUNNY_DOC_RUN_BOLD, runs.items[0].kind);
    TEST_ASSERT_EQUAL_STRING("never closes", runs.items[0].text);
    bunny_doc_free(&doc);
}

void test_list_block_produces_one_list_item_block_per_star(void)
{
    bunny_doc_t doc = parse("intro\n\n[list]\n[*]first item\n[*]second item\n[/list]\n\noutro");
    TEST_ASSERT_EQUAL(4, (int)doc.count);
    TEST_ASSERT_EQUAL(BUNNY_DOC_BLOCK_PARAGRAPH, doc.items[0].kind);
    TEST_ASSERT_EQUAL_STRING("intro", doc.items[0].runs.items[0].text);
    TEST_ASSERT_EQUAL(BUNNY_DOC_BLOCK_LIST_ITEM, doc.items[1].kind);
    TEST_ASSERT_EQUAL_STRING("first item", doc.items[1].runs.items[0].text);
    TEST_ASSERT_EQUAL(BUNNY_DOC_BLOCK_LIST_ITEM, doc.items[2].kind);
    TEST_ASSERT_EQUAL_STRING("second item", doc.items[2].runs.items[0].text);
    TEST_ASSERT_EQUAL(BUNNY_DOC_BLOCK_PARAGRAPH, doc.items[3].kind);
    TEST_ASSERT_EQUAL_STRING("outro", doc.items[3].runs.items[0].text);
    bunny_doc_free(&doc);
}

void test_heading_tag_produces_a_heading_block_with_its_level(void)
{
    bunny_doc_t doc = parse("[h2]Chapter One[/h2]\n\nbody text");
    TEST_ASSERT_EQUAL(2, (int)doc.count);
    TEST_ASSERT_EQUAL(BUNNY_DOC_BLOCK_HEADING, doc.items[0].kind);
    TEST_ASSERT_EQUAL(2, doc.items[0].heading_level);
    TEST_ASSERT_EQUAL_STRING("Chapter One", doc.items[0].runs.items[0].text);
    TEST_ASSERT_EQUAL(BUNNY_DOC_BLOCK_PARAGRAPH, doc.items[1].kind);
    bunny_doc_free(&doc);
}

void test_empty_input_produces_zero_blocks(void)
{
    bunny_doc_t doc = parse("");
    TEST_ASSERT_EQUAL(0, (int)doc.count);
    bunny_doc_free(&doc);
}

void test_invalid_args_are_rejected(void)
{
    bunny_doc_t doc;
    TEST_ASSERT_EQUAL(BUNNY_BBCODE_ERR_INVALID_ARG, bunny_bbcode_parse(NULL, &doc));
    TEST_ASSERT_EQUAL(BUNNY_BBCODE_ERR_INVALID_ARG, bunny_bbcode_parse("text", NULL));
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_plain_text_becomes_one_paragraph_with_one_plain_run);
    RUN_TEST(test_blank_line_splits_into_two_paragraphs);
    RUN_TEST(test_single_newline_is_a_soft_break_joined_with_a_space);
    RUN_TEST(test_bold_tag_produces_a_bold_run);
    RUN_TEST(test_italic_and_underline_tags);
    RUN_TEST(test_nested_bold_italic_innermost_style_wins);
    RUN_TEST(test_url_tag_with_attribute_and_label);
    RUN_TEST(test_url_tag_without_attribute_uses_content_as_both_text_and_url);
    RUN_TEST(test_bare_url_is_detected_and_trailing_punctuation_trimmed);
    RUN_TEST(test_img_tag_renders_as_a_url_run_not_a_fetched_image);
    RUN_TEST(test_unknown_tag_degrades_to_plain_text_keeping_content);
    RUN_TEST(test_stray_mismatched_closing_tag_is_ignored_without_crashing);
    RUN_TEST(test_unclosed_bold_tag_runs_to_end_of_text_without_crashing);
    RUN_TEST(test_list_block_produces_one_list_item_block_per_star);
    RUN_TEST(test_heading_tag_produces_a_heading_block_with_its_level);
    RUN_TEST(test_empty_input_produces_zero_blocks);
    RUN_TEST(test_invalid_args_are_rejected);
    return UNITY_END();
}
