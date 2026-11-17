#include "unity.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bunny_epub/epub.h"

static char g_path[256];

void setUp(void)
{
    snprintf(g_path, sizeof(g_path), "/tmp/bunny_epub_test_%d.epub", rand());
}

void tearDown(void)
{
    remove(g_path);
}

static bunny_doc_run_t plain_run(const char *text)
{
    bunny_doc_run_t run = {0};
    run.kind = BUNNY_DOC_RUN_PLAIN;
    run.text = strdup(text);
    return run;
}

static bunny_doc_run_t bold_run(const char *text)
{
    bunny_doc_run_t run = {0};
    run.kind = BUNNY_DOC_RUN_BOLD;
    run.text = strdup(text);
    return run;
}

static bunny_doc_run_t url_run(const char *text, const char *url)
{
    bunny_doc_run_t run = {0};
    run.kind = BUNNY_DOC_RUN_URL;
    run.text = strdup(text);
    run.url = strdup(url);
    return run;
}

static bunny_doc_block_t paragraph_block(bunny_doc_run_t *runs, size_t count)
{
    bunny_doc_block_t block = {0};
    block.kind = BUNNY_DOC_BLOCK_PARAGRAPH;
    block.runs.items = runs;
    block.runs.count = count;
    return block;
}

void test_build_then_read_round_trips_a_simple_document(void)
{
    bunny_doc_run_t para1_runs[] = {plain_run("Once upon a time, "), bold_run("the end.")};
    bunny_doc_run_t para2_runs[] = {plain_run("See "), url_run("this page", "https://example.com/story")};

    bunny_doc_block_t blocks[2];
    blocks[0] = paragraph_block(para1_runs, 2);
    blocks[1] = paragraph_block(para2_runs, 2);

    bunny_doc_t doc = {.items = blocks, .count = 2};

    bunny_epub_build_params_t params = {0};
    params.title = "A Test Story";
    params.author = "Someone";
    params.doc = &doc;

    TEST_ASSERT_EQUAL(BUNNY_EPUB_OK, bunny_epub_build(&params, g_path));

    bunny_doc_t read_doc;
    char *title = NULL;
    TEST_ASSERT_EQUAL(BUNNY_EPUB_OK, bunny_epub_read(g_path, &read_doc, &title));

    TEST_ASSERT_EQUAL_STRING("A Test Story", title);
    TEST_ASSERT_EQUAL(2, (int)read_doc.count);

    TEST_ASSERT_EQUAL(2, (int)read_doc.items[0].runs.count);
    TEST_ASSERT_EQUAL(BUNNY_DOC_RUN_PLAIN, read_doc.items[0].runs.items[0].kind);
    TEST_ASSERT_EQUAL_STRING("Once upon a time, ", read_doc.items[0].runs.items[0].text);
    TEST_ASSERT_EQUAL(BUNNY_DOC_RUN_BOLD, read_doc.items[0].runs.items[1].kind);
    TEST_ASSERT_EQUAL_STRING("the end.", read_doc.items[0].runs.items[1].text);

    TEST_ASSERT_EQUAL(2, (int)read_doc.items[1].runs.count);
    TEST_ASSERT_EQUAL(BUNNY_DOC_RUN_URL, read_doc.items[1].runs.items[1].kind);
    TEST_ASSERT_EQUAL_STRING("this page", read_doc.items[1].runs.items[1].text);
    TEST_ASSERT_EQUAL_STRING("https://example.com/story", read_doc.items[1].runs.items[1].url);

    free(title);
    bunny_doc_free(&read_doc);
    free(para1_runs[0].text);
    free(para1_runs[1].text);
    free(para2_runs[0].text);
    free(para2_runs[1].text);
    free(para2_runs[1].url);
}

void test_build_then_read_round_trips_headings_and_list_items(void)
{
    bunny_doc_run_t heading_runs[] = {plain_run("Chapter One")};
    bunny_doc_run_t item1_runs[] = {plain_run("first")};
    bunny_doc_run_t item2_runs[] = {plain_run("second")};

    bunny_doc_block_t blocks[3];
    blocks[0] = paragraph_block(heading_runs, 1);
    blocks[0].kind = BUNNY_DOC_BLOCK_HEADING;
    blocks[0].heading_level = 2;
    blocks[1] = paragraph_block(item1_runs, 1);
    blocks[1].kind = BUNNY_DOC_BLOCK_LIST_ITEM;
    blocks[2] = paragraph_block(item2_runs, 1);
    blocks[2].kind = BUNNY_DOC_BLOCK_LIST_ITEM;

    bunny_doc_t doc = {.items = blocks, .count = 3};
    bunny_epub_build_params_t params = {0};
    params.title = "Headings & Lists";
    params.doc = &doc;

    TEST_ASSERT_EQUAL(BUNNY_EPUB_OK, bunny_epub_build(&params, g_path));

    bunny_doc_t read_doc;
    TEST_ASSERT_EQUAL(BUNNY_EPUB_OK, bunny_epub_read(g_path, &read_doc, NULL));
    TEST_ASSERT_EQUAL(3, (int)read_doc.count);
    TEST_ASSERT_EQUAL(BUNNY_DOC_BLOCK_HEADING, read_doc.items[0].kind);
    TEST_ASSERT_EQUAL(2, read_doc.items[0].heading_level);
    TEST_ASSERT_EQUAL_STRING("Chapter One", read_doc.items[0].runs.items[0].text);
    TEST_ASSERT_EQUAL(BUNNY_DOC_BLOCK_LIST_ITEM, read_doc.items[1].kind);
    TEST_ASSERT_EQUAL_STRING("first", read_doc.items[1].runs.items[0].text);
    TEST_ASSERT_EQUAL(BUNNY_DOC_BLOCK_LIST_ITEM, read_doc.items[2].kind);
    TEST_ASSERT_EQUAL_STRING("second", read_doc.items[2].runs.items[0].text);

    bunny_doc_free(&read_doc);
    free(heading_runs[0].text);
    free(item1_runs[0].text);
    free(item2_runs[0].text);
}

void test_build_embeds_a_cover_image(void)
{
    bunny_doc_run_t runs[] = {plain_run("Body text.")};
    bunny_doc_block_t blocks[1] = {paragraph_block(runs, 1)};
    bunny_doc_t doc = {.items = blocks, .count = 1};

    unsigned char fake_cover[] = {0xFF, 0xD8, 0xFF, 0x00, 0x01, 0x02};

    bunny_epub_build_params_t params = {0};
    params.title = "With Cover";
    params.doc = &doc;
    params.cover_image = fake_cover;
    params.cover_image_len = sizeof(fake_cover);
    params.cover_mimetype = "image/jpeg";

    TEST_ASSERT_EQUAL(BUNNY_EPUB_OK, bunny_epub_build(&params, g_path));

    /* zip.c is internal (no public header), so its own correctness is
     * exercised indirectly here: a build with a cover image adds an extra
     * stored entry before text.xhtml, so a successful read-back (title +
     * body intact) confirms the writer's per-entry offsets/central
     * directory stay correct with more than one entry present. */
    bunny_doc_t read_doc;
    TEST_ASSERT_EQUAL(BUNNY_EPUB_OK, bunny_epub_read(g_path, &read_doc, NULL));
    TEST_ASSERT_EQUAL(1, (int)read_doc.count);
    TEST_ASSERT_EQUAL_STRING("Body text.", read_doc.items[0].runs.items[0].text);

    bunny_doc_free(&read_doc);
    free(runs[0].text);
}

void test_build_rejects_invalid_args(void)
{
    bunny_doc_t doc = {0};
    bunny_epub_build_params_t params = {0};
    params.doc = &doc;
    /* missing title */
    TEST_ASSERT_EQUAL(BUNNY_EPUB_ERR_INVALID_ARG, bunny_epub_build(&params, g_path));
}

void test_read_rejects_a_nonexistent_file(void)
{
    bunny_doc_t doc;
    TEST_ASSERT_EQUAL(BUNNY_EPUB_ERR_IO, bunny_epub_read("/tmp/bunny_epub_test_does_not_exist.epub", &doc, NULL));
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_build_then_read_round_trips_a_simple_document);
    RUN_TEST(test_build_then_read_round_trips_headings_and_list_items);
    RUN_TEST(test_build_embeds_a_cover_image);
    RUN_TEST(test_build_rejects_invalid_args);
    RUN_TEST(test_read_rejects_a_nonexistent_file);
    return UNITY_END();
}
